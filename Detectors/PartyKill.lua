-- Kill detection for WoW Forever (Retail engine). The combat log is closed to
-- addons there; the PARTY_KILL event still reports who landed a killing blow on
-- whom. Both GUIDs become secret wherever the client hides unit identity
-- (instances, PvP matches, some maps), and a secret value must never be
-- compared or indexed, so every check below starts with Context.Readable.
local _, ns = ...

local Context, Ears, Chat, Database = ns.Context, ns.Ears, ns.Chat, ns.Database
local Readable = Context.Readable

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
	local me = UnitGUID("player")
	if not Readable(me) or attackerGUID ~= me then
		trace(db, attackerGUID, targetGUID, "not your killing blow")
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

	-- The 8th return (level) exists on Forever and Retail 12.x but may be nil.
	local _, class, _, race, _, name, realm, level = GetPlayerInfoByGUID(targetGUID)
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
		level = Readable(level) and level > 0 and level or nil,
		yourLevel = Readable(yourLevel) and yourLevel > 0 and yourLevel or nil,
		mapID = location.mapID,
		zone = location.zone,
		subzone = location.subzone,
	}, GetServerTime())

	trace(db, attackerGUID, targetGUID, isNew and "new ear" or "camped")
	if db.settings.announce then
		Chat.Announce(ear, isNew)
	end
end

ns.On("PARTY_KILL", ns.OnPartyKill)
