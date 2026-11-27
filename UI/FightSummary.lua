-- The words for an ear's grade, from its saved record (Appraisal.Record): the
-- lines under the grade, and the strongest reason for the pop-up. Each
-- reason's own words are in UI/Reasons.lua; the story is UI/Tales.lua.
local _, ns = ...

local Reasons = ns.Reasons
local capital, lower = Reasons.Capital, Reasons.Lower

local FightSummary = {}
ns.FightSummary = FightSummary

FightSummary.SHOWN = 6 -- reason lines before the rest share one line
FightSummary.NEAR = 3 -- points from the next grade that make an ear "just short" of it

local function deaths(ear, fight)
	return type(fight.debt) == "number" and fight.debt or ear.vengeance or 0
end

local function sign(points)
	return points > 0 and "+ " or "- "
end

--- The lines under the grade: { text, kind, strength? }, where kind is
--- "up" or "down" (with 1 to 3 for strength), "vengeance", "context" (a reason
--- that didn't count) or "note".
---@param ear table
---@return table[]
function FightSummary.Lines(ear)
	if ear.pending then
		return { { text = "Appraised when you leave combat", kind = "note" } }
	end
	local fight = ear.fight
	if type(fight) ~= "table" then
		return {}
	end
	local out, list = {}, Reasons.List(fight, ear)
	local function add(text, kind, strength)
		out[#out + 1] = { text = text, kind = kind, strength = strength }
	end
	local function overflow(signed)
		local rest = {}
		for i = FightSummary.SHOWN + 1, #list do
			rest[#rest + 1] = signed and sign(list[i].points) .. list[i].line or lower(list[i].line)
		end
		if #rest > 0 then
			add(signed and table.concat(rest, ", ") or capital(table.concat(rest, ", ")), "note")
		end
	end
	if fight.rule == "vengeance" then
		add(("Vengeance for %d deaths"):format(deaths(ear, fight)), "vengeance")
		if #list > 0 then
			add("The fight didn't count", "note")
		end
		for i = 1, math.min(#list, FightSummary.SHOWN) do
			add(list[i].line, "context")
		end
		overflow(false)
		return out
	elseif fight.rule == "grey" then
		add("Grey to you: no honor", "note")
		for _, r in ipairs(list) do
			if r.key == "revenge" then
				add(r.line, "up", r.strength)
			end
		end
		return out
	end
	for i = 1, math.min(#list, FightSummary.SHOWN) do
		add(list[i].line, list[i].points > 0 and "up" or "down", list[i].strength)
	end
	overflow(true)
	if not fight.read then
		add("No record of the fight", "note")
	elseif #list == 0 then
		add("Nothing raised or lowered it", "note")
	end
	local nextGrade = ns.QUALITY[(ear.quality or 0) + 1]
	local threshold = ns.Appraisal.BUCKETS[(ear.quality or 0) + 1]
	if fight.read and threshold and type(fight.score) == "number" and fight.score >= threshold - FightSummary.NEAR then
		add(("Just short of %s"):format(nextGrade.name), "note")
	end
	return out
end

--- The strongest reason, for the pop-up's detail line. Nil when none counted.
---@param ear table
---@return string|nil
function FightSummary.Short(ear)
	local fight = ear.fight
	if ear.pending or type(fight) ~= "table" then
		return nil
	elseif fight.rule == "vengeance" then
		return ("Avenged %d deaths"):format(deaths(ear, fight))
	end
	for _, r in ipairs(Reasons.List(fight, ear)) do
		if fight.rule ~= "grey" or r.key == "revenge" then
			return r.line
		end
	end
end
