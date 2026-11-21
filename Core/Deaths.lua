-- Your deaths to enemy players, and the vengeance they build up. Pure logic: the
-- detector (Detectors/Death.lua) reads the game, this file decides, so specs can
-- drive it directly.
local _, ns = ...

local Readable = ns.Context.Readable

local Deaths = {}
ns.Deaths = Deaths

-- Deaths to one player since you last killed them that make their next ear a
-- Legendary "Vengeance" ear. Taking it clears the debt.
Deaths.VENGEANCE = 3

---@class EarCollector.Death : EarCollector.Kill
---@field at number server time of the death
---@field spell string? the killing blow's spell, from the death recap

--- The killing blow's source from death recap events. Blizzard_DeathRecap lists
--- them newest first and marks the first as the one that caused the death.
--- Blizzard's PTR feedback code also reads the event's sourceGUID; when that is
--- a readable player GUID it identifies the killer outright.
--- Returns nothing when the recap is empty, hides the caster, or holds secrets.
---@param events any C_DeathRecap.GetRecapEvents()
---@return string|nil name, string|nil spell, string|nil guid
function Deaths.KillerFromRecap(events)
	if not Readable(events) or type(events) ~= "table" then
		return nil
	end
	local first = events[1]
	if not Readable(first) or type(first) ~= "table" then
		return nil
	end
	local hidden = first.hideCaster -- usually absent; Readable(nil) is false
	if hidden ~= nil and (not Readable(hidden) or hidden) then
		return nil
	end
	local name, spell, guid = first.sourceName, first.spellName, first.sourceGUID
	if not Readable(name) or type(name) ~= "string" or name == "" then
		name = nil
	end
	if not Readable(guid) or type(guid) ~= "string" or not guid:find("^Player%-") then
		guid = nil
	end
	if not name and not guid then
		return nil
	end
	if not Readable(spell) or type(spell) ~= "string" or spell == "" then
		spell = nil
	end
	return name, spell, guid
end

--- The GUID of the enemy player a recap name refers to, from the players seen at
--- the moment of death (see Deaths.See). Only an exact match counts: a recap name
--- with a surname must match that surname, so "Grimbash Stonefist" can't be
--- blamed on the "Grimbash Ironhide" you were targeting.
---@param name string
---@param seen table<string, string|false> name -> GUID; false when two players shared the name
---@return string|nil guid
function Deaths.MatchKiller(name, seen)
	return seen[name] or nil
end

--- Note a player seen at the moment of death, under every form the recap might
--- write their name in: the name as UnitName gives it, its first word (in case
--- the name includes the surname), and name plus surname joined by a space or a
--- hyphen. A form two players share is marked false, so it can never match.
---@param seen table<string, string|false>
---@param name string
---@param guid string
---@param surname string? UnitName's second return (the surname on Forever)
function Deaths.See(seen, name, guid, surname)
	local function add(key)
		if seen[key] == nil then
			seen[key] = guid
		elseif seen[key] ~= guid then
			seen[key] = false
		end
	end
	add(name)
	local first = name:match("^[^%s%-]+")
	if first and first ~= name then
		add(first)
	end
	if surname and surname ~= "" then
		add(name .. " " .. surname)
		add(name .. "-" .. surname)
	end
end

--- Deaths to `guid` since you last killed them (their latest ear's last kill).
---@param db table
---@param guid string
---@return integer
function Deaths.Debt(db, guid)
	local latest = ns.Ears.Latest(db, guid)
	local since = latest and latest.lastAt or nil
	local count = 0
	for _, death in ipairs(db.deaths) do
		if death.guid == guid and (not since or death.at > since) then
			count = count + 1
		end
	end
	return count
end

--- Record a death to an enemy player.
---@param db table
---@param killer EarCollector.Kill details of the player who killed you
---@param now number server time in seconds
---@param spell string?
---@return EarCollector.Death death
---@return integer debt deaths to them since you last killed them, this one included
function Deaths.Record(db, killer, now, spell)
	local death = {
		guid = killer.guid,
		name = killer.name,
		surname = killer.surname,
		realm = killer.realm,
		class = killer.class,
		className = killer.className,
		race = killer.race,
		raceName = killer.raceName,
		sex = killer.sex,
		level = killer.level,
		yourLevel = killer.yourLevel,
		mapID = killer.mapID,
		zone = killer.zone,
		subzone = killer.subzone,
		spell = spell,
		at = now,
	}
	db.deaths[#db.deaths + 1] = death
	return death, Deaths.Debt(db, killer.guid)
end
