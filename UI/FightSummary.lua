-- The words for an ear's grade, from its saved record (Appraisal.Record): the
-- lines under "Why it's <grade>", the story that closes the tooltip and follows
-- the grade in chat, and the strongest reason for the pop-up. Each reason's own
-- words are in UI/Reasons.lua.
local _, ns = ...

local Reasons = ns.Reasons
local word, capital, lower = Reasons.Word, Reasons.Capital, Reasons.Lower

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

--- The lines under "Why it's <grade>": { text, kind, strength? }, where kind is
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
	local out, list = {}, Reasons.List(fight)
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

local function history(n)
	if n == 1 then
		return "They had taken your ear."
	end
	return ("They had taken your ear %s in a row."):format(n == 2 and "twice" or word(n) .. " times")
end

local function clause(r, fight, ear)
	local ok, subject, predicate = pcall(r.band.clause, fight, ear)
	if ok and type(subject) == "string" and type(predicate) == "string" then
		return { subject = subject, predicate = predicate, order = r.band.order, up = r.points > 0 }
	end
end

-- Clauses that point the same way, joined: "You were outnumbered two to one and
-- took more than a full health bar". `said` tracks whether "health bar" came up,
-- so a later "nearly two health bars" can end at "nearly two".
local function join(group, said)
	table.sort(group, function(a, b)
		return a.order < b.order
	end)
	local text
	for i, c in ipairs(group) do
		local predicate = c.predicate
		if said.bars and predicate:find(" health bars$") then
			predicate = predicate:gsub(" health bars$", "")
		end
		said.bars = said.bars or predicate:find("health bar") ~= nil
		if i == 1 then
			text = c.subject .. " " .. predicate
		elseif c.subject == group[1].subject then
			text = text .. " and " .. predicate
		else
			text = text .. ", and " .. lower(c.subject) .. " " .. predicate
		end
	end
	return text
end

--- One or two sentences that tell the kill, built from its strongest reasons.
--- Nil when there's nothing to tell.
---@param ear table
---@return string|nil
function FightSummary.Story(ear)
	local fight = ear.fight
	if ear.pending or type(fight) ~= "table" then
		return nil
	end
	local list, debt = Reasons.List(fight), deaths(ear, fight)
	if fight.rule == "vengeance" then
		return history(debt) .. " You finally have theirs."
	end
	local clauses, avenged = {}, false
	for _, r in ipairs(list) do
		avenged = avenged or r.key == "revenge"
		local c = r.band.clause and clause(r, fight, ear)
		if c then
			c.kind = r.band.kind
			clauses[#clauses + 1] = c
		end
	end
	if fight.rule == "grey" then
		return avenged and history(debt) .. " Now you have theirs." or nil
	elseif avenged then
		for _, c in ipairs(clauses) do
			if c.kind ~= "help" then
				local joiner = c.kind == "easy" and ", but " or ", though "
				return ("%s Now you have theirs%s%s %s."):format(history(debt), joiner, lower(c.subject), c.predicate)
			end
		end
		return history(debt) .. " Now you have theirs."
	end
	local named = { clauses[1], clauses[2] }
	if #named == 0 then
		return nil
	elseif named[2] and named[1].up == named[2].up then
		for i = 3, #clauses do
			if clauses[i].up ~= named[1].up then
				named[3] = clauses[i]
				break
			end
		end
	end
	if #named == 1 and named[1].up and named[1].order <= 5 and type(fight.secs) == "number" and fight.secs < 10 then
		return ("It was over in seconds, though %s %s."):format(lower(named[1].subject), named[1].predicate)
	end
	local first, second = {}, {}
	for _, c in ipairs(named) do
		table.insert(c.up == named[1].up and first or second, c)
	end
	local said = {}
	local text = join(first, said)
	if #second > 0 then
		text = text .. ", but " .. lower(join(second, said))
	end
	return capital(text) .. "."
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
	for _, r in ipairs(Reasons.List(fight)) do
		if fight.rule ~= "grey" or r.key == "revenge" then
			return r.line
		end
	end
end
