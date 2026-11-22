-- Helpers shared by the detectors: reading a victim's details without touching
-- secret values, and the /ears debug decision log.
local _, ns = ...

local Context, Chat, Database, Errors = ns.Context, ns.Chat, ns.Database, ns.Errors
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
		t = math.floor(GetTime() * 1000 + 0.5) / 1000, -- seconds, for the gaps between events
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

-- Decisions about things that never count (NPC kills, kills in dungeons) are
-- logged only a few times per session each: enough to show the event fires,
-- without pushing PvP lines out of the bounded debug log or flooding chat.
ns.ROUTINE_TRACES = 3
local routineTraces = {} -- key -> times seen this session, while debug was on

--- ns.Trace for a routine decision: logged at most ns.ROUTINE_TRACES times per
--- session for each `key` (default: the decision).
---@param db table
---@param event string
---@param source any
---@param target any
---@param decision string
---@param key string? groups decisions whose text varies, e.g. by a count
function ns.TraceRoutine(db, event, source, target, decision, key)
	if not db.settings.debug then
		return
	end
	key = event .. " " .. (key or decision)
	local seen = (routineTraces[key] or 0) + 1
	routineTraces[key] = seen
	if seen < ns.ROUTINE_TRACES then
		ns.Trace(db, event, source, target, decision)
	elseif seen == ns.ROUTINE_TRACES then
		ns.Trace(db, event, source, target, decision .. " (no more of these logged until /reload)")
	end
end

--- What the client will tell us about a dead player, as the start of an ear.
--- Returns nil when the details are hidden.
---@param guid string a readable player GUID
---@return EarCollector.Kill|nil
function ns.VictimDetails(guid)
	-- The 8th return (level) exists on Forever and Retail 12.x but may be nil.
	-- The 7th is the realm on most clients. Forever has surnames instead of
	-- realms, and in play its name is "First Surname" with the 7th empty, so a
	-- non-empty 7th is kept as the surname in case another build splits them.
	local className, class, raceName, race, sex, name, nameSuffix, level = GetPlayerInfoByGUID(guid)
	if not Readable(name) then
		return nil
	end
	local suffix = Readable(nameSuffix) and nameSuffix ~= "" and nameSuffix or nil
	local regionalNames = RegionalUniqueNamesEnabled()
	local usesSurnames = Readable(regionalNames) and regionalNames
	local yourLevel = UnitLevel("player")
	local trivialRange = UnitQuestTrivialLevelRange("player")
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
		trivialRange = Readable(trivialRange) and type(trivialRange) == "number" and trivialRange or nil,
		mapID = location.mapID,
		zone = location.zone,
		subzone = location.subzone,
	}
end

--- Record a death to an enemy player and announce it.
---@param db table
---@param killer EarCollector.Kill
---@param spell string?
---@return EarCollector.Death death
---@return integer debt
function ns.RecordDeath(db, killer, spell)
	local death, debt = ns.Deaths.Record(db, killer, GetServerTime(), spell)
	-- UI work runs in its own Errors.Call: a UI bug must never switch off detection.
	if db.settings.announce then
		Errors.Call("chat", Chat.AnnounceDeath, death, debt)
	end
	if ns.Pouch then
		Errors.Call("pouch refresh", ns.Pouch.Refresh)
	end
	return death, debt
end

--- Record an ear and announce it. A kill of someone you owe vengeance becomes
--- a Legendary Vengeance ear.
---@param db table
---@param kill EarCollector.Kill with `by` set
---@return table ear
---@return boolean isNew
function ns.Collect(db, kill)
	local debt = ns.Deaths.Debt(db, kill.guid)
	if debt >= ns.Deaths.VENGEANCE then
		kill.vengeance = debt
	end
	local ear, isNew = ns.Ears.Record(db, kill, GetServerTime())
	-- UI work runs in its own Errors.Call: a UI bug must never switch off detection.
	if db.settings.announce then
		Errors.Call("chat", Chat.Announce, ear, isNew)
	end
	if ns.Pouch then
		Errors.Call("pouch refresh", ns.Pouch.Refresh)
	end
	if isNew and ns.Toast then
		Errors.Call("toast", ns.Toast.Show, ear)
	end
	return ear, isNew
end
