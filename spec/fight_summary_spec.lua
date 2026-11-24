-- The words for an ear's grade. The samples are the copy the maintainer approved,
-- built from real gradings, so a change to the wording or the rules shows here.
local wow = require("spec.support.wow")

describe("the words for an ear's grade", function()
	local ns, FightSummary

	before_each(function()
		wow.reset()
		ns = wow.loadAddon("EarCollector.toc")
		FightSummary = ns.FightSummary
	end)

	-- An ear graded the way the addon grades it, from the kill's terms and its fight.
	local function ear(kill, facts, fields)
		local result = ns.Appraisal.Appraise(kill, facts)
		local fight = ns.Appraisal.Record(kill, result)
		for key, value in pairs(facts or {}) do
			fight[key] = value
		end
		local out = { name = "Cedric Vale", quality = result.quality, level = 60, yourLevel = 60, fight = fight }
		for key, value in pairs(fields or {}) do
			out[key] = value
		end
		return out
	end

	local function fought(fields)
		local facts = { read = true, enemies = 1, allies = 1, secs = 20, taken = 0.3, sideTaken = 0.3, size = 1 }
		for key, value in pairs(fields) do
			facts[key] = value
		end
		return facts
	end

	-- "+ Took more than a full health bar ##": sign, words, strength.
	local function lines(e)
		local out = {}
		for _, line in ipairs(FightSummary.Lines(e)) do
			local sign = line.kind == "up" and "+ " or line.kind == "down" and "- " or ""
			out[#out + 1] = sign .. line.text .. (line.strength and " " .. ("#"):rep(line.strength) or "")
		end
		return out
	end

	describe("the samples", function()
		it("Legendary: revenge for two, against a higher level", function()
			local e = ear(
				{ level = 4, debt = 2 },
				fought({ secs = 12, taken = 0.6, sideTaken = 0.6, size = 1.3, toughness = 1 }),
				{ yourLevel = 54 }
			)
			assert.are.same({
				"+ Avenged 2 deaths ###",
				"+ Six levels above you ###",
				"+ More health than you #",
				"+ Took more than half a health bar #",
			}, lines(e))
			assert.are.equal(
				"Twice they took your ear. Six levels above you, and now it's yours.",
				FightSummary.Story(e)
			)
			assert.are.equal("Avenged 2 deaths", FightSummary.Short(e))
		end)

		it("Epic: five seconds on a big target", function()
			local e = ear({ level = 2 }, fought({ secs = 5, taken = 0.1, sideTaken = 0.1, size = 2.1, toughness = 1 }))
			assert.are.equal(4, e.quality)
			assert.are.same({ "+ Twice your health ###", "+ Down in seconds #" }, lines(e))
			assert.are.equal("Twice your health, and gone in a moment.", FightSummary.Story(e))
			assert.are.equal("Twice your health", FightSummary.Short(e))
		end)

		it("Epic: outnumbered, but a repeat", function()
			local e = ear(
				{ level = 2, earlier = 1 },
				fought({ enemies = 2, secs = 45, taken = 1.6, sideTaken = 1.6, size = 1.1, toughness = 1.2 })
			)
			assert.are.same({
				"+ Outnumbered 1v2 ###",
				"+ Took more than a full health bar ##",
				"- Second ear from them in a day #",
				"+ In combat for 45 seconds #",
			}, lines(e))
			assert.are.equal(
				"Two of them, one of you, over a full health bar gone, and the ear is still yours.",
				FightSummary.Story(e)
			)
			assert.are.equal("Outnumbered 1v2", FightSummary.Short(e))
		end)

		it("Common: five of you against one", function()
			local e = ear({ level = 2 }, fought({ allies = 5, secs = 4, taken = 0, sideTaken = 0, size = 0.9 }))
			assert.are.same({ "- Outnumbered them 5v1 ##", "- Your side took no damage ##" }, lines(e))
			assert.are.equal("Five of you, one of them. They never landed a hit.", FightSummary.Story(e))
			assert.are.equal("Outnumbered them 5v1", FightSummary.Short(e))
		end)

		it("Epic: a healer's assist", function()
			local e = ear(
				{ level = 2, assist = true },
				fought({
					enemies = 3,
					allies = 3,
					secs = 70,
					taken = 0.4,
					sideTaken = 2,
					healed = 1.8,
					disrupts = 4,
					allyDeaths = 1,
					toughness = 3,
				}),
				{ by = "assist" }
			)
			assert.are.same({
				"+ Three health bars to kill ##",
				"+ Healed nearly two health bars ##",
				"+ In combat for over a minute #",
				"+ Interrupts and dispels: 4 #",
				"+ Lost a group member #",
			}, lines(e))
			assert.are.equal(
				"Three health bars to put them down, nearly two health bars of healing from you, "
					.. "and the ear is still yours.",
				FightSummary.Story(e)
			)
			assert.are.equal("Three health bars to kill", FightSummary.Short(e))
		end)

		it("Uncommon: your assist two levels up, burst down in seconds", function()
			local e = ear(
				{ level = 2, gap = 2, assist = true },
				fought({ allies = 1, secs = 6, taken = 0, sideTaken = 0 }),
				{ level = 56, yourLevel = 54, by = "assist" }
			)
			assert.are.same({
				"+ Down in seconds #",
				"+ Two levels above you #",
				"- Assist, took little damage #",
				"Just short of Rare",
			}, lines(e))
			assert.are.equal("Two levels above you, and gone in a moment.", FightSummary.Story(e))
		end)

		it("no gold line for a small markdown alone", function()
			local e = ear({ level = 2, assist = true }, fought({ secs = 20, taken = 0.1 }))
			assert.are.same({ "- Assist, took little damage #" }, lines(e))
			assert.is_nil(FightSummary.Story(e))
		end)

		it("Uncommon: nothing counted, so no story", function()
			local e = ear({ level = 2 }, fought({}))
			assert.are.same({ "Nothing raised or lowered it" }, lines(e))
			assert.is_nil(FightSummary.Story(e))
			assert.is_nil(FightSummary.Short(e))
		end)

		it("Vengeance: three deaths owed, and an easy fight that didn't count", function()
			local e = ear(
				{ level = 2, debt = 3 },
				fought({ allies = 3, secs = 8, taken = 0, sideTaken = 0, size = 0.9 }),
				{ vengeance = 3 }
			)
			assert.are.equal(5, e.quality)
			assert.are.same({
				"Vengeance for 3 deaths",
				"The fight didn't count",
				"Outnumbered them 3v1",
				"Your side took no damage",
			}, lines(e))
			assert.are.same({ "vengeance", "note", "context", "context" }, {
				FightSummary.Lines(e)[1].kind,
				FightSummary.Lines(e)[2].kind,
				FightSummary.Lines(e)[3].kind,
				FightSummary.Lines(e)[4].kind,
			})
			assert.are.equal("Three times they took your ear. Not this time.", FightSummary.Story(e))
			assert.are.equal("Avenged 3 deaths", FightSummary.Short(e))
		end)

		it("no record of the fight", function()
			local e = ear({ level = 2 })
			assert.are.same({ "No record of the fight" }, lines(e))
			assert.is_nil(FightSummary.Story(e))
			assert.is_nil(FightSummary.Short(e))
		end)

		it("a grey victim, raised by revenge", function()
			local e = ear({ level = 0, debt = 1 }, fought({ allies = 3, taken = 0, sideTaken = 0, size = 0.5 }))
			assert.are.equal(1, e.quality)
			assert.are.same({ "Grey to you: no honor", "+ Avenged your death ##" }, lines(e))
			assert.are.equal("They took your ear last time. Now it's yours.", FightSummary.Story(e))
			assert.are.equal("Avenged your death", FightSummary.Short(e))
			-- A grey victim's fight didn't count, so the story leaves it out.
			e = ear({ level = 0, debt = 1 }, fought({ taken = 1.2, sideTaken = 1.2 }))
			assert.are.equal("They took your ear last time. Now it's yours.", FightSummary.Story(e))
		end)

		it("Rare: you died too", function()
			local e =
				ear({ level = 2 }, fought({ secs = 25, taken = 1.2, sideTaken = 1.2, died = true, toughness = 1 }))
			assert.are.same({ "+ Took more than a full health bar ##", "+ You died too #" }, lines(e))
			assert.are.equal(
				"Over a full health bar gone, you went down too, and the ear is still yours.",
				FightSummary.Story(e)
			)
		end)
	end)

	describe("amounts", function()
		local function line(why, fields)
			local fight = { read = true, why = { why }, points = { [why] = 8 } }
			for key, value in pairs(fields) do
				fight[key] = value
			end
			return FightSummary.Lines({ quality = 3, fight = fight })[1].text
		end

		it("round health bars down, and say over or nearly", function()
			local said = {}
			for _, taken in ipairs({ 0.5, 0.6, 0.8, 1, 1.1, 1.7, 1.8, 2, 2.3, 2.9 }) do
				said[#said + 1] = line("nearDeath", { taken = taken })
			end
			assert.are.same({
				"Took half a health bar",
				"Took more than half a health bar",
				"Took nearly a full health bar",
				"Took a full health bar",
				"Took more than a full health bar",
				"Took more than a full health bar",
				"Took nearly two health bars",
				"Took two health bars",
				"Took more than two health bars",
				"Took nearly three health bars",
			}, said)
			assert.are.equal("Healed over a full health bar", line("carried", { healed = 1.5 }))
			assert.are.equal("Over two health bars to kill", line("veryTough", { toughness = 2.6 }))
		end)

		it("say how much more health they had", function()
			local said = {}
			for _, size in ipairs({ 1.3, 1.6, 2.4, 3.2 }) do
				said[#said + 1] = line("giant", { size = size })
			end
			assert.are.same(
				{ "More health than you", "Far more health than you", "Twice your health", "Three times your health" },
				said
			)
		end)

		it("say how long you were in combat", function()
			local said = {}
			for _, secs in ipairs({ 45, 60, 75, 130 }) do
				said[#said + 1] = line("epicFight", { secs = secs, taken = 0.3 })
			end
			assert.are.same({
				"In combat for 45 seconds",
				"In combat for a minute",
				"In combat for over a minute",
				"In combat for over 2 minutes",
			}, said)
		end)

		it("name the level gap", function()
			local function level(gap, why)
				local fight = { read = true, why = { why }, points = { [why] = 2 }, gap = gap }
				return FightSummary.Lines({ quality = 2, fight = fight })[1].text
			end
			assert.are.same(
				{ "A level above you", "Two levels below you", "Six levels above you" },
				{ level(1, "above"), level(-2, "below"), level(6, "red") }
			)
		end)

		it("count repeats and deaths in words a player uses", function()
			assert.are.equal("Third ear from them in a day", line("repeat", { earlier = 2 }))
			assert.are.equal("Fourth ear from them in a day", line("repeat", { earlier = 3 }))
			assert.are.equal("Avenged your death", line("revenge", { debt = 1 }))
			assert.are.equal("Lost 2 group members", line("alliesFell", { allyDeaths = 2 }))
			assert.are.equal("Interrupts and dispels: 1", line("disrupted", { disrupts = 1 }))
		end)
	end)

	describe("stories", function()
		it("put numbers over ten in digits", function()
			local e = ear({ level = 2 }, fought({ enemies = 11, allies = 4, sideTaken = 9 }))
			assert.are.equal("Outnumbered 11 to 4, and the ear is yours.", FightSummary.Story(e))
		end)

		it("say a level gap in words, or how far off when the levels are missing", function()
			local e = ear({ level = 4 }, fought({}), { yourLevel = 53 })
			assert.are.equal("Seven levels above you, and the ear is yours.", FightSummary.Story(e))
			e.level = nil
			assert.are.equal("Far above your level, and the ear is yours.", FightSummary.Story(e))
		end)

		it("give a reason told alone its own punchline", function()
			local e = ear({ level = 2 }, fought({ secs = 12, size = 2.1 }))
			assert.are.equal("Twice your health, and it still wasn't enough.", FightSummary.Story(e))
			e = ear({ level = 2 }, fought({ healed = 1.6 }))
			assert.are.equal("Over a full health bar of healing from you.", FightSummary.Story(e))
		end)

		it("tell a grudge settled, without the reasons that lowered the grade", function()
			local e = ear({ level = 2, debt = 1 }, fought({ allies = 5, taken = 0.4, sideTaken = 3 }))
			assert.are.equal("They took your ear last time. Now it's yours.", FightSummary.Story(e))
		end)

		it("lead with what lowered the grade when it counted most, keeping to that side", function()
			local e = ear({ level = 2 }, fought({ allies = 5, secs = 30, taken = 1.2, sideTaken = 2 }))
			assert.are.equal("Five of you, one of them.", FightSummary.Story(e))
		end)

		it("let your part tell a grudge settled", function()
			local e = ear({ level = 2, debt = 1 }, fought({ healed = 1.6 }))
			assert.are.equal(
				"They took your ear last time. Over a full health bar of healing from you, and now it's yours.",
				FightSummary.Story(e)
			)
		end)
	end)

	describe("lines", function()
		it("share one line past the sixth reason, signs kept", function()
			local e = ear(
				{ level = 4, earlier = 1, debt = 1 },
				fought({
					enemies = 3,
					secs = 70,
					taken = 1.8,
					sideTaken = 3,
					size = 2.1,
					toughness = 2.6,
					healed = 1.6,
					disrupts = 3,
					allyDeaths = 2,
					died = true,
				})
			)
			local shown = FightSummary.Lines(e)
			assert.are.equal(7, #shown) -- six reasons, then the rest
			assert.are.equal("note", shown[#shown].kind)
			assert.matches("^[%+%-] .+, [%+%-] ", shown[#shown].text)
		end)

		it("say you took no damage when you fought without a group", function()
			local e = ear({ level = 2 }, fought({ taken = 0, sideTaken = 0, size = 0.9 }))
			assert.are.same({ "- You took no damage ##", "Just short of Uncommon" }, lines(e))
			assert.are.equal("They never landed a hit on you.", FightSummary.Story(e))
		end)

		it("only say a Vengeance fight didn't count when there's a fight to show", function()
			local e = ear({ level = 2, debt = 3 }, fought({}), { vengeance = 3 })
			assert.are.same({ "Vengeance for 3 deaths" }, lines(e))
		end)

		it("never call an ear just short of a grade when there was no record of the fight", function()
			local e = ear({ level = 1 })
			assert.are.same({ "- Well below your level ##", "No record of the fight" }, lines(e))
		end)

		it("say when the grade waits on the fight", function()
			local e = ear({ level = 2 }, nil, { pending = true })
			assert.are.same({ "Appraised when you leave combat" }, lines(e))
			assert.is_nil(FightSummary.Story(e))
			assert.is_nil(FightSummary.Short(e))
		end)

		it("leave out bands from a newer version and facts a damaged save lost", function()
			local e = { quality = 2, fight = { read = true, why = { "nearDeath", "fromANewerVersion" }, points = {} } }
			assert.are.same({ "Nothing raised or lowered it" }, lines(e))
			assert.is_nil(FightSummary.Story(e))
		end)

		it("show nothing for an ear with no record of how it was graded", function()
			assert.are.same({}, FightSummary.Lines({ quality = 2 }))
			assert.is_nil(FightSummary.Story({ quality = 2 }))
		end)
	end)
end)
