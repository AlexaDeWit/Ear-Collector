-- Fight facts: what the game tells an addon about the fight an ear came from,
-- for Core/Appraisal.lua. At the kill it notes how long the fight had run and
-- the victim's health; the damage meter is read when the fight ends, since it's
-- secret in combat. An ear taken in combat waits here, then is graded and
-- announced. One taken out of combat is graded at once.
local _, ns = ...

local Appraisal, Context, DamageMeter, Errors = ns.Appraisal, ns.Context, ns.DamageMeter, ns.Errors
local Readable = Context.Readable

local FightFacts = {}
ns.FightFacts = FightFacts

FightFacts.WAIT = 30 -- seconds in combat after a kill before its pop-up shows ungraded
FightFacts.PENDING = 20 -- ears waiting for their fight to end, at most

local pending = {} ---@type table[] { ear, kill, fight, secs, health, shown }
local scheduled = false

local function number(value)
	return Readable(value) and type(value) == "number" and value or nil
end

local function round(value, places)
	if not value then
		return nil
	end
	local scale = 10 ^ (places or 1)
	return math.floor(value * scale + 0.5) / scale
end

-- The victim's maximum health, from a unit showing them at the kill. A
-- percentage (100) or less says nothing about how tough they were.
local function victimHealth(guid)
	local units = { "target", "focus", "mouseover" }
	for _, unit in ipairs(ns.DeathWatch and ns.DeathWatch.NameplateUnits() or {}) do
		units[#units + 1] = unit
	end
	for _, unit in ipairs(units) do
		local unitGUID = UnitGUID(unit)
		if Readable(unitGUID) and unitGUID == guid then
			local health = number(UnitHealthMax(unit))
			if health and health > 100 then
				return health
			end
		end
	end
	return nil
end

-- One meter view of a fight: your amount, everyone else's, how many sources
-- had one, and the enemy players among them. Nil when it can't be read.
local function view(sessionID, kind)
	local meter = C_DamageMeter
	local session = sessionID and meter.GetCombatSessionFromID(sessionID, kind)
		or meter.GetCombatSessionFromType(Enum.DamageMeterSessionType.Current, kind)
	local sources = Readable(session) and type(session) == "table" and session.combatSources
	if not Readable(sources) or type(sources) ~= "table" then
		return nil
	end
	local out = { you = 0, others = 0, count = 0, othersCount = 0, players = {} }
	for _, source in ipairs(sources) do
		local amount = Readable(source) and type(source) == "table" and number(source.totalAmount)
		if amount and amount > 0 then
			local mine = Readable(source.isLocalPlayer) and source.isLocalPlayer == true
			out.count = out.count + 1
			if mine then
				out.you = out.you + amount
			else
				out.others, out.othersCount = out.others + amount, out.othersCount + 1
			end
			local guid = source.sourceGUID
			if Readable(guid) and type(guid) == "string" and guid:find("^Player%-") then
				out.players[guid] = amount
			end
		end
	end
	return out
end

local function sum(a, b, field)
	if not a and not b then
		return nil
	end
	return (a and a[field] or 0) + (b and b[field] or 0)
end

--- What the meter says about `entry`'s fight. Out of combat only.
---@param entry { ear: table, fight: table?, secs: number?, health: number? }
---@return EarCollector.FightFacts
function FightFacts.Read(entry)
	local meter, types = C_DamageMeter, Enum.DamageMeterType
	if not entry.fight or not meter or not types or not Enum.DamageMeterSessionType or Context.InCombat() then
		return { read = false }
	end
	local available = meter.IsDamageMeterAvailable()
	if not Readable(available) or available ~= true then
		return { read = false }
	end
	local id = entry.fight.sessionID
	local enemies, taken = view(id, types.EnemyDamageTaken), view(id, types.DamageTaken)
	local done, healing, absorbs = view(id, types.DamageDone), view(id, types.HealingDone), view(id, types.Absorbs)
	local deaths = view(id, types.Deaths)
	local recorded = (enemies and enemies.count or 0) + (taken and taken.count or 0) + (healing and healing.count or 0)
	if recorded == 0 then
		return { read = false } -- nothing on the meter for this fight
	end
	local facts = { read = true, secs = entry.secs }
	local count = 0
	for _ in pairs(enemies and enemies.players or {}) do
		count = count + 1
	end
	facts.enemies = count > 0 and count or nil
	facts.allies = 1 + math.max(done and done.othersCount or 0, healing and healing.othersCount or 0)
	local health = number(UnitHealthMax("player"))
	if health and health > 0 then
		facts.taken = taken and taken.you / health
		local healed = sum(healing, absorbs, "you")
		facts.healed = healed and healed / health
	end
	facts.sideTaken = taken and taken.you + taken.others
	local victimDamage = enemies and enemies.players[entry.ear.guid]
	facts.toughness = victimDamage and entry.health and victimDamage / entry.health
	local interrupts, dispels = view(id, types.Interrupts), view(id, types.Dispels)
	facts.disrupts = sum(interrupts, dispels, "you")
	if facts.disrupts then
		facts.disrupts = facts.disrupts + sum(interrupts, dispels, "others")
	end
	facts.allyDeaths = deaths and deaths.othersCount
	facts.died = deaths and deaths.you > 0
	return facts
end

local function describe(facts, result)
	local f = facts
	local parts = {
		("%s enemies, %s allies, %s s"):format(
			tostring(f.enemies or "?"),
			tostring(f.allies or "?"),
			tostring(round(f.secs, 0) or "?")
		),
	}
	if f.taken then
		parts[#parts + 1] = ("took %sx"):format(round(f.taken))
	end
	if f.toughness then
		parts[#parts + 1] = ("toughness %sx"):format(round(f.toughness))
	end
	if f.healed and f.healed > 0 then
		parts[#parts + 1] = ("healed %sx"):format(round(f.healed))
	end
	local bands = {}
	for _, key in ipairs(result.why) do
		bands[#bands + 1] = ("%s %+d"):format(key, result.points[key])
	end
	return ("%s; %s = %d"):format(
		f.read and table.concat(parts, ", ") or "no fight record",
		#bands > 0 and table.concat(bands, ", ") or "no bands",
		result.score
	)
end

-- Grade `entry`'s ear from its fight, saving the facts on the ear.
local function appraise(db, entry)
	local facts = FightFacts.Read(entry)
	local kill, ear = entry.kill, entry.ear
	local result = Appraisal.Appraise(kill.appraise, facts)
	local before = ear.quality
	ear.quality, ear.pending = result.quality, nil
	ear.fight = {
		read = facts.read,
		enemies = facts.enemies,
		allies = facts.allies,
		secs = round(facts.secs, 0),
		taken = round(facts.taken),
		sideTaken = facts.sideTaken,
		healed = round(facts.healed),
		toughness = round(facts.toughness),
		disrupts = facts.disrupts,
		allyDeaths = facts.allyDeaths,
		died = facts.died,
		debt = kill.appraise.debt,
		earlier = kill.appraise.earlier,
		score = result.score,
		fightScore = result.fightScore,
		why = result.why,
	}
	ns.Trace(
		db,
		"APPRAISAL",
		nil,
		ear.guid,
		("%s: %s (was %s)"):format(describe(facts, result), ns.Quality(ear.quality).name, ns.Quality(before).name)
	)
end

local function announce(db, entry)
	if db.settings.announce then
		Errors.Call("chat", ns.Chat.AnnounceAppraisal, entry.ear)
	end
	if ns.Pouch then
		Errors.Call("pouch refresh", ns.Pouch.Refresh)
	end
	if not entry.shown and ns.Toast then
		Errors.Call("toast", ns.Toast.Show, entry.ear)
	end
end

local function settle()
	scheduled = false
	local db = ns.db
	if not db or Context.InCombat() then
		return -- the next PLAYER_REGEN_ENABLED schedules another
	end
	local entries = pending
	pending = {}
	for _, entry in ipairs(entries) do
		appraise(db, entry)
		announce(db, entry)
	end
end

local settleWrapped = Errors.Wrap("fight facts", settle)

-- Still fighting after FightFacts.WAIT: show the pop-up at the ungraded grade.
local function showUngraded(entry)
	if entry.ear.pending and not entry.shown and ns.Toast then
		entry.shown = true
		ns.Toast.Show(entry.ear, "Appraising the fight")
	end
end

--- Grade a new ear from its fight: at once out of combat, else when the fight
--- ends. Runs inside ns.Collect.
---@param db table
---@param ear table
---@param kill EarCollector.Kill with `appraise` set (Appraisal.Appraise's kill)
---@return boolean waiting true when the ear waits for its fight to end
function FightFacts.Hold(db, ear, kill)
	local fight = DamageMeter.Fight()
	local entry = { ear = ear, kill = kill, fight = fight, health = victimHealth(ear.guid) }
	if fight and fight.start then
		entry.secs = (fight.finish or GetTime()) - fight.start
	end
	if not Context.InCombat() then
		appraise(db, entry)
		return false
	end
	ear.pending = true
	pending[#pending + 1] = entry
	if #pending > FightFacts.PENDING then
		local oldest = table.remove(pending, 1)
		oldest.ear.pending = nil -- keeps its ungraded grade
	end
	C_Timer.After(
		FightFacts.WAIT,
		Errors.Wrap("fight facts", function()
			showUngraded(entry)
		end)
	)
	return true
end

ns.On("PLAYER_REGEN_ENABLED", function()
	if #pending > 0 and not scheduled then
		scheduled = true
		C_Timer.After(DamageMeter.SETTLE, settleWrapped)
	end
end)
