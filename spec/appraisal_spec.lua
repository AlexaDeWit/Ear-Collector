local wow = require("spec.support.wow")

describe("Appraisal", function()
	local ns, Appraisal

	before_each(function()
		wow.reset()
		ns = wow.loadAddon("EarCollector.toc")
		Appraisal = ns.Appraisal
	end)

	local YELLOW, RED, ORANGE, GREEN, GREY = 2, 4, 3, 1, 0

	-- A read fight, with `fields` set.
	local function fight(fields)
		local facts = { read = true }
		for k, v in pairs(fields) do
			facts[k] = v
		end
		return facts
	end

	local function grade(kill, facts)
		return Appraisal.Appraise(kill, facts).quality
	end

	describe("without a fight record", function()
		it("gives the level colour's grade, as before", function()
			for level, quality in pairs({ [GREY] = 0, [GREEN] = 1, [YELLOW] = 2, [ORANGE] = 3, [RED] = 4 }) do
				assert.are.equal(quality, grade({ level = level }), level)
				assert.are.equal(quality, grade({ level = level }, { read = false }), level)
				assert.are.equal(quality, grade({ level = level }, { read = true }), level) -- read, but nothing known
			end
		end)

		it("doesn't count an assist against you when the meter couldn't say what you did", function()
			assert.are.equal(4, grade({ level = RED, assist = true }, { read = false }))
		end)
	end)

	describe("grade buckets", function()
		it("widen as grades rise", function()
			assert.are.same({ 1, 2, 2, 3, 3, 4, 4, 5 }, {
				Appraisal.Bucket(-6),
				Appraisal.Bucket(-5),
				Appraisal.Bucket(5),
				Appraisal.Bucket(6),
				Appraisal.Bucket(15),
				Appraisal.Bucket(16),
				Appraisal.Bucket(29),
				Appraisal.Bucket(30),
			})
			local b = Appraisal.BUCKETS
			assert.is_true(b[5] - b[4] > b[4] - b[3] and b[4] - b[3] < b[5] - b[4])
		end)

		it("never put an honorable kill below Common", function()
			local facts = fight({ enemies = 1, allies = 6, sideTaken = 0, taken = 0 })
			assert.are.equal(1, grade({ level = GREEN, earlier = 2, assist = true }, facts))
		end)
	end)

	describe("the worked examples", function()
		it("an even one-on-one for 40 seconds, ending low, is Rare", function()
			local facts = fight({ enemies = 1, allies = 1, secs = 40, taken = 1.1, sideTaken = 1100 })
			local result = Appraisal.Appraise({ level = YELLOW }, facts)
			assert.are.equal(3, result.quality)
			assert.are.same({ "nearDeath", "longFight" }, result.why)
		end)

		it("winning alone against three, near death, is Legendary at even level", function()
			local facts = fight({ enemies = 3, allies = 1, secs = 35, taken = 1.6, sideTaken = 1600 })
			assert.are.equal(5, grade({ level = YELLOW }, facts))
		end)

		it("five of you killing one in two seconds is Common, and pulls a red victim down", function()
			local facts = fight({ enemies = 1, allies = 5, secs = 2, taken = 0.05, sideTaken = 50 })
			assert.are.equal(1, grade({ level = YELLOW }, facts))
			assert.are.equal(2, grade({ level = RED }, facts))
		end)

		it("ganking a lower player who never fought back is Common", function()
			local result = Appraisal.Appraise(
				{ level = GREEN },
				fight({ enemies = 1, allies = 1, secs = 3, taken = 0, sideTaken = 0 })
			)
			assert.are.equal(1, result.quality)
			assert.are.same({ "green", "oneSided" }, result.why)
		end)

		it("a long fight against a healed, tough victim is Epic", function()
			local facts = fight({ enemies = 2, allies = 2, secs = 75, taken = 1.4, sideTaken = 2400, toughness = 2.8 })
			assert.are.equal(4, grade({ level = YELLOW }, facts))
		end)
	end)

	describe("bursts", function()
		local burst = { enemies = 1, allies = 1, secs = 4, taken = 0, sideTaken = 0 }

		local function withSize(size)
			local facts = fight(burst)
			facts.size = size
			return facts
		end

		it("reward a quick kill of a bigger foe, who never got to hit back", function()
			local result = Appraisal.Appraise({ level = YELLOW }, withSize(1.5))
			assert.are.same({ muchBigger = 9 }, result.points)
			assert.are.equal(3, result.quality)
			assert.are.equal(5, Appraisal.Appraise({ level = YELLOW }, withSize(1.25)).points.bigger)
			assert.are.equal(13, Appraisal.Appraise({ level = YELLOW }, withSize(2)).points.giant)
		end)

		it("don't count against you on an equal or higher-level foe", function()
			assert.are.same({}, Appraisal.Appraise({ level = YELLOW }, withSize(1)).points)
			assert.is_nil(Appraisal.Appraise({ level = RED }, withSize(0.8)).points.oneSided)
		end)

		it("still count against you on a smaller, lower foe", function()
			assert.are.equal(-6, Appraisal.Appraise({ level = YELLOW }, withSize(0.8)).points.oneSided)
			assert.are.equal(-6, Appraisal.Appraise({ level = GREEN }, fight(burst)).points.oneSided)
		end)
	end)

	describe("signals", function()
		it("count being outnumbered only when they fought back", function()
			local result =
				Appraisal.Appraise({ level = YELLOW }, fight({ enemies = 3, allies = 1, taken = 0.1, sideTaken = 100 }))
			assert.are.same({}, result.why)
		end)

		it("count fight length only when they fought back, and less than a strong foe", function()
			local result = Appraisal.Appraise({ level = YELLOW }, fight({ secs = 90, taken = 0.1 }))
			assert.are.same({}, result.why)
			local long = Appraisal.Appraise({ level = YELLOW }, fight({ secs = 90, taken = 0.3 }))
			assert.are.equal(4, long.points.epicFight)
			assert.is_true(long.points.epicFight < 5) -- the smallest "bigger than you" band
		end)

		it("count one band per signal: the highest that applies", function()
			local result = Appraisal.Appraise({ level = YELLOW }, fight({ taken = 2.5 }))
			assert.are.same({ againstAllOdds = 12 }, result.points)
		end)

		it("reward healing, interrupts and allies lost", function()
			local result = Appraisal.Appraise(
				{ level = YELLOW },
				fight({ healed = 1.6, disrupts = 3, allyDeaths = 1, died = true })
			)
			assert.are.same({ carried = 6, costYourLife = 4, disruptor = 3, allyFell = 3 }, result.points)
		end)
	end)

	describe("revenge", function()
		local ordinary = { enemies = 1, allies = 1, secs = 15, taken = 0.5, sideTaken = 500 }

		it("raises the grade with each death owed, and three is always Legendary", function()
			local facts = fight(ordinary)
			assert.are.same({ 2, 3, 4, 5 }, {
				grade({ level = YELLOW, debt = 0 }, facts),
				grade({ level = YELLOW, debt = 1 }, facts),
				grade({ level = YELLOW, debt = 2 }, facts),
				grade({ level = YELLOW, debt = 3 }, fight({ enemies = 1, allies = 5, sideTaken = 0 })),
			})
		end)

		it("can reach Legendary early with a strong fight", function()
			local facts = fight({ enemies = 2, allies = 1, secs = 40, taken = 1.2, sideTaken = 1200 })
			assert.are.equal(5, grade({ level = YELLOW, debt = 2 }, facts))
		end)

		it("raises a grey victim's Poor ear, which the fight never does", function()
			local heroic = fight({ enemies = 3, allies = 1, secs = 60, taken = 2, sideTaken = 2000 })
			assert.are.same({ 0, 1, 2, 5 }, {
				grade({ level = GREY }, heroic),
				grade({ level = GREY, debt = 1 }, heroic),
				grade({ level = GREY, debt = 2 }, heroic),
				grade({ level = GREY, debt = 3 }, heroic),
			})
		end)
	end)

	describe("assists", function()
		it("have no cap: a healer's outstanding assist can be Legendary", function()
			local facts = fight({ enemies = 3, allies = 1, secs = 45, taken = 1.2, sideTaken = 1200, healed = 1.6 })
			assert.are.equal(5, grade({ level = YELLOW, assist = true }, facts))
		end)

		it("lose a little only when the meter shows you did little", function()
			local little = Appraisal.Appraise({ level = YELLOW, assist = true }, fight({ taken = 0.1, healed = 0.1 }))
			assert.are.equal(-4, little.points.assist)
			local healer = Appraisal.Appraise({ level = YELLOW, assist = true }, fight({ taken = 0.1, healed = 0.6 }))
			assert.is_nil(healer.points.assist)
			local fighter = Appraisal.Appraise({ level = YELLOW, assist = true }, fight({ taken = 0.6 }))
			assert.is_nil(fighter.points.assist)
		end)
	end)

	it("lowers repeat ears from the same player that day, counting up to two", function()
		local points = {}
		for earlier = 0, 3 do
			points[#points + 1] = Appraisal.Appraise({ level = YELLOW, earlier = earlier }).points["repeat"] or 0
		end
		assert.are.same({ 0, -4, -8, -8 }, points)
	end)

	describe("phrases", function()
		it("sum up the fight, strongest bands first", function()
			local facts = fight({ enemies = 3, allies = 1, secs = 35, taken = 1.6, sideTaken = 1600 })
			local result = Appraisal.Appraise({ level = YELLOW, debt = 2 }, facts)
			local saved = facts
			saved.why, saved.fightScore, saved.debt = result.why, result.fightScore, 2
			assert.are.equal(
				"Hard-fought: alone against 3, revenge for 2 deaths, you took 1.6 times your health",
				ns.FightSummary.Summary(saved, 3)
			)
		end)

		it("say when a fight was one-sided, and when there was no record", function()
			assert.are.equal(
				"One-sided: 5 of you against 1, they never fought back",
				ns.FightSummary.Summary({
					read = true,
					enemies = 1,
					allies = 5,
					sideTaken = 0,
					fightScore = -18,
					why = { "mob", "oneSided" },
				})
			)
			assert.are.equal(
				"No fight record: your 2nd ear from them today",
				ns.FightSummary.Summary({ read = false, earlier = 1, why = { "repeat" } })
			)
		end)

		it("leave out a phrase whose facts a damaged save lost", function()
			assert.are.equal("Fair fight", ns.FightSummary.Summary({ read = true, why = { "longFight", "nonsense" } }))
		end)
	end)
end)
