-- The game's damage meter (C_DamageMeter), read after a fight: it lists the
-- enemies you and your group damaged. That's the evidence for an assist no honor
-- named, and a way to put a GUID to your killer's name. Its data is secret in
-- combat, so it's read when combat ends, and only when a death waits on it.
local _, ns = ...

local Assists, Context, Errors = ns.Assists, ns.Context, ns.Errors
local Readable = Context.Readable

local DamageMeter = {}
ns.DamageMeter = DamageMeter

DamageMeter.SETTLE = 0.5 -- seconds after combat ends before reading the meter
DamageMeter.QUEUE_SIZE = 20 -- unclaimed deaths waiting for a check, at most

local fight -- your latest fight: { start, finish } in GetTime(), and its meter sessionID
local noted -- the newest meter session when your last fight ended (or at login)
local queue = {} -- unclaimed deaths waiting for the meter
local checkScheduled = false

local function isTrue(value)
	return Readable(value) and value == true
end

-- The newest session ID in a GetAvailableCombatSessions() list.
local function latestSessionID(sessions)
	if not Readable(sessions) or type(sessions) ~= "table" then
		return nil
	end
	local latest
	for _, session in ipairs(sessions) do
		local id = Readable(session) and type(session) == "table" and session.sessionID
		if Readable(id) and type(id) == "number" and (not latest or id > latest) then
			latest = id
		end
	end
	return latest
end

--- Enemy players you or your group damaged in your latest fight (and in the
--- meter sessions `sessionIDs` names), by GUID, with their name when it's
--- readable (false when not).
---@param sessionIDs table<number, true>? more sessions to read
---@return table<string, string|false>|nil damaged nil when the meter can't be read
---@return string|nil reason why it can't
function DamageMeter.EnemyPlayers(sessionIDs)
	local meter = C_DamageMeter
	local types = Enum.DamageMeterType
	local sessionTypes = Enum.DamageMeterSessionType
	if not meter or not types or not sessionTypes then
		return nil, "no damage meter"
	end
	if Context.InCombat() then
		return nil, "in combat"
	end
	if not isTrue(meter.IsDamageMeterAvailable()) then
		return nil, "damage meter unavailable"
	end
	local damaged, readAny = {}, false
	local function read(session)
		if not Readable(session) or type(session) ~= "table" then
			return
		end
		local sources = session.combatSources
		if not Readable(sources) or type(sources) ~= "table" then
			return
		end
		readAny = true
		for _, source in ipairs(sources) do
			if Readable(source) and type(source) == "table" then
				local guid, name, amount = source.sourceGUID, source.name, source.totalAmount
				if
					Readable(guid)
					and type(guid) == "string"
					and guid:find("^Player%-")
					and Readable(amount)
					and type(amount) == "number"
					and amount > 0
				then
					damaged[guid] = Readable(name) and type(name) == "string" and name ~= "" and name or false
				end
			end
		end
	end
	read(meter.GetCombatSessionFromType(sessionTypes.Current, types.EnemyDamageTaken))
	local ids = { [latestSessionID(meter.GetAvailableCombatSessions()) or false] = true }
	for id in pairs(sessionIDs or {}) do
		ids[id] = true
	end
	for id in pairs(ids) do
		if id then
			read(meter.GetCombatSessionFromID(id, types.EnemyDamageTaken))
		end
	end
	if not readAny then
		return nil, "no fight on the damage meter"
	end
	return damaged
end

--- Your latest fight: { start, finish? } in GetTime(), and its meter sessionID
--- once it has ended. Nil before your first fight this session.
---@return table|nil
function DamageMeter.Fight()
	return fight
end

local function check()
	checkScheduled = false
	local db = ns.db
	if not db or #queue == 0 or Context.InCombat() then
		return -- in combat, the next PLAYER_REGEN_ENABLED schedules another check
	end
	local deaths = queue
	queue = {}
	local sessionIDs = {}
	for _, death in ipairs(deaths) do
		if death.fight and death.fight.sessionID then
			sessionIDs[death.fight.sessionID] = true
		end
	end
	local damaged, reason = DamageMeter.EnemyPlayers(sessionIDs)
	if not damaged then
		for _, death in ipairs(deaths) do
			ns.Trace(db, "DAMAGE_METER", nil, death.guid, "no assist: " .. tostring(reason))
		end
		return
	end
	local assists, rejected = Assists.FromDamage(deaths, damaged, fight)
	for _, kill in ipairs(assists) do
		kill.by = "assist"
		local _, isNew = ns.Collect(db, kill)
		ns.Trace(db, "DAMAGE_METER", nil, kill.guid, isNew and "new ear (assist, damage)" or "camped (assist, damage)")
	end
	for _, r in ipairs(rejected) do
		ns.Trace(db, "DAMAGE_METER", nil, r.guid, "no assist: " .. r.reason)
	end
end

local checkWrapped = Errors.Wrap("damage meter", check)

local function schedule()
	if checkScheduled or Context.InCombat() then
		return
	end
	checkScheduled = true
	C_Timer.After(DamageMeter.SETTLE, checkWrapped)
end

--- Hold deaths no honor named until the meter can say whether you took part.
--- Out of combat, with your last fight settled on the meter, they're checked at
--- once. Runs inside Errors.Call.
---@param deaths { guid: string, t: number, kill: EarCollector.Kill, fight: table? }[]
function DamageMeter.Queue(deaths)
	for _, death in ipairs(deaths) do
		death.fight = death.fight or fight -- the fight it happened in, or after
		queue[#queue + 1] = death
		if #queue > DamageMeter.QUEUE_SIZE then
			table.remove(queue, 1)
		end
	end
	if #queue == 0 then
		return
	end
	local settled = fight and fight.finish and GetTime() - fight.finish >= DamageMeter.SETTLE
	if settled and not checkScheduled and not Context.InCombat() then
		checkWrapped()
	else
		schedule()
	end
end

local function newestSession()
	local meter = C_DamageMeter
	return meter and latestSessionID(meter.GetAvailableCombatSessions()) or nil
end

ns.On("PLAYER_ENTERING_WORLD", function()
	if not Context.InCombat() then
		noted = newestSession()
	end
end)

ns.On("PLAYER_REGEN_DISABLED", function()
	fight = { start = GetTime() }
end)

ns.On("PLAYER_REGEN_ENABLED", function()
	if fight and not fight.finish then
		fight.finish = GetTime()
		-- The session list isn't secret, so the fight's session can be noted now.
		-- If the newest is the one noted before, the meter kept no record of this fight.
		local newest = newestSession()
		fight.sessionID = newest ~= noted and newest or nil
		noted = newest
	end
	if #queue > 0 then
		schedule()
	end
end)
