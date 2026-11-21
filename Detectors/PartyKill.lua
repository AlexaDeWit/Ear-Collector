-- Kill detection for WoW Forever (Retail engine). The combat log is closed to
-- addons there; the PARTY_KILL event still reports who landed a killing blow on
-- whom. Both GUIDs become secret wherever the client hides unit identity
-- (instances, PvP matches, some maps), and a secret value must never be
-- compared or indexed, so every check below starts with Context.Readable.
--
-- Kills by you, your pet, anyone in your group or their pets all count: in the
-- open world a group kill is a world PvP kill. Instanced PvP is excluded by
-- Context, where group kills would be noise.
local _, ns = ...

local Context, Ears, Chat, Database = ns.Context, ns.Ears, ns.Chat, ns.Database
local Readable = Context.Readable

local MAX_PARTY_PETS, MAX_RAID_PETS = 4, 40

--- Text for the debug log that never inspects a secret value.
local function describe(value)
	if value == nil then
		return "nil"
	elseif issecretvalue(value) then
		return "<secret>"
	end
	return tostring(value)
end

local function trace(db, attackerGUID, targetGUID, decision)
	if not db.settings.debug then
		return
	end
	local entry = {
		at = GetServerTime(),
		attacker = describe(attackerGUID),
		target = describe(targetGUID),
		decision = decision,
	}
	Database.LogDebug(db, entry)
	Chat.Print(("PARTY_KILL %s -> %s: %s"):format(entry.attacker, entry.target, decision))
end

local function unitIs(unit, guid)
	local unitGUID = UnitGUID(unit)
	return Readable(unitGUID) and unitGUID == guid
end

--- Who landed the killing blow, relative to the player.
---@param attackerGUID string a readable GUID
---@return "you"|"group"|nil by nil when the killer isn't you, your group, or a pet of either
---@return string|nil killerName a group member's name, when known
function ns.ClassifyKiller(attackerGUID)
	if unitIs("player", attackerGUID) or unitIs("pet", attackerGUID) then
		return "you", nil
	end
	if attackerGUID:find("^Player%-") then
		local inGroup = C_PartyInfo.IsGUIDInGroup(attackerGUID)
		if Readable(inGroup) and inGroup then
			local name = select(6, GetPlayerInfoByGUID(attackerGUID))
			return "group", Readable(name) and name or nil
		end
		return nil, nil
	end
	-- A pet or guardian: count it if it belongs to someone in the group.
	for i = 1, MAX_PARTY_PETS do
		if unitIs("partypet" .. i, attackerGUID) then
			return "group", nil
		end
	end
	for i = 1, MAX_RAID_PETS do
		if unitIs("raidpet" .. i, attackerGUID) then
			return "group", nil
		end
	end
	return nil, nil
end

--- PARTY_KILL(attackerGUID, targetGUID): you or a group member landed a killing blow.
---@param attackerGUID string
---@param targetGUID string
function ns.OnPartyKill(attackerGUID, targetGUID)
	local db = ns.db
	if not db then
		return
	end
	if not Readable(attackerGUID) or not Readable(targetGUID) then
		db.stats.hiddenKills = db.stats.hiddenKills + 1
		trace(db, attackerGUID, targetGUID, "hidden by the client")
		return
	end
	if not targetGUID:find("^Player%-") then
		trace(db, attackerGUID, targetGUID, "not a player")
		return
	end
	local counts, reason = Context.Current(db.settings)
	if not counts then
		trace(db, attackerGUID, targetGUID, reason)
		return
	end
	local by, killerName = ns.ClassifyKiller(attackerGUID)
	if not by then
		trace(db, attackerGUID, targetGUID, "not you or your group")
		return
	end

	-- The 8th return (level) exists on Forever and Retail 12.x but may be nil.
	local _, class, _, race, sex, name, realm, level = GetPlayerInfoByGUID(targetGUID)
	if not Readable(name) then
		trace(db, attackerGUID, targetGUID, "victim details hidden")
		return
	end
	local yourLevel = UnitLevel("player")
	local location = Context.Location()
	local ear, isNew = Ears.Record(db, {
		guid = targetGUID,
		name = name,
		realm = Readable(realm) and realm ~= "" and realm or nil,
		class = Readable(class) and class or nil,
		race = Readable(race) and race or nil,
		sex = Readable(sex) and sex or nil,
		level = Readable(level) and level > 0 and level or nil,
		yourLevel = Readable(yourLevel) and yourLevel > 0 and yourLevel or nil,
		by = by,
		killer = killerName,
		mapID = location.mapID,
		zone = location.zone,
		subzone = location.subzone,
	}, GetServerTime())

	trace(db, attackerGUID, targetGUID, (isNew and "new ear" or "camped") .. " (" .. by .. ")")
	if db.settings.announce then
		Chat.Announce(ear, isNew)
	end
end

ns.On("PARTY_KILL", ns.OnPartyKill)
