-- Your deaths to enemy players, from the death recap. A readable player
-- sourceGUID names the killer; otherwise the recap's name must match exactly one
-- enemy player in view at the moment of death, or on the damage meter. No match,
-- no record: a wrong rival is worse than none. DeathWatch reads the game;
-- Core/Deaths.lua decides.
local _, ns = ...

local Context, Deaths, Errors = ns.Context, ns.Deaths, ns.Errors
local Readable = Context.Readable

local DeathWatch = {}
ns.DeathWatch = DeathWatch

DeathWatch.RECAP_DELAY = 1 -- seconds after death before reading the recap
DeathWatch.NAMEPLATES = 40 -- nameplate1 .. nameplateN, when C_NamePlate.GetNamePlates is missing

local function isTrue(value)
	return Readable(value) and value == true
end

-- Note `unit` if it's an enemy player whose name and GUID are readable.
local function see(seen, unit)
	if not isTrue(UnitExists(unit)) or not isTrue(UnitIsPlayer(unit)) or not isTrue(UnitCanAttack("player", unit)) then
		return
	end
	local name, server = UnitName(unit)
	local guid = UnitGUID(unit)
	if Readable(name) and type(name) == "string" and Readable(guid) and type(guid) == "string" then
		local surname = Readable(server) and type(server) == "string" and server or nil
		Deaths.See(seen, name, guid, surname)
	end
end

--- The unit tokens of the nameplates on screen (NamePlateBaseMixin:GetUnit on each
--- C_NamePlate.GetNamePlates() frame), or every numbered token without the API.
---@return string[]
function DeathWatch.NameplateUnits()
	local units = {}
	local plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates()
	if not Readable(plates) or type(plates) ~= "table" then
		for i = 1, DeathWatch.NAMEPLATES do
			units[i] = "nameplate" .. i
		end
		return units
	end
	for _, plate in ipairs(plates) do
		local getUnit = Readable(plate) and type(plate) == "table" and plate.GetUnit
		local unit = type(getUnit) == "function" and getUnit(plate)
		if Readable(unit) and type(unit) == "string" then
			units[#units + 1] = unit
		end
	end
	return units
end

--- Enemy players you can see right now, by name.
---@return table<string, string|false>
function DeathWatch.EnemiesInView()
	local seen = {}
	for _, unit in ipairs({ "target", "focus", "mouseover" }) do
		see(seen, unit)
	end
	for _, unit in ipairs(DeathWatch.NameplateUnits()) do
		see(seen, unit)
	end
	return seen
end

DeathWatch.NAMES_LOGGED = 8 -- names in view listed when the recap's name matches none

--- The names a recap could have matched, for the debug log.
---@param seen table<string, string|false>
---@return string
function DeathWatch.NamesInView(seen)
	local names = {}
	for name, guid in pairs(seen) do
		if guid then
			names[#names + 1] = name
		end
	end
	if #names == 0 then
		return "nobody"
	end
	table.sort(names)
	local shown = table.concat(names, ", ", 1, math.min(#names, DeathWatch.NAMES_LOGGED))
	return #names > DeathWatch.NAMES_LOGGED and shown .. ", ..." or shown
end

--- Read the recap and record the death if the killing blow was an enemy player
--- seen at the moment of death, or one the damage meter says you hit.
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
	local name, spell, sourceGUID = Deaths.KillerFromRecap(C_DeathRecap.GetRecapEvents())
	if not name and not sourceGUID then
		ns.Trace(db, "PLAYER_DEAD", nil, nil, "recap names no killer")
		return
	end
	local guid, how = sourceGUID, "by GUID"
	if guid then
		local me, inGroup = UnitGUID("player"), C_PartyInfo.IsGUIDInGroup(guid)
		if not Readable(me) or guid == me or not Readable(inGroup) or inGroup then
			ns.Trace(db, "PLAYER_DEAD", guid, nil, "killer is you or in your group")
			return
		end
	else
		guid, how = Deaths.MatchKiller(name, seen), "by name"
		if not guid then
			-- Out of sight now, but on the damage meter if you or your group hit them.
			local damaged = ns.DamageMeter.EnemyPlayers()
			if damaged then
				for meterGUID, meterName in pairs(damaged) do
					if meterName then
						Deaths.See(seen, meterName, meterGUID, nil)
					end
				end
				guid, how = Deaths.MatchKiller(name, seen), "by name, from the damage meter"
			end
		end
		if not guid then
			local decision = "killer isn't an enemy player you saw or damaged (names: %s)"
			ns.Trace(db, "PLAYER_DEAD", name, nil, decision:format(DeathWatch.NamesInView(seen)))
			return
		end
	end
	local killer = ns.VictimDetails(guid)
	if not killer then
		ns.Trace(db, "PLAYER_DEAD", name, guid, "killer's details hidden")
		return
	end
	local _, debt = ns.RecordDeath(db, killer, spell)
	ns.Trace(
		db,
		"PLAYER_DEAD",
		name or guid,
		guid,
		("death recorded %s (%d since you last killed them)"):format(how, debt)
	)
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
	local seen = DeathWatch.EnemiesInView()
	C_Timer.After(
		DeathWatch.RECAP_DELAY,
		Errors.Wrap("death recap", function()
			readRecap(seen)
		end)
	)
end)
