-- One reason an ear got its grade, in words: each band's tooltip line, with
-- the amounts they share (health bars, health, time, levels). UI/FightSummary.lua
-- lists them; UI/Tales.lua tells the story. The voice is in docs/architecture.md,
-- "Wording".
local _, ns = ...

local Reasons = {}
ns.Reasons = Reasons

local WORDS = { "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten" }
local ORDINALS = { "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth" }

local function word(n)
	return WORDS[n] or tostring(n)
end

local function capital(text)
	return text:sub(1, 1):upper() .. text:sub(2)
end

local function lower(text)
	return text:sub(1, 1):lower() .. text:sub(2)
end

-- An amount in health bars, rounded down: "half a health bar", "over a full
-- health bar", "nearly two health bars". After "took", "over" reads as a
-- phrasal verb, so `took` makes it "more than".
local function bars(value, took)
	local tenths = math.floor(value * 10 + 0.5)
	local whole, rest = math.floor(tenths / 10), tenths % 10
	local text
	if whole == 0 then
		text = rest >= 8 and "nearly a full health bar"
			or rest > 5 and "over half a health bar"
			or rest == 5 and "half a health bar"
			or "under half a health bar"
	elseif rest >= 8 then
		text = ("nearly %s health bars"):format(word(whole + 1))
	else
		text = whole == 1 and "a full health bar" or ("%s health bars"):format(word(whole))
		text = rest > 0 and "over " .. text or text
	end
	return took and text:gsub("^over ", "more than ") or text
end

local function size(value)
	if value >= 3 then
		return ("%s times your health"):format(word(math.floor(value)))
	elseif value >= 2 then
		return "twice your health"
	end
	return value >= 1.5 and "far more health than you" or "more health than you"
end

-- "45 seconds", "a minute", "over 2 minutes".
local function duration(secs)
	if secs < 60 then
		return ("%d seconds"):format(secs)
	end
	local minutes = math.floor(secs / 60)
	local text = minutes == 1 and "a minute" or ("%d minutes"):format(minutes)
	return secs % 60 == 0 and text or "over " .. text
end

local function side(f)
	return (f.allies or 1) > 1 and "your side" or "you"
end

-- Their level less yours: saved with the grade, or worked out from the ear.
local function gap(f, ear)
	if type(f.gap) == "number" then
		return f.gap
	elseif type(ear) == "table" and type(ear.level) == "number" and type(ear.yourLevel) == "number" then
		return ear.level - ear.yourLevel
	end
end

-- "six levels above you", "a level below you"; `fallback` when the levels are unknown.
local function levels(f, ear, fallback)
	local n = gap(f, ear)
	if not n or n == 0 then
		return fallback
	end
	local direction = n > 0 and "above" or "below"
	n = math.abs(n)
	return n == 1 and ("a level %s you"):format(direction) or ("%s levels %s you"):format(word(n), direction)
end

local function levelLine(fallback)
	return function(f, ear)
		return capital(levels(f, ear, fallback))
	end
end

local function fixed(text)
	return function()
		return text
	end
end

local ODDS_FOR = function(f)
	return ("Outnumbered %dv%d"):format(f.allies, f.enemies)
end
local ODDS_AGAINST = function(f)
	return ("Outnumbered them %dv%d"):format(f.allies, f.enemies)
end
local BIGGER = function(f)
	return capital(size(f.size))
end
local TOUGH = function(f)
	return capital(bars(f.toughness)) .. " to kill"
end
local TAKEN = function(f)
	return "Took " .. bars(f.taken, true)
end
local HEALED = function(f)
	return "Healed " .. bars(f.healed)
end
local DISRUPTS = function(f)
	return ("Interrupts and dispels: %d"):format(f.disrupts)
end
local LOST = function(f)
	return f.allyDeaths == 1 and "Lost a group member" or ("Lost %d group members"):format(f.allyDeaths)
end
local COMBAT = function(f)
	return "In combat for " .. duration(f.secs)
end

-- Each band's tooltip line, from the record (and the ear, for its levels).
local LINES = {
	overwhelmed = ODDS_FOR,
	badlyOutnumbered = ODDS_FOR,
	outnumbered = ODDS_FOR,
	mob = ODDS_AGAINST,
	zerg = ODDS_AGAINST,
	outnumbering = ODDS_AGAINST,
	red = levelLine("far above your level"),
	orange = levelLine("above your level"),
	above = levelLine("above your level"),
	below = levelLine("below your level"),
	green = levelLine("well below your level"),
	giant = BIGGER,
	muchBigger = BIGGER,
	bigger = BIGGER,
	veryTough = TOUGH,
	tough = TOUGH,
	againstAllOdds = TAKEN,
	nearDeath = TAKEN,
	hurt = TAKEN,
	burst = fixed("Down in seconds"),
	oneSided = function(f)
		return capital(side(f)) .. " took no damage"
	end,
	costYourLife = fixed("You died too"),
	alliesFell = LOST,
	allyFell = LOST,
	carried = HEALED,
	healer = HEALED,
	disruptor = DISRUPTS,
	disrupted = DISRUPTS,
	epicFight = COMBAT,
	longFight = COMBAT,
	revenge = function(f)
		return f.debt == 1 and "Avenged your death" or ("Avenged %d deaths"):format(f.debt)
	end,
	["repeat"] = function(f)
		return ("%s ear from them in a day"):format(capital(ORDINALS[f.earlier + 1] or (f.earlier + 1) .. "th"))
	end,
	assist = fixed("Assist, took little damage"),
}

local function strength(points)
	local n = math.abs(points)
	return n >= 13 and 3 or n >= 6 and 2 or 1
end

--- The reasons that counted, strongest first: { key, points, line, strength }.
--- A band this version doesn't know, or a saved fact a line needs that's
--- missing, is left out.
---@param fight table an ear's saved record (Appraisal.Record)
---@param ear table? the ear, for its levels when the record has no gap
---@return table[]
function Reasons.List(fight, ear)
	local out = {}
	for _, key in ipairs(type(fight.why) == "table" and fight.why or {}) do
		local points = type(fight.points) == "table" and fight.points[key]
			or ns.Appraisal.Points(key, fight.debt, fight.earlier)
		local ok, line = pcall(LINES[key] or error, fight, ear)
		if ok and type(line) == "string" and type(points) == "number" and points ~= 0 then
			out[#out + 1] = { key = key, points = points, line = line, strength = strength(points) }
		end
	end
	return out
end

Reasons.Word, Reasons.Capital, Reasons.Lower = word, capital, lower
