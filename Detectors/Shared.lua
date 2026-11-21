-- Helpers shared by the detectors: reading a victim's details without touching
-- secret values, and the /ears debug decision log.
local _, ns = ...

local Context, Chat, Database = ns.Context, ns.Chat, ns.Database
local Readable = Context.Readable

--- Text for the debug log that never inspects a secret value.
---@param value any
---@return string
function ns.Describe(value)
	if value == nil then
		return "nil"
	elseif issecretvalue(value) then
		return "<secret>"
	end
	return tostring(value)
end

--- Addon restrictions the client is enforcing right now, e.g. "Map,PvPMatch".
--- Logged with each decision so a hidden kill can be explained afterwards.
---@return string
function ns.ActiveRestrictions()
	local active = {}
	for _, name in ipairs({ "Combat", "PvPMatch", "Map" }) do
		local kind = Enum.AddOnRestrictionType[name]
		local on = kind and C_RestrictedActions.IsAddOnRestrictionActive(kind)
		if Readable(on) and on then
			active[#active + 1] = name
		end
	end
	return #active > 0 and table.concat(active, ",") or "none"
end

--- Record a detector decision while /ears debug is on.
---@param db table
---@param event string e.g. "PARTY_KILL", "UNIT_DIED", "HONOR"
---@param source any the killer's GUID, when the event has one
---@param target any the victim's GUID
---@param decision string
function ns.Trace(db, event, source, target, decision)
	if not db.settings.debug then
		return
	end
	local entry = {
		at = GetServerTime(),
		event = event,
		attacker = ns.Describe(source),
		target = ns.Describe(target),
		decision = decision,
		restrictions = ns.ActiveRestrictions(),
	}
	Database.LogDebug(db, entry)
	Chat.Print(
		("%s %s -> %s: %s [restrictions: %s]"):format(event, entry.attacker, entry.target, decision, entry.restrictions)
	)
end

--- What the client will tell us about a dead player, as the start of an ear.
--- Returns nil when the details are hidden.
---@param guid string a readable player GUID
---@return EarCollector.Kill|nil
function ns.VictimDetails(guid)
	-- The 8th return (level) exists on Forever and Retail 12.x but may be nil.
	-- The 7th is the realm on most clients, but Forever characters have a first
	-- name and a surname instead of realms, and it holds the surname there.
	local className, class, raceName, race, sex, name, nameSuffix, level = GetPlayerInfoByGUID(guid)
	if not Readable(name) then
		return nil
	end
	local suffix = Readable(nameSuffix) and nameSuffix ~= "" and nameSuffix or nil
	local regionalNames = RegionalUniqueNamesEnabled()
	local usesSurnames = Readable(regionalNames) and regionalNames
	local yourLevel = UnitLevel("player")
	local location = Context.Location()
	return {
		guid = guid,
		name = name,
		surname = usesSurnames and suffix or nil,
		realm = not usesSurnames and suffix or nil,
		class = Readable(class) and class or nil,
		className = Readable(className) and className or nil,
		race = Readable(race) and race or nil,
		raceName = Readable(raceName) and raceName or nil,
		sex = Readable(sex) and sex or nil,
		level = Readable(level) and level > 0 and level or nil,
		yourLevel = Readable(yourLevel) and yourLevel > 0 and yourLevel or nil,
		mapID = location.mapID,
		zone = location.zone,
		subzone = location.subzone,
	}
end

--- Record an ear and announce it.
---@param db table
---@param kill EarCollector.Kill with `by` set
---@return table ear
---@return boolean isNew
function ns.Collect(db, kill)
	local ear, isNew = ns.Ears.Record(db, kill, GetServerTime())
	if db.settings.announce then
		Chat.Announce(ear, isNew)
	end
	if ns.Pouch then
		ns.Pouch.Refresh()
	end
	return ear, isNew
end
