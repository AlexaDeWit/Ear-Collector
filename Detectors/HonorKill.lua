-- Assist evidence: enemy players' deaths (UNIT_DIED) and steps in your lifetime
-- honorable-kill count, matched once late events have arrived. Deaths no honor
-- named go to the damage meter (Detectors/DamageMeter.lua).
local _, ns = ...

local Context, Assists, Errors = ns.Context, ns.Assists, ns.Errors
local Readable = Context.Readable

local lastHonorableKills -- this session's baseline; nil until known

local function lifetimeHonorableKills()
	local kills = GetPVPLifetimeStats()
	return Readable(kills) and kills or nil
end

local function resolve()
	local db = ns.db
	if not db then
		return
	end
	local assists, unnamed, _, unclaimed = Assists.Resolve(ns.assistTracker, GetTime())
	for _, kill in ipairs(assists) do
		kill.by = "assist"
		local _, isNew = ns.Collect(db, kill)
		ns.Trace(db, "HONOR", nil, kill.guid, isNew and "new ear (assist)" or "camped (assist)")
	end
	if unnamed > 0 then
		db.stats.unnamedHonorKills = db.stats.unnamedHonorKills + unnamed
		ns.Trace(db, "HONOR", nil, nil, ("%d honorable kill(s) not tied to one victim"):format(unnamed))
	end
	-- Deaths no honor named may still be assists, if you damaged them.
	ns.DamageMeter.Queue(unclaimed)
end

local resolveWrapped = Errors.Wrap("assist matching", resolve)

--- Match honor credits to deaths once this event's window has closed. Every
--- death and credit schedules its own pass, so each settles on time; a pass
--- that finds nothing settled does nothing. Runs inside Errors.Call.
function ns.ScheduleAssistCheck()
	C_Timer.After(Assists.WINDOW + 0.5, resolveWrapped)
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
		local decision = ("%d honorable kill(s) ignored: %s"):format(kills - previous, reason)
		ns.TraceRoutine(db, "HONOR", nil, nil, decision, "ignored: " .. reason)
		return
	end
	ns.Trace(db, "HONOR", nil, nil, ("+%d honorable kill(s), %d lifetime"):format(kills - previous, kills))
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
		ns.ScheduleAssistCheck()
		ns.Trace(db, "UNIT_DIED", nil, guid, "assist candidate")
	end
end)
