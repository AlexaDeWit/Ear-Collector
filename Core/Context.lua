-- Where is the player? Only open-world kills drop ears.
local _, ns = ...

local Context = {}
ns.Context = Context

--- True when `value` can be read. Values the client marks secret can be shown
--- to the player but not inspected by addon code. A table can be secret too
--- (issecrettable): indexing one without access (canaccesstable) is an error.
---@param value any
---@return boolean
function Context.Readable(value)
	if value == nil or issecretvalue(value) then
		return false
	end
	if type(value) == "table" and issecrettable and issecrettable(value) then
		return canaccesstable ~= nil and canaccesstable(value) == true
	end
	return true
end

--- Decide whether a kill here counts. Pure: callers pass in what the API reported.
---@param inInstance boolean from IsInInstance()
---@param instanceType string from IsInInstance(): "none", "pvp", "arena", "party", "raid", "scenario"
---@param pvpType string|nil from C_PvP.GetZonePVPInfo(): "combat" (zone-wide battle), "arena" (free-for-all), ...
---@param settings table the saved settings
---@return boolean counts
---@return string reason
function Context.Classify(inInstance, instanceType, pvpType, settings)
	if inInstance or instanceType ~= "none" then
		return false, "instance:" .. tostring(instanceType)
	end
	if pvpType == "combat" and not settings.includeBattlefields then
		return false, "battlefield"
	end
	if pvpType == "arena" and not settings.includeFreeForAll then
		return false, "free-for-all"
	end
	return true, "open world"
end

--- Classify the player's current location.
---@param settings table
---@return boolean counts
---@return string reason
---@return string|nil pvpType
function Context.Current(settings)
	local inInstance, instanceType = IsInInstance()
	if not Context.Readable(inInstance) or not Context.Readable(instanceType) then
		return false, "location hidden", nil
	end
	local zonePvpType = C_PvP.GetZonePVPInfo()
	local pvpType = Context.Readable(zonePvpType) and zonePvpType or nil
	local counts, reason = Context.Classify(inInstance, instanceType, pvpType, settings)
	return counts, reason, pvpType
end

--- Where the player is standing, for the ear's record. Missing values stay nil.
---@return { mapID: number?, zone: string?, subzone: string? }
function Context.Location()
	local mapID = C_Map.GetBestMapForUnit("player")
	local zone, subzone = GetRealZoneText(), GetSubZoneText()
	return {
		mapID = Context.Readable(mapID) and mapID or nil,
		zone = Context.Readable(zone) and zone ~= "" and zone or nil,
		subzone = Context.Readable(subzone) and subzone ~= "" and subzone or nil,
	}
end
