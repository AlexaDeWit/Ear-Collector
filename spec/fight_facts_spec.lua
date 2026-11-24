local wow = require("spec.support.wow")

local ME = "Player-4395-0000000A"
local GRIMBASH = "Player-4395-0B1C2D3E"
local KORGA = "Player-4395-0D1E2F30"

describe("grading an ear from its fight", function()
	local ns

	before_each(function()
		wow.reset()
		wow.addPlayer(GRIMBASH, { name = "Grimbash", class = "Warrior", race = "Orc", level = 60, maxHealth = 4000 })
		wow.addPlayer(KORGA, { name = "Korga", class = "Shaman", race = "Orc", level = 60 })
		ns = wow.loadAddon("EarCollector.toc")
		wow.fireEvent("PLAYER_ENTERING_WORLD", false, false)
	end)

	-- A hard one-on-one on the meter: you took 1.2 health bars, 40 seconds in.
	local function hardFight(enemies)
		wow.meterFight(enemies or { { guid = GRIMBASH, name = "Grimbash", amount = 5000 } }, {
			DamageTaken = { { amount = 1200, me = true } },
			DamageDone = { { amount = 5000, me = true } },
		})
	end

	local function endFight()
		wow.endCombat()
		wow.advance(ns.DamageMeter.SETTLE)
	end

	describe("a kill in combat", function()
		before_each(function()
			wow.startCombat()
			wow.advance(40)
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		end)

		it("waits for the fight to end, saying so in chat, with no pop-up yet", function()
			local ear = ns.db.ears[1]
			assert.is_true(ear.pending)
			-- Graded by the kill alone, so far.
			assert.are.same({ false, 0, {} }, { ear.fight.read, ear.fight.score, ear.fight.why })
			assert.are.equal(1, wow.printed("You collected .*Grimbash's Ear.*%. Appraising the fight%.%.%.$"))
			assert.are.equal(0, #ns.Toast.Active())
			local text = {}
			for _, line in ipairs(ns.EarsTab.TooltipLines(ear)) do
				text[#text + 1] = line.text or line.left
			end
			assert.matches("\nAppraised when you leave combat\n", table.concat(text, "\n"))
		end)

		it("is graded from the meter when the fight ends, with one chat line and one pop-up", function()
			hardFight()
			endFight()
			local ear = ns.db.ears[1]
			assert.is_nil(ear.pending)
			assert.are.equal(3, ear.quality) -- near death and a long fight: Rare
			assert.are.same({ "nearDeath", "longFight" }, ear.fight.why)
			assert.are.same({ nearDeath = 8, longFight = 2 }, ear.fight.points)
			assert.are.same({ true, 1, 1, 40, 1.2 }, {
				ear.fight.read,
				ear.fight.enemies,
				ear.fight.allies,
				ear.fight.secs,
				ear.fight.taken,
			})
			assert.are.equal(
				1,
				wow.printed(
					"Appraised .*Grimbash's Ear.*: Rare%. Over a full health bar gone, 40 seconds of fighting, "
						.. "and the ear is still yours%.$"
				)
			)
			assert.are.equal(1, #ns.Toast.Active())
			assert.are.equal("|cff0070ddGrimbash's Ear|r", ns.Toast.Active()[1].title:GetText())
		end)

		it("shows its pop-up ungraded if the fight goes on, and doesn't pop up twice", function()
			wow.advance(ns.FightFacts.WAIT)
			assert.are.equal(1, #ns.Toast.Active())
			assert.are.equal("Appraising the fight", ns.Toast.Active()[1].label:GetText())
			hardFight()
			endFight()
			assert.are.equal(1, wow.printed("Appraised"))
			assert.are.equal(1, #ns.Toast.Active())
		end)

		it("keeps its ungraded grade when the meter has no record", function()
			endFight()
			local ear = ns.db.ears[1]
			assert.is_nil(ear.pending)
			assert.are.equal(2, ear.quality)
			assert.is_false(ear.fight.read)
			assert.are.equal(1, wow.printed("Appraised .*: Uncommon%. No record of the fight%.$"))
		end)
	end)

	it("grades several kills from one fight once it ends, each with its own pop-up", function()
		wow.startCombat()
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		wow.fireEvent("PARTY_KILL", ME, KORGA)
		hardFight({ { guid = GRIMBASH, name = "Grimbash" }, { guid = KORGA, name = "Korga" } })
		endFight()
		assert.are.same({ 2, 2 }, { ns.db.ears[1].fight.enemies, ns.db.ears[2].fight.enemies })
		assert.is_nil(ns.db.ears[1].pending)
		assert.is_nil(ns.db.ears[2].pending)
		assert.are.equal(2, #ns.Toast.Active())
		assert.are.equal(2, wow.printed("Appraised"))
	end)

	it("grades a kill out of combat at once, in one chat line", function()
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		local ear = ns.db.ears[1]
		assert.is_nil(ear.pending)
		assert.are.equal(1, #ns.Toast.Active())
		assert.are.equal(0, wow.printed("Appraising"))
		assert.are.equal(1, wow.printed("You collected .*Grimbash's Ear.* %(Uncommon%)%. No record of the fight%.$"))
	end)

	describe("matches a kill to its own fight", function()
		local function aFight()
			wow.startCombat()
			wow.advance(40)
			hardFight()
			endFight()
		end

		it("grades a kill just after a fight from that fight", function()
			aFight()
			wow.advance(5)
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
			assert.is_true(ns.db.ears[1].fight.read)
		end)

		it("doesn't grade a kill long after a fight from it", function()
			aFight()
			wow.advance(ns.Assists.RECENT + 1)
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH) -- your group's kill, say, while you weren't fighting
			assert.is_false(ns.db.ears[1].fight.read)
			assert.are.equal(2, ns.db.ears[1].quality)
		end)

		it("doesn't grade a fight the meter kept no record of from the one before", function()
			aFight()
			wow.advance(120)
			wow.startCombat()
			wow.fireEvent("PARTY_KILL", ME, KORGA)
			endFight()
			assert.is_false(ns.db.ears[1].fight.read)
		end)

		it("doesn't take a record from before you logged in for your first fight", function()
			wow.meterFight({ { guid = KORGA, name = "Korga" } }, { DamageTaken = { { amount = 1500, me = true } } })
			wow.fireEvent("PLAYER_ENTERING_WORLD", false, true)
			wow.startCombat()
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
			endFight()
			assert.is_false(ns.db.ears[1].fight.read)
		end)
	end)

	it("measures how tough the victim was from their health at the kill", function()
		wow.startCombat()
		wow.state().units.target = GRIMBASH
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		wow.state().units.target = nil
		hardFight({ { guid = GRIMBASH, name = "Grimbash", amount = 10000 } }) -- 2.5 times their 4000 health
		endFight()
		assert.are.equal(2.5, ns.db.ears[1].fight.toughness)
		assert.are.equal(4, ns.db.ears[1].fight.size) -- their 4000 health against your 1000
		assert.are.equal(6, ns.Appraisal.Appraise({ level = 2 }, ns.db.ears[1].fight).points.veryTough)
	end)

	it("ignores a victim's health given as a percentage", function()
		wow.state().players[GRIMBASH].maxHealth = 100
		wow.startCombat()
		wow.state().units.target = GRIMBASH
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		hardFight({ { guid = GRIMBASH, name = "Grimbash", amount = 10000 } })
		endFight()
		assert.is_nil(ns.db.ears[1].fight.toughness)
	end)

	it("pays revenge from the first death owed, and says so on the pop-up", function()
		ns.RecordDeath(ns.db, { guid = GRIMBASH, name = "Grimbash", class = "WARRIOR", race = "Orc", level = 60 })
		ns.Toast.Active()[1]:Click("RightButton")
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		local ear = ns.db.ears[1]
		assert.are.equal(1, ear.fight.debt)
		assert.are.equal(3, ear.quality) -- Uncommon raised by one death owed
		assert.are.same({ revenge = 9 }, ear.fight.points)
		assert.are.equal("Revenge!", ns.Toast.Active()[1].label:GetText())
	end)

	it("notes when Vengeance or a grey victim set the grade instead of the fight", function()
		for _ = 1, 3 do
			ns.RecordDeath(ns.db, { guid = GRIMBASH, name = "Grimbash", class = "WARRIOR", race = "Orc", level = 60 })
		end
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		wow.state().players[KORGA].level = 30
		wow.fireEvent("PARTY_KILL", ME, KORGA)
		assert.are.same({ 5, "vengeance" }, { ns.db.ears[1].quality, ns.db.ears[1].fight.rule })
		assert.are.same({ 0, "grey" }, { ns.db.ears[2].quality, ns.db.ears[2].fight.rule })
	end)

	it("counts each level a yellow victim is above you", function()
		wow.state().players[GRIMBASH].level = 62
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		local fight = ns.db.ears[1].fight
		assert.are.same({ 2, 4 }, { fight.gap, fight.points.above })
	end)

	it("lowers a second ear from the same player that day", function()
		ns.db.settings.campWindow = 0
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		wow.advance(60)
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		assert.are.same({ 0, 1 }, { ns.db.ears[1].fight.earlier, ns.db.ears[2].fight.earlier })
		assert.are.same({ "repeat" }, ns.db.ears[2].fight.why)
	end)

	it("never grades a camped repeat", function()
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		local ear = ns.db.ears[1]
		local fight = ear.fight
		wow.startCombat()
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		assert.are.equal(1, ear.camped)
		assert.is_nil(ear.pending)
		hardFight()
		endFight()
		assert.are.equal(fight, ear.fight)
		assert.are.equal(2, ear.quality)
	end)

	it("keeps the ear and announces it when grading fails", function()
		ns.FightFacts.Read = function()
			error("boom")
		end
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		assert.are.equal(1, #ns.db.ears)
		assert.are.equal(2, ns.db.ears[1].quality)
		assert.is_false(ns.db.ears[1].fight.read) -- its grade from the kill alone, and why
		assert.are.equal(1, wow.printed("You collected .*Grimbash's Ear"))
		assert.are.equal(1, #ns.Toast.Active())
		assert.are.equal("appraisal", ns.db.errors[1].where)
	end)

	it("logs each grading while debug is on", function()
		ns.db.settings.debug = true
		wow.startCombat()
		wow.advance(40)
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		hardFight()
		endFight()
		assert.are.same({
			"1 enemies, 1 allies, 40 s, took 1.2x; nearDeath +8, longFight +2 = 10: Rare (was Uncommon)",
		}, wow.decisions("APPRAISAL"))
	end)
end)
