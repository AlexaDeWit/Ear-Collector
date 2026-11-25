-- The gold line: the kill in the player's own words, as they'd tell it to a
-- friend afterwards. The list above it carries the facts, so this carries the
-- feeling, in degrees rather than numbers. A grudge settled takes it over;
-- otherwise the strongest reasons pick the tale. Nothing is told when there's
-- nothing worth telling. Lines may colour what the ear saved, never invent an
-- event or say what anyone thought. Voice: docs/architecture.md, "Wording".
local _, ns = ...

local Tales = {}
ns.Tales = Tales

-- "me" alone, "us" with your group.
local function either(mine, ours)
	return function(group)
		return group and ours or mine
	end
end

-- Each band's tale. `line` tells it alone; `opener` starts one when a second
-- beat follows; `edge` marks an advantage the victim had over you.
local TALES = {
	outnumbered = { edge = true, line = either("There were more of them than me.", "There were more of them than us.") },
	badlyOutnumbered = { edge = true, line = either("They had me well outnumbered.", "They had us well outnumbered.") },
	overwhelmed = {
		edge = true,
		line = either(
			"They came at me in a pack. One of them paid for it.",
			"They came at us in a pack. One of them paid for it."
		),
		opener = either("They came at me in a pack.", "They came at us in a pack."),
	},
	above = { edge = true, line = either("They had the edge on me.", "They had the edge on us.") },
	orange = {
		edge = true,
		line = either("They outlevelled me, and it didn't save them.", "They outlevelled us, and it didn't save them."),
		opener = either("They outlevelled me.", "They outlevelled us."),
	},
	red = {
		edge = true,
		line = either(
			"They were well out of my league, and it didn't save them.",
			"They were well out of our league, and it didn't save them."
		),
		opener = either("They were well out of my league.", "They were well out of our league."),
	},
	bigger = { edge = true, line = "They were bigger than me." },
	muchBigger = { edge = true, line = "They were built big." },
	giant = {
		edge = true,
		line = either("Built like a wall. I tore it down.", "Built like a wall. We tore it down."),
		opener = "Built like a wall.",
	},
	tough = { edge = true, line = "They took some putting down." },
	veryTough = {
		edge = true,
		line = "They soaked up hit after hit after hit, and then they didn't.",
		opener = "They soaked up hit after hit.",
	},
	hurt = { line = "They drew blood." },
	nearDeath = { line = "They hit me hard. I hit back harder." },
	againstAllOdds = { line = "They hit me hard, again and again. They still went down." },
	healer = { line = "I kept the heals coming." },
	carried = { line = "I kept the heals coming until they dropped." },
	longFight = { line = "It dragged on." },
	epicFight = { line = "It went on and on. I outlasted them." },
	burst = { line = "One moment they were standing. The next, they weren't." },
	zerg = { line = "We had the numbers. They never stood a chance.", opener = "We had the numbers" },
	mob = { line = "We came in force. They never stood a chance.", opener = "We came in force" },
	oneSided = { line = either("They never laid a finger on me.", "They never laid a finger on any of us.") },
	costYourLife = { line = "I went down swinging, but I didn't go down alone." },
	alliesFell = { line = "We lost some of ours in that one, but they paid for it." },
	allyFell = { line = "We lost one of ours in that one, but they paid for it." },
	["repeat"] = { line = "They keep coming back for more. I keep obliging." },
}
local ODDS = { outnumbered = true, badlyOutnumbered = true, overwhelmed = true }
local ABOVE = { above = true, orange = true, red = true }

-- A grudge settled, by degree of spite: a slight, a grudge, a vendetta.
local SLIGHT = {
	"They had their moment. I had mine.",
	"They got one over on me. Just the one.",
	"Last time went their way. This time didn't.",
}
local GRUDGE = {
	"They'd made a habit of putting me down. I broke it.",
	"They kept coming for me. That ended here.",
}
local VENDETTA = {
	"They should have quit while they were ahead.",
	"They pushed their luck once too often.",
	"They kept pushing their luck. It ran out.",
}

-- The same ear always tells the same story; different ears vary.
local function pick(lines, ear)
	local text, n = tostring(ear.guid) .. tostring(ear.at), 0
	for i = 1, #text do
		n = (n * 31 + text:byte(i)) % 2147483647
	end
	return lines[n % #lines + 1]
end

local function say(text, group)
	return type(text) == "function" and text(group) or text
end

--- The kill told in the player's own words. Nil when there's nothing worth telling.
---@param ear table
---@return string|nil
function Tales.Story(ear)
	local fight = ear.fight
	if ear.pending or type(fight) ~= "table" then
		return nil
	end
	local debt = type(fight.debt) == "number" and fight.debt or ear.vengeance or 0
	if fight.rule == "vengeance" then
		return pick(VENDETTA, ear)
	end
	local group, told, by = (fight.allies or 1) > 1, {}, {}
	for _, r in ipairs(ns.Reasons.List(fight, ear)) do
		if r.key == "revenge" then
			return pick(debt >= 2 and GRUDGE or SLIGHT, ear)
		end
		local tale = TALES[r.key]
		if tale and fight.rule ~= "grey" then
			told[#told + 1] = { key = r.key, points = r.points, strength = r.strength, tale = tale }
			by[r.key] = told[#told]
		end
	end
	local function line(t)
		return say(t.tale.line, group)
	end
	local function opener(t)
		return say(t.tale.opener or t.tale.line, group)
	end
	local edge, odds, above
	for _, t in ipairs(told) do
		edge = edge or t.tale.edge and t
		odds = odds or ODDS[t.key] and t
		above = above or ABOVE[t.key] and t
	end
	if by.costYourLife then -- before anything that says you came through it
		return edge and opener(edge) .. " " .. line(by.costYourLife) or line(by.costYourLife)
	elseif by.burst and edge then
		return opener(edge) .. " They never had the time."
	elseif odds and above then
		return ("Outnumbered, outlevelled, and %s still came out on top."):format(group and "we" or "I")
	end
	local numbers, tough, heal = by.zerg or by.mob, by.veryTough or by.tough, by.carried or by.healer
	if numbers and by.oneSided then
		return ("%s, and they never laid a finger on %s."):format(opener(numbers), group and "any of us" or "me")
	elseif tough and heal then
		local start = by.veryTough and "They soaked up hit after hit" or "They took some putting down"
		return start .. ", and I kept the heals coming until they dropped."
	end
	local first = told[1]
	if not first or (first.points < 0 and first.strength < 2) then
		return nil -- a small markdown, such as a second ear in a day, is no story
	end
	return line(first)
end
