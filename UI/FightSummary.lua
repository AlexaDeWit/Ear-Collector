-- The words for an ear's fight (Core/Appraisal.lua's bands), for chat lines
-- and tooltips: "Hard-fought: alone against 3, 35 seconds".
local _, ns = ...

local FightSummary = {}
ns.FightSummary = FightSummary

--- How the fight felt, from its bands' points.
---@param fightScore number
---@return string
function FightSummary.Heading(fightScore)
	if fightScore >= 10 then
		return "Hard-fought"
	elseif fightScore <= -5 then
		return "One-sided"
	end
	return "Fair fight"
end

local function count(n, singular, plural)
	return ("%d %s"):format(n, n == 1 and singular or plural or singular .. "s")
end

local function times(n)
	return ("%s times"):format((("%.1f"):format(n)):gsub("%.0$", ""))
end

local function sides(f)
	if f.allies > f.enemies then
		return ("%d of you against %d"):format(f.allies, f.enemies)
	elseif f.allies == 1 then
		return ("alone against %d"):format(f.enemies)
	end
	return ("%d against %d"):format(f.allies, f.enemies)
end

local function ordinal(n)
	local suffix = (n % 100 >= 11 and n % 100 <= 13) and "th" or ({ "st", "nd", "rd" })[n % 10] or "th"
	return n .. suffix
end

local PHRASES = {
	overwhelmed = sides,
	badlyOutnumbered = sides,
	outnumbered = sides,
	mob = sides,
	zerg = sides,
	outnumbering = sides,
	againstAllOdds = function(f)
		return ("you took %s your health"):format(times(f.taken))
	end,
	epicFight = function(f)
		return ("%d seconds"):format(f.secs)
	end,
	oneSided = function()
		return "they never fought back"
	end,
	giant = function(f)
		return ("they had %s your health"):format(times(f.size))
	end,
	veryTough = function(f)
		return ("it took %s their health"):format(times(f.toughness))
	end,
	carried = function(f)
		return ("you healed %s your health"):format(times(f.healed))
	end,
	disruptor = function(f)
		return count(f.disrupts, "interrupt or dispel", "interrupts and dispels")
	end,
	alliesFell = function(f)
		return ("%d of your side fell"):format(f.allyDeaths)
	end,
	allyFell = function()
		return "an ally fell"
	end,
	costYourLife = function()
		return "it cost you your life"
	end,
	red = function()
		return "a red-level foe"
	end,
	orange = function()
		return "an orange-level foe"
	end,
	green = function()
		return "a green-level foe"
	end,
	revenge = function(f)
		return ("revenge for %s"):format(count(f.debt, "death"))
	end,
	["repeat"] = function(f)
		return ("your %s ear from them today"):format(ordinal(f.earlier + 1))
	end,
	assist = function()
		return "an assist"
	end,
}
PHRASES.nearDeath, PHRASES.hurt = PHRASES.againstAllOdds, PHRASES.againstAllOdds
PHRASES.longFight = PHRASES.epicFight
PHRASES.muchBigger, PHRASES.bigger = PHRASES.giant, PHRASES.giant
PHRASES.tough, PHRASES.healer = PHRASES.veryTough, PHRASES.carried
PHRASES.disrupted = PHRASES.disruptor

--- The bands that counted, as phrases, strongest first.
---@param fight table an ear's saved fight: its facts, debt, earlier and why
---@param n integer? at most this many
---@return string[]
function FightSummary.Phrases(fight, n)
	local out = {}
	for _, key in ipairs(fight.why or {}) do
		local phrase = PHRASES[key]
		-- A damaged saved fight can lack a fact a phrase needs: leave that phrase out.
		local ok, text = pcall(phrase or tostring, fight)
		if phrase and ok and type(text) == "string" then
			out[#out + 1] = text
		end
		if n and #out >= n then
			break
		end
	end
	return out
end

--- One line about the fight: "Hard-fought: alone against 3, 35 seconds, ...".
---@param fight table an ear's saved fight
---@param n integer? phrases at most
---@return string
function FightSummary.Summary(fight, n)
	local phrases = FightSummary.Phrases(fight, n)
	local heading = fight.read and FightSummary.Heading(fight.fightScore or 0) or "No fight record"
	return #phrases > 0 and ("%s: %s"):format(heading, table.concat(phrases, ", ")) or heading
end
