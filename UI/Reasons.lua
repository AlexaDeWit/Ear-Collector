-- One reason an ear got its grade, in words: each band's tooltip line, and its
-- part in the ear's story (a fragment, and a punchline for when it stands
-- alone), with the amounts they share (health bars, health, time, levels).
-- UI/FightSummary.lua puts them together. The voice is in docs/architecture.md,
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

-- "45 seconds", "a minute", "over 2 minutes" (or "over two minutes" in a story).
local function duration(secs, story)
	if secs < 60 then
		return ("%d seconds"):format(secs)
	end
	local minutes = math.floor(secs / 60)
	local text = minutes == 1 and "a minute" or ("%s minutes"):format(story and word(minutes) or minutes)
	return secs % 60 == 0 and text or "over " .. text
end

local function big(a, b)
	return a > 10 or b > 10
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

-- Each band: its tooltip line, and its story part. `part` is a fragment, and
-- `solo` the whole story when the band tells it alone (else the fragment).
local function band(line, part, solo)
	return { line = line, part = part, solo = solo }
end

local function sentence(text)
	return capital(text) .. "."
end

local ODDS_FOR = band(function(f)
	return ("Outnumbered %dv%d"):format(f.allies, f.enemies)
end, function(f)
	if big(f.enemies, f.allies) then -- no sentence starts with a digit
		return ("outnumbered %d to %d"):format(f.enemies, f.allies)
	end
	return ("%s of them, %s of you"):format(word(f.enemies), word(f.allies))
end, function(_, part)
	return capital(part) .. ", and the ear is yours."
end)
local ODDS_AGAINST = band(function(f)
	return ("Outnumbered them %dv%d"):format(f.allies, f.enemies)
end, function(f)
	if big(f.allies, f.enemies) then
		return ("outnumbering them %d to %d"):format(f.allies, f.enemies)
	end
	return ("%s of you, %s of them"):format(word(f.allies), word(f.enemies))
end)
local function above(fallback)
	return band(function(f, ear)
		return capital(levels(f, ear, fallback))
	end, function(f, ear)
		return levels(f, ear, fallback)
	end, function(_, part)
		return capital(part) .. ", and the ear is yours."
	end)
end
local function below(fallback)
	return band(function(f, ear)
		return capital(levels(f, ear, fallback))
	end, function(f, ear)
		return levels(f, ear, fallback)
	end)
end
local BIGGER = band(function(f)
	return capital(size(f.size))
end, function(f)
	return size(f.size)
end, function(_, part)
	return capital(part) .. ", and it still wasn't enough."
end)
local TOUGH = band(function(f)
	return capital(bars(f.toughness)) .. " to kill"
end, function(f)
	return bars(f.toughness) .. " to put them down"
end)
local TAKEN = band(function(f)
	return "Took " .. bars(f.taken, true)
end, function(f)
	return bars(f.taken) .. " gone"
end, function(f)
	return ("You took %s, and the ear is still yours."):format(bars(f.taken, true))
end)
local HEALED = band(function(f)
	return "Healed " .. bars(f.healed)
end, function(f)
	return bars(f.healed) .. " of healing from you"
end)
local DISRUPTS = band(function(f)
	return ("Interrupts and dispels: %d"):format(f.disrupts)
end, function(f)
	local n = f.disrupts
	local what = n == 1 and "an interrupt or dispel" or ("%s interrupts and dispels"):format(word(n))
	return ("%s from %s"):format(what, side(f))
end)
local LOST = band(function(f)
	return f.allyDeaths == 1 and "Lost a group member" or ("Lost %d group members"):format(f.allyDeaths)
end, function(f)
	return f.allyDeaths == 1 and "a group member down" or ("%s of your group down"):format(word(f.allyDeaths))
end, function(_, part)
	return capital(part) .. ", but the ear is yours."
end)
local COMBAT = band(function(f)
	return "In combat for " .. duration(f.secs)
end, function(f)
	return duration(f.secs, true) .. " of fighting"
end, function(_, part)
	return capital(part) .. ", and the ear is yours."
end)

local BANDS = {
	overwhelmed = ODDS_FOR,
	badlyOutnumbered = ODDS_FOR,
	outnumbered = ODDS_FOR,
	mob = ODDS_AGAINST,
	zerg = ODDS_AGAINST,
	outnumbering = ODDS_AGAINST,
	red = above("far above your level"),
	orange = above("above your level"),
	above = above("above your level"),
	below = below("below your level"),
	green = below("well below your level"),
	giant = BIGGER,
	muchBigger = BIGGER,
	bigger = BIGGER,
	veryTough = TOUGH,
	tough = TOUGH,
	againstAllOdds = TAKEN,
	nearDeath = TAKEN,
	hurt = TAKEN,
	burst = band(function()
		return "Down in seconds"
	end, function()
		return "gone in a moment"
	end),
	oneSided = band(function(f)
		return capital(side(f)) .. " took no damage"
	end, function(f)
		return (f.allies or 1) > 1 and "they never landed a hit" or "they never landed a hit on you"
	end),
	costYourLife = band(function()
		return "You died too"
	end, function()
		return "you went down too"
	end, function()
		return "You went down too, but the ear is yours."
	end),
	alliesFell = LOST,
	allyFell = LOST,
	carried = HEALED,
	healer = HEALED,
	disruptor = DISRUPTS,
	disrupted = DISRUPTS,
	epicFight = COMBAT,
	longFight = COMBAT,
	revenge = band(function(f)
		return f.debt == 1 and "Avenged your death" or ("Avenged %d deaths"):format(f.debt)
	end),
	["repeat"] = band(function(f)
		return ("%s ear from them in a day"):format(capital(ORDINALS[f.earlier + 1] or (f.earlier + 1) .. "th"))
	end, function(f)
		return ("your %s ear from them in a day"):format(ORDINALS[f.earlier + 1] or (f.earlier + 1) .. "th")
	end),
	assist = band(function()
		return "Assist, took little damage"
	end, function()
		return "an assist where you took little damage"
	end),
}

local function strength(points)
	local n = math.abs(points)
	return n >= 13 and 3 or n >= 6 and 2 or 1
end

--- The reasons that counted, strongest first: { key, points, line, strength,
--- part?, solo? }. A band this version doesn't know, or a saved fact a line
--- needs that's missing, is left out.
---@param fight table an ear's saved record (Appraisal.Record)
---@param ear table? the ear, for its levels when the record has no gap
---@return table[]
function Reasons.List(fight, ear)
	local out = {}
	for _, key in ipairs(type(fight.why) == "table" and fight.why or {}) do
		local b = BANDS[key]
		local points = type(fight.points) == "table" and fight.points[key]
			or ns.Appraisal.Points(key, fight.debt, fight.earlier)
		local ok, line = pcall(b and b.line or error, fight, ear)
		if ok and type(line) == "string" and type(points) == "number" and points ~= 0 then
			local r = { key = key, points = points, line = line, strength = strength(points) }
			local told, part = pcall(b.part or error, fight, ear)
			if told and type(part) == "string" then
				r.part = part
				r.solo = b.solo and b.solo(fight, part) or sentence(part)
			end
			out[#out + 1] = r
		end
	end
	return out
end

Reasons.Word, Reasons.Capital, Reasons.Lower = word, capital, lower
