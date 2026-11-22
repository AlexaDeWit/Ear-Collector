-- Appraisal: an ear's grade from how much the kill felt like an achievement.
-- Each signal (the level colour, the odds, the danger to you, the fight's
-- length, revenge...) falls into a named band worth some points. The total falls
-- into grade buckets that widen as grades rise. A signal the game didn't give is
-- worth nothing, so with no fight record the grade is the level colour's, as
-- before. Pure logic: Detectors/FightFacts.lua reads the fight. Design: issue #46.
local _, ns = ...

local Appraisal = {}
ns.Appraisal = Appraisal

-- The lowest score for each grade, Uncommon up. Each step is wider than the last.
Appraisal.BUCKETS = { [2] = -5, [3] = 6, [4] = 16, [5] = 30 }
Appraisal.CONTESTED = 0.25 -- your damage taken, in health bars, that shows a real fight
Appraisal.DAY = 24 * 60 * 60 -- earlier ears from the same player within this lower the score

---@class EarCollector.FightFacts
---@field read boolean whether the damage meter had a record of the fight
---@field enemies integer? enemy players your side damaged
---@field allies integer? your side: you and the group members who took part
---@field secs number? seconds from entering combat to the kill
---@field taken number? damage you took, in multiples of your health
---@field sideTaken number? damage your whole side took (0: they never fought back)
---@field healed number? your healing and absorbs, in multiples of your health
---@field toughness number? your side's damage to the victim, in multiples of their health
---@field size number? the victim's maximum health, in multiples of yours
---@field disrupts integer? your side's interrupts and dispels
---@field allyDeaths integer? others on your side who died in the fight
---@field died boolean? you died in the fight

---@class EarCollector.Appraisal
---@field quality integer the grade
---@field score number every band's points
---@field fightScore number the fight's bands only: odds, danger, length and the rest
---@field why string[] the bands that counted, strongest first
---@field points table<string, number> each counted band's points
---@field rule "vengeance"|"grey"|nil a fixed rule that set the grade instead of the score

local LEVEL = { [4] = { "red", 16 }, [3] = { "orange", 8 }, [1] = { "green", -8 } }

-- Each signal's bands: the first whose test passes counts. A band is
-- { key, points, test(facts, kill) }. "Fight" bands make the heading.
local function band(key, points, test)
	return { key = key, points = points, test = test }
end

local function atLeast(field, value)
	return function(f)
		return type(f[field]) == "number" and f[field] >= value
	end
end

local function contested(f)
	return type(f.taken) == "number" and f.taken >= Appraisal.CONTESTED
end

local function odds(f)
	if type(f.enemies) ~= "number" or type(f.allies) ~= "number" or f.enemies < 1 or f.allies < 1 then
		return nil
	end
	return f.enemies / f.allies
end

local function oddsAtLeast(ratio)
	return function(f)
		local r = odds(f)
		return r ~= nil and r >= ratio and contested(f) -- outnumbered only counts if they hit back
	end
end

local function oddsAtMost(ratio)
	return function(f)
		local r = odds(f)
		return r ~= nil and r <= ratio
	end
end

local function withContest(test)
	return function(f)
		return contested(f) and test(f)
	end
end

Appraisal.SIGNALS = {
	{
		band("overwhelmed", 20, oddsAtLeast(3)),
		band("badlyOutnumbered", 13, oddsAtLeast(2)),
		band("outnumbered", 6, oddsAtLeast(1.01)),
		band("mob", -12, oddsAtMost(1 / 5)),
		band("zerg", -9, oddsAtMost(1 / 3)),
		band("outnumbering", -5, oddsAtMost(1 / 2)),
	},
	{
		band("againstAllOdds", 12, atLeast("taken", 1.75)),
		band("nearDeath", 8, atLeast("taken", 1)),
		band("hurt", 3, atLeast("taken", 0.5)),
	},
	{
		-- A strong opponent counts for more than a long fight: a burst can end a big one in seconds.
		band("giant", 13, atLeast("size", 2)),
		band("muchBigger", 9, atLeast("size", 1.5)),
		band("bigger", 5, atLeast("size", 1.25)),
	},
	{
		band("epicFight", 4, withContest(atLeast("secs", 60))),
		band("longFight", 2, withContest(atLeast("secs", 30))),
	},
	{
		-- Only against a smaller, lower foe: a stronger one who never hit back was burst down.
		band("oneSided", -6, function(f, kill)
			return f.sideTaken == 0 and (f.size or 0) < 1 and (kill.level or 2) <= 2
		end),
	},
	{ band("veryTough", 6, atLeast("toughness", 2.5)), band("tough", 3, atLeast("toughness", 1.5)) },
	{ band("carried", 6, atLeast("healed", 1.5)), band("healer", 3, atLeast("healed", 0.5)) },
	{ band("disruptor", 3, atLeast("disrupts", 3)), band("disrupted", 1, atLeast("disrupts", 1)) },
	{ band("alliesFell", 5, atLeast("allyDeaths", 2)), band("allyFell", 3, atLeast("allyDeaths", 1)) },
	{
		band("costYourLife", 4, function(f)
			return f.died == true
		end),
	},
}

