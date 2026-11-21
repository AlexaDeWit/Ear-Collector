-- The ear collection: grading and recording kills. Pure logic with no WoW API
-- calls, so specs can drive it directly.
local _, ns = ...

local Ears = {}
ns.Ears = Ears

---@class EarCollector.Kill
---@field guid string the victim's GUID
---@field name string
---@field surname string? Forever characters have a surname instead of a realm
---@field realm string? other clients: nil for your own realm
---@field class string? English class token, e.g. "WARRIOR"
---@field race string? English race token, e.g. "Scourge"
---@field sex number? 2 male, 3 female (GetPlayerInfoByGUID)
---@field level number? nil when the client doesn't say
---@field yourLevel number?
---@field by "you"|"group"|"assist" who landed the killing blow: you (or your pet), your group,
--- or someone else while you earned honorable-kill credit
---@field killer string? the group member's name, when by == "group" and known
---@field mapID number?
---@field zone string?
---@field subzone string?

--- Base grade from the level gap between the victim and you.
--- Unknown levels count as an even fight.
---@param victimLevel number|nil
---@param yourLevel number|nil
---@return integer quality 0 Poor .. 3 Rare
function Ears.Grade(victimLevel, yourLevel)
	if not victimLevel or not yourLevel then
		return 2
	end
	local gap = victimLevel - yourLevel
	if gap <= -10 then
		return 0
	elseif gap <= -5 then
		return 1
	elseif gap >= 3 then
		return 3
	end
	return 2
end

--- The most recent ear taken from `guid`, if any.
---@param db table
---@param guid string
---@return table|nil
function Ears.Latest(db, guid)
	local ears = db.ears
	for i = #ears, 1, -1 do
		if ears[i].guid == guid then
			return ears[i]
		end
	end
	return nil
end

--- Record a kill. A repeat kill of the same player inside the camping window
--- adds to that ear's camp count instead of dropping a new ear, and restarts the window.
---@param db table
---@param kill EarCollector.Kill
---@param now number server time in seconds
---@return table ear the new or updated ear
---@return boolean isNew false when the kill was a camped repeat
function Ears.Record(db, kill, now)
	local previous = Ears.Latest(db, kill.guid)
	if previous and now - previous.lastAt <= db.settings.campWindow then
		previous.camped = previous.camped + 1
		previous.lastAt = now
		return previous, false
	end
	local ear = {
		guid = kill.guid,
		name = kill.name,
		surname = kill.surname,
		realm = kill.realm,
		class = kill.class,
		race = kill.race,
		sex = kill.sex,
		level = kill.level,
		yourLevel = kill.yourLevel,
		by = kill.by,
		killer = kill.killer,
		mapID = kill.mapID,
		zone = kill.zone,
		subzone = kill.subzone,
		at = now,
		lastAt = now,
		camped = 0,
		quality = Ears.Grade(kill.level, kill.yourLevel),
	}
	db.ears[#db.ears + 1] = ear
	return ear, true
end

--- The newest `n` ears, newest first.
---@param db table
---@param n integer
---@return table[]
function Ears.Recent(db, n)
	local out = {}
	for i = #db.ears, math.max(1, #db.ears - n + 1), -1 do
		out[#out + 1] = db.ears[i]
	end
	return out
end

--- How many ears were taken at or after `since`.
---@param db table
---@param since number server time in seconds
---@return integer
function Ears.CountSince(db, since)
	local count = 0
	for i = #db.ears, 1, -1 do
		if db.ears[i].at < since then
			break
		end
		count = count + 1
	end
	return count
end
