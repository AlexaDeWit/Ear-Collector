-- Assist detection: honorable-kill credit for an enemy player whose killing
-- blow came from outside your group. Feeds Core/Assists.lua with
--   * UNIT_DIED for enemy players in the open world (death candidates), and
--   * PLAYER_PVP_KILLS_CHANGED steps in the lifetime honorable-kill count,
-- then matches them once late events have had time to arrive.
local _, ns = ...

local Context, Assists, Errors = ns.Context, ns.Assists, ns.Errors
local Readable = Context.Readable

local lastHonorableKills -- this session's baseline; nil until known
local resolveScheduled = false

local function lifetimeHonorableKills()
	local kills = GetPVPLifetimeStats()
	return Readable(kills) and kills or nil
end

local function resolve()
	resolveScheduled = false
	local db = ns.db
	if not db then
		return
	end
	local assists, unnamed, pending = Assists.Resolve(ns.assistTracker, GetTime())
	for _, kill in ipairs(assists) do
		kill.by = "assist"
		local _, isNew = ns.Collect(db, kill)
		ns.Trace(db, "HONOR", nil, kill.guid, isNew and "new ear (assist)" or "camped (assist)")
	end
	if unnamed > 0 then
		db.stats.unnamedHonorKills = db.stats.unnamedHonorKills + unnamed
		ns.Trace(db, "HONOR", nil, nil, ("%d honorable kill(s) not tied to one victim"):format(unnamed))
	end
	if pending > 0 then
		ns.ScheduleAssistCheck()
	end
end

--- Match honor credits to deaths after the window closes. Runs inside Errors.Call.
function ns.ScheduleAssistCheck()
	if resolveScheduled then
		return
	end
	resolveScheduled = true
	C_Timer.After(Assists.WINDOW + 0.5, Errors.Wrap("assist matching", resolve))
end

ns.On("PLAYER_ENTERING_WORLD", function()
	lastHonorableKills = lifetimeHonorableKills()
end)

ns.On("PLAYER_PVP_KILLS_CHANGED", function(unit)
	local db = ns.db
	if not db or not Readable(unit) or unit ~= "player" then
		return
	end
	local kills = lifetimeHonorableKills()
	if not kills then
		return
	end
	local previous = lastHonorableKills
	lastHonorableKills = kills
	if not previous or kills <= previous then
		return
	end
	local counts, reason = Context.Current(db.settings)
	if not counts then
		ns.Trace(db, "HONOR", nil, nil, ("%d honorable kill(s) ignored: %s"):format(kills - previous, reason))
		return
	end
	Assists.NoteHonor(ns.assistTracker, kills - previous, GetTime())
	ns.ScheduleAssistCheck()
end)

ns.On("UNIT_DIED", function(guid)
	local db = ns.db
	-- Most deaths are creatures, whose GUIDs are secret: return before any work.
	if not db or not Readable(guid) or not guid:find("^Player%-") then
		return
	end
	local me = UnitGUID("player")
	if not Readable(me) or guid == me then
		return
	end
	local inGroup = C_PartyInfo.IsGUIDInGroup(guid)
	if not Readable(inGroup) or inGroup then
		return
	end
	if not Context.Current(db.settings) then
		return
	end
	local kill = ns.VictimDetails(guid)
	if kill then
		Assists.NoteDeath(ns.assistTracker, { guid = guid, t = GetTime(), kill = kill })
		ns.Trace(db, "UNIT_DIED", nil, guid, "assist candidate")
	end
end)
