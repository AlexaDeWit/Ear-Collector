-- One reason an ear got its grade, in words: each band's tooltip line and story
-- clause, and the amounts they share (health bars, health, time in combat).
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

-- "three to one", or "12 to 4" once either is over ten.
local function pair(a, b, joiner)
	if a > 10 or b > 10 then
		return ("%d%s%d"):format(a, joiner, b)
	end
	return ("%s%s%s"):format(word(a), joiner, word(b))
end

local function side(f)
	return (f.allies or 1) > 1 and "Your side" or "You"
end

local function gap(ear)
	if type(ear.level) == "number" and type(ear.yourLevel) == "number" then
		return math.abs(ear.level - ear.yourLevel)
	end
end

local function levelClause(ear, direction, fallback)
	local n = gap(ear)
	return "They", n and ("were %s levels %s you"):format(word(n), direction) or "were " .. fallback
end

-- Each band: its tooltip line, its story clause (subject, predicate), what kind
-- of reason it is, and its place in a story (setup, opponent, cost, your part).
local ODDS_FOR = {
	line = function(f)
		return ("Outnumbered %dv%d"):format(f.allies, f.enemies)
	end,
	clause = function(f)
		return "You", "were outnumbered " .. pair(f.enemies, f.allies, " to ")
	end,
	kind = "hard",
	order = 1,
}
local ODDS_AGAINST = {
	line = function(f)
		return ("Outnumbered them %dv%d"):format(f.allies, f.enemies)
	end,
	clause = function(f)
		return "It was", pair(f.allies, f.enemies, " of you against ")
	end,
	kind = "easy",
	order = 1,
}
local ABOVE = function(text)
	return {
		line = function()
			return capital(text)
		end,
		clause = function(_, ear)
			return levelClause(ear, "above", text)
		end,
		kind = "hard",
		order = 2,
	}
end
local BIGGER = {
	line = function(f)
		return capital(size(f.size))
	end,
	clause = function(f)
		return "They", "had " .. size(f.size)
	end,
	kind = "hard",
	order = 3,
}
local TOUGH = {
	line = function(f)
		return capital(bars(f.toughness)) .. " to kill"
	end,
	clause = function(f)
		return "It", ("took %s to bring them down"):format(bars(f.toughness, true))
	end,
	kind = "hard",
	order = 4,
}
local TAKEN = {
	line = function(f)
		return "Took " .. bars(f.taken, true)
	end,
	clause = function(f)
		return "You", "took " .. bars(f.taken, true)
	end,
	kind = "hard",
	order = 5,
}
local HEALED = {
	line = function(f)
		return "Healed " .. bars(f.healed)
	end,
	clause = function(f)
		return "You", "healed " .. bars(f.healed)
	end,
	kind = "help",
	order = 9,
}
local DISRUPTS = {
	line = function(f)
		return ("Interrupts and dispels: %d"):format(f.disrupts)
	end,
	clause = function(f)
		local n = f.disrupts
		return side(f),
			n == 1 and "landed an interrupt or dispel" or ("landed %s interrupts and dispels"):format(word(n))
	end,
	kind = "help",
	order = 10,
}
local LOST = {
	line = function(f)
		return f.allyDeaths == 1 and "Lost a group member" or ("Lost %d group members"):format(f.allyDeaths)
	end,
	clause = function(f)
		return f.allyDeaths == 1 and "A group member" or capital(word(f.allyDeaths)) .. " group members", "died"
	end,
	kind = "hard",
	order = 8,
}
local COMBAT = {
	line = function(f)
		return "In combat for " .. duration(f.secs)
	end,
	clause = function(f)
		return "You", "were in combat for " .. duration(f.secs, true)
	end,
	kind = "hard",
	order = 11,
}

local BANDS = {
	overwhelmed = ODDS_FOR,
	badlyOutnumbered = ODDS_FOR,
	outnumbered = ODDS_FOR,
	mob = ODDS_AGAINST,
	zerg = ODDS_AGAINST,
	outnumbering = ODDS_AGAINST,
	red = ABOVE("far above your level"),
	orange = ABOVE("above your level"),
	green = {
		line = function()
			return "Well below your level"
		end,
		clause = function(_, ear)
			return levelClause(ear, "below", "well below your level")
		end,
		kind = "easy",
		order = 2,
	},
	giant = BIGGER,
	muchBigger = BIGGER,
	bigger = BIGGER,
	veryTough = TOUGH,
	tough = TOUGH,
	againstAllOdds = TAKEN,
	nearDeath = TAKEN,
	hurt = TAKEN,
	oneSided = {
		line = function(f)
			return side(f) .. " took no damage"
		end,
		clause = function(f)
			return side(f), "took no damage"
		end,
		kind = "easy",
		order = 6,
	},
	costYourLife = {
		line = function()
			return "You died too"
		end,
		clause = function()
			return "You", "died too"
		end,
		kind = "hard",
		order = 7,
	},
	alliesFell = LOST,
	allyFell = LOST,
	carried = HEALED,
	healer = HEALED,
	disruptor = DISRUPTS,
	disrupted = DISRUPTS,
	epicFight = COMBAT,
	longFight = COMBAT,
	revenge = {
		line = function(f)
			return f.debt == 1 and "Avenged your death" or ("Avenged %d deaths"):format(f.debt)
		end,
	},
	["repeat"] = {
		line = function(f)
			return ("%s ear from them in a day"):format(capital(ORDINALS[f.earlier + 1] or (f.earlier + 1) .. "th"))
		end,
		clause = function(f)
			return "It was",
				("your %s ear from them in a day"):format(ORDINALS[f.earlier + 1] or (f.earlier + 1) .. "th")
		end,
		kind = "easy",
		order = 12,
	},
	assist = {
		line = function()
			return "Assist, took little damage"
		end,
		clause = function()
			return "It was", "an assist where you took little damage"
		end,
		kind = "easy",
		order = 13,
	},
}

local function strength(points)
	local n = math.abs(points)
	return n >= 13 and 3 or n >= 6 and 2 or 1
end

--- The reasons that counted, strongest first: { key, points, line, band, strength }.
--- A band this version doesn't know, or a saved fact a line needs that's
--- missing, is left out.
---@param fight table an ear's saved record (Appraisal.Record)
---@return table[]
function Reasons.List(fight)
	local out = {}
	for _, key in ipairs(type(fight.why) == "table" and fight.why or {}) do
		local band = BANDS[key]
		local points = type(fight.points) == "table" and fight.points[key]
			or ns.Appraisal.Points(key, fight.debt, fight.earlier)
		local ok, line = pcall(band and band.line or error, fight)
		if ok and type(line) == "string" and type(points) == "number" and points ~= 0 then
			out[#out + 1] = { key = key, points = points, line = line, band = band, strength = strength(points) }
		end
	end
	return out
end

Reasons.Word, Reasons.Capital, Reasons.Lower = word, capital, lower
