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
--- Returns nil when the recap is empty, hides the caster, or holds secrets.
---@param events any C_DeathRecap.GetRecapEvents()
---@return string|nil name, string|nil spell
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
	local name, spell = first.sourceName, first.spellName
	if not Readable(name) or type(name) ~= "string" or name == "" then
		return nil
	end
	if not Readable(spell) or type(spell) ~= "string" or spell == "" then
		spell = nil
	end
	return name, spell
end

--- The GUID of the enemy player a recap name refers to, from the players seen at
--- the moment of death. Tries the name as given, then its first word, in case
--- the recap adds a surname ("Name Surname") or realm ("Name-Realm").
---@param name string
---@param seen table<string, string|false> name -> GUID; false when two players shared the name
---@return string|nil guid
function Deaths.MatchKiller(name, seen)
	local guid = seen[name]
	if guid == nil then
		local short = name:match("^[^%s%-]+")
		if short and short ~= name then
			guid = seen[short]
		end
	end
	return guid or nil
end

--- Add `name -> guid` to a seen-players table; a second GUID for the same name
--- makes the name ambiguous (false), so it can never match.
---@param seen table<string, string|false>
---@param name string
---@param guid string
function Deaths.See(seen, name, guid)
	if seen[name] == nil then
		seen[name] = guid
	elseif seen[name] ~= guid then
		seen[name] = false
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