-- Bands about you and the victim rather than the fight.
local REVENGE = { [1] = 9, [2] = 18 }
local REPEAT = -4 -- per earlier ear from them today, counting up to two
local ASSIST = -4 -- an assist where the meter shows you did little

local function add(parts, key, points, isFight)
	parts[#parts + 1] = { key = key, points = points, fight = isFight, order = #parts }
end

--- The grade for a score: Common (the least an honorable kill gets) to Legendary.
---@param score number
---@return integer
function Appraisal.Bucket(score)
	local quality = 1
	for grade = 2, 5 do
		if score >= Appraisal.BUCKETS[grade] then
			quality = grade
		end
	end
	return quality
end

--- Score a kill.
---@param kill { level: integer, debt: integer?, earlier: integer?, assist: boolean? } level: Ears.Grade's 0..4
---@param facts EarCollector.FightFacts? nil before the fight is read
---@return EarCollector.Appraisal
function Appraisal.Appraise(kill, facts)
	local debt, earlier = kill.debt or 0, math.min(kill.earlier or 0, 2)
	local parts = {}
	if facts and facts.read then
		for _, bands in ipairs(Appraisal.SIGNALS) do
			for _, b in ipairs(bands) do
				if b.test(facts, kill) then
					add(parts, b.key, b.points, true)
					break
				end
			end
		end
	end
	local level = LEVEL[kill.level]
	if level then
		add(parts, level[1], level[2], false)
	end
	if REVENGE[debt] then
		add(parts, "revenge", REVENGE[debt], false)
	end
	if earlier > 0 then
		add(parts, "repeat", REPEAT * earlier, false)
	end
	local didLittle = facts
		and facts.read
		and type(facts.taken) == "number" -- a known figure, so "took little damage" is never a guess
		and not contested(facts)
		and (facts.healed or 0) < 0.5
	if kill.assist and didLittle then
		add(parts, "assist", ASSIST, true)
	end

	local score, fightScore = 0, 0
	for _, p in ipairs(parts) do
		score = score + p.points
		fightScore = fightScore + (p.fight and p.points or 0)
	end
	table.sort(parts, function(a, b) -- strongest first; ties in the order the signals are listed
		if math.abs(a.points) ~= math.abs(b.points) then
			return math.abs(a.points) > math.abs(b.points)
		end
		return a.order < b.order
	end)
	local why, points = {}, {}
	for i, p in ipairs(parts) do
		why[i], points[p.key] = p.key, p.points
	end

	local quality, rule
	if debt >= ns.Deaths.VENGEANCE then
		quality, rule = 5, "vengeance" -- whatever the fight
	elseif kill.level == 0 then
		quality, rule = math.min(debt, 2), "grey" -- gave no honor, raised only by revenge
	else
		quality = Appraisal.Bucket(score)
	end
	return { quality = quality, score = score, fightScore = fightScore, why = why, points = points, rule = rule }
end

--- What an ear saves about its grade, before (or without) its fight's facts. It
--- keeps each band's points and the rule, so the ear says the same after the
--- bands are retuned.
---@param kill { debt: integer?, earlier: integer? } the terms Appraise was given
---@param result EarCollector.Appraisal
---@return table
function Appraisal.Record(kill, result)
	return {
		read = false,
		debt = kill.debt,
		earlier = kill.earlier,
		score = result.score,
		fightScore = result.fightScore,
		why = result.why,
		points = result.points,
		rule = result.rule,
	}
end

local POINTS = { assist = ASSIST }
for _, level in pairs(LEVEL) do
	POINTS[level[1]] = level[2]
end
for _, bands in ipairs(Appraisal.SIGNALS) do
	for _, b in ipairs(bands) do
		POINTS[b.key] = b.points
	end
end

--- A band's points today, for an ear saved before ears kept them.
---@param key any a band name
---@param debt integer? deaths owed, for revenge
---@param earlier integer? earlier ears that day, for repeats
---@return number|nil
function Appraisal.Points(key, debt, earlier)
	if key == "revenge" then
		return REVENGE[debt]
	elseif key == "repeat" then
		return type(earlier) == "number" and earlier > 0 and REPEAT * math.min(earlier, 2) or nil
	end
	return POINTS[key]
end
