-- Grudges: players who took your ear since you last took theirs, noticed when
-- the game shows them to you (their nameplate, your target, your mouseover).
-- Seeing one you last fought on an earlier day reminds you, once that day:
-- Core/Deaths.lua decides (Deaths.Reminder). Hovering one always shows the
-- grudge on their tooltip.
local _, ns = ...

local Context, Deaths, Errors = ns.Context, ns.Deaths, ns.Errors
local Readable = Context.Readable

local Grudges = {}
ns.Grudges = Grudges

local reminded = {} -- guid -> server time of today's reminder

local function isTrue(value)
	return Readable(value) and value == true
end

-- The GUID of `unit` if it's an enemy player whose GUID can be read.
local function enemy(unit)
	if not isTrue(UnitExists(unit)) or not isTrue(UnitIsPlayer(unit)) or not isTrue(UnitCanAttack("player", unit)) then
		return nil
	end
	local guid = UnitGUID(unit)
	return Readable(guid) and type(guid) == "string" and guid or nil
end

-- A grudge you could settle here: an enemy player you owe, where kills count.
local function owed(db, unit)
	local guid = enemy(unit)
	if not guid or not Context.Current(db.settings) then
		return nil
	end
	return guid
end

local function remind(unit)
	local db = ns.db
	local guid = db and owed(db, unit)
	if not guid then
		return
	end
	local now = GetServerTime()
	local debt = Deaths.Reminder(db, guid, now, reminded[guid])
	local who = debt > 0 and ns.VictimDetails(guid)
	if not who then
		if db.settings.debug and Deaths.Debt(db, guid) > 0 then
			local why = reminded[guid] and "reminded today" or "fought too recently, or details hidden"
			ns.TraceRoutine(db, "GRUDGE", nil, guid, "no reminder: " .. why, guid)
		end
		return
	end
	reminded[guid] = now
	local lastAt = Deaths.LastFought(db, guid)
	ns.Trace(db, "GRUDGE", nil, guid, ("reminder: %d owed, last fought %s"):format(debt, ns.Chat.Date(lastAt)))
	if db.settings.announce then
		Errors.Call("chat", ns.Chat.AnnounceGrudge, who, debt, lastAt)
	end
	if debt < Deaths.VENGEANCE then
		return -- a lesser grudge gets the chat line alone
	end
	if ns.Toast then
		Errors.Call("toast", ns.Toast.ShowGrudge, who, debt)
	end
	if db.settings.grudgeSound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
		PlaySound(SOUNDKIT.RAID_WARNING, "SFX")
	end
end

ns.On("NAME_PLATE_UNIT_ADDED", function(unit)
	remind(unit)
end)

ns.On("PLAYER_TARGET_CHANGED", function()
	remind("target")
end)

ns.On("UPDATE_MOUSEOVER_UNIT", function()
	remind("mouseover")
end)

--- Add the grudge to the game's tooltip for a player you owe. Only GameTooltip:
--- other tooltips that show units (party frames' and the like) stay as they are.
---@param tooltip table
function Grudges.TooltipLines(tooltip)
	local db = ns.db
	if tooltip ~= GameTooltip or not db then
		return
	end
	local _, unit = TooltipUtil.GetDisplayedUnit(tooltip)
	local guid = Readable(unit) and type(unit) == "string" and owed(db, unit)
	local debt = guid and Deaths.Debt(db, guid) or 0
	if debt > 0 then
		for _, line in ipairs(ns.Chat.GrudgeLines(debt, Deaths.LastFought(db, guid))) do
			tooltip:AddLine(line.text, line.r, line.g, line.b, true)
		end
	end
end

if TooltipDataProcessor and TooltipUtil and Enum and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(
		Enum.TooltipDataType.Unit,
		Errors.Wrap("grudge tooltip", Grudges.TooltipLines)
	)
end
