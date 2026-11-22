-- Kills by you, your pet, your group or their pets, from PARTY_KILL (Forever has
-- no combat log). Its GUIDs turn secret where the client hides identity, so
-- every check starts with Context.Readable. Kills by anyone else can become
-- assists (Detectors/HonorKill.lua).
local _, ns = ...

local Context, Assists = ns.Context, ns.Assists
local Readable = Context.Readable

local MAX_PARTY_PETS, MAX_RAID_PETS = 4, 40

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
	local function trace(decision)
		ns.Trace(db, "PARTY_KILL", attackerGUID, targetGUID, decision)
	end
	local function traceRoutine(decision)
		ns.TraceRoutine(db, "PARTY_KILL", attackerGUID, targetGUID, decision)
	end
	-- Location first: inside a dungeon every mob kill is hidden, and those
	-- aren't kills the game hid from us in a place where they'd count.
	local counts, reason = Context.Current(db.settings)
	if not counts then
		traceRoutine(reason)
		return
	end
	if not Readable(attackerGUID) or not Readable(targetGUID) then
		db.stats.hiddenKills = db.stats.hiddenKills + 1
		trace("hidden by the client")
		return
	end
	if not targetGUID:find("^Player%-") then
		traceRoutine("not a player")
		return
	end
	local kill = ns.VictimDetails(targetGUID)
	if not kill then
		trace("victim details hidden")
		return
	end
	local by, killerName = ns.ClassifyKiller(attackerGUID)
	if not by then
		-- Not ours, but if honor credit arrives for it, it's an assist.
		Assists.NoteDeath(ns.assistTracker, { guid = targetGUID, t = GetTime(), kill = kill })
		ns.ScheduleAssistCheck()
		trace("not you or your group: assist candidate")
		return
	end
	kill.by, kill.killer = by, killerName
	Assists.NoteGroupKill(ns.assistTracker, targetGUID, GetTime(), ns.Ears.IsTrivial(kill))
	local _, isNew = ns.Collect(db, kill)
	trace((isNew and "new ear" or "camped") .. " (" .. by .. ")")
end

ns.On("PARTY_KILL", ns.OnPartyKill)
