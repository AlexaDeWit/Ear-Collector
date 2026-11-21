-- Your deaths to enemy players in the open world, from the death recap. They
-- fill the Rivals tab's "Deaths" column and build up vengeance (Core/Deaths.lua).
--
-- Forever gives addons no combat log, so the death recap (C_DeathRecap) is the
-- only record of who killed you. Its events name the source by `sourceName`
-- only, with no GUID, and NPCs appear too. So at the moment of death the addon
-- notes the enemy players it can see (target, focus, mouseover, nameplates),
-- and a moment later matches the recap's killing blow to one of them. A match
-- gives the killer's GUID, which keys Rivals and vengeance, and proves the
-- killer was a player. No match, no record: a wrong rival is worse than none.
--
-- Unverified in game (T4): whether Forever fills the recap at all (Blizzard's
-- recap window only loads on Retail, though C_DeathRecap is documented for every
-- client), and how sourceName is written. With /ears debug on, every death logs
-- what the recap held and why it did or didn't count.
local _, ns = ...

local Context, Deaths, Errors = ns.Context, ns.Deaths, ns.Errors
local Readable = Context.Readable

Deaths.RECAP_DELAY = 1 -- seconds after death before reading the recap
Deaths.NAMEPLATES = 40 -- nameplate1 .. nameplateN

local function isTrue(value)
	return Readable(value) and value == true
end

-- Note `unit` if it's an enemy player whose name and GUID are readable.
local function see(seen, unit)
	if not isTrue(UnitExists(unit)) or not isTrue(UnitIsPlayer(unit)) or not isTrue(UnitCanAttack("player", unit)) then
		return
	end
	local name, guid = UnitName(unit), UnitGUID(unit)
	if Readable(name) and type(name) == "string" and Readable(guid) and type(guid) == "string" then
		Deaths.See(seen, name, guid)
	end
end

--- Enemy players you can see right now, by name.
---@return table<string, string|false>
function Deaths.EnemiesInView()
	local seen = {}
	for _, unit in ipairs({ "target", "focus", "mouseover" }) do
		see(seen, unit)
	end
	for i = 1, Deaths.NAMEPLATES do
		see(seen, "nameplate" .. i)
	end
	return seen
end

--- Read the recap and record the death if the killing blow was an enemy player
--- seen at the moment of death.
---@param seen table<string, string|false>
local function readRecap(seen)
	local db = ns.db
	if not db then
		return
	end
	local has = C_DeathRecap.HasRecapEvents()
	if not isTrue(has) then
		ns.Trace(db, "PLAYER_DEAD", nil, nil, "no death recap")
		return
	end
	local name, spell = Deaths.KillerFromRecap(C_DeathRecap.GetRecapEvents())
	if not name then
		ns.Trace(db, "PLAYER_DEAD", nil, nil, "recap names no killer")
		return
	end
	local guid = Deaths.MatchKiller(name, seen)
	if not guid then
		ns.Trace(db, "PLAYER_DEAD", name, nil, "killer isn't an enemy player you could see")
		return
	end
	local killer = ns.VictimDetails(guid)
	if not killer then
		ns.Trace(db, "PLAYER_DEAD", name, guid, "killer's details hidden")
		return
	end
	local _, debt = ns.RecordDeath(db, killer, spell)
	ns.Trace(db, "PLAYER_DEAD", name, guid, ("death recorded (%d since you last killed them)"):format(debt))
end

ns.On("PLAYER_DEAD", function()
	local db = ns.db
	if not db then
		return
	end
	local counts, reason = Context.Current(db.settings)
	if not counts then
		ns.Trace(db, "PLAYER_DEAD", nil, nil, "ignored: " .. reason)
		return
	end
	local seen = Deaths.EnemiesInView()
	C_Timer.After(
		Deaths.RECAP_DELAY,
		Errors.Wrap("death recap", function()
			readRecap(seen)
		end)
	)
end)
