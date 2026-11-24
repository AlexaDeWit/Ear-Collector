-- The gold line, in the player's own words. Each sample is a line the
-- maintainer approved, from a real grading.
local wow = require("spec.support.wow")

describe("the kill in your own words", function()
	local ns, Tales

	before_each(function()
		wow.reset()
		ns = wow.loadAddon("EarCollector.toc")
		Tales = ns.Tales
	end)

	local n = 0
	local function ear(kill, facts, fields)
		local result = ns.Appraisal.Appraise(kill, facts)
		local fight = ns.Appraisal.Record(kill, result)
		for key, value in pairs(facts or {}) do
			fight[key] = value
		end
		n = n + 1
		local out = { guid = "Player-1-" .. n, at = 1000 + n, quality = result.quality, fight = fight }
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

	local function story(kill, facts, fields)
		return Tales.Story(ear(kill, facts, fields))
	end

	describe("one reason, in degrees", function()
		it("tells how badly you were outnumbered", function()
			assert.are.same({
				"There were more of them than us.",
				"They had me well outnumbered.",
				"They came at me in a pack. One of them paid for it.",
			}, {
				story({ level = 2 }, fought({ enemies = 3, allies = 2, taken = 0.3 })),
				story({ level = 2 }, fought({ enemies = 2, taken = 0.3 })),
				story({ level = 2 }, fought({ enemies = 3, taken = 0.3 })),
			})
			assert.are.equal(
				"They came at us in a pack. One of them paid for it.",
				story({ level = 2 }, fought({ enemies = 6, allies = 2, taken = 0.3 }))
			)
		end)

		it("tells how far above you they were", function()
			assert.are.same({
				"They had the edge on me.",
				"They outlevelled me, and it didn't save them.",
				"They were well out of my league, and it didn't save them.",
			}, {
				story({ level = 2, gap = 2 }, fought({})),
				story({ level = 3, gap = 3 }, fought({})),
				story({ level = 4, gap = 6 }, fought({})),
			})
		end)

		it("tells how big and how hard to kill they were", function()
			assert.are.same({
				"They were bigger than me.",
				"They were built big.",
				"Built like a wall. I tore it down.",
				"They took some putting down.",
				"They soaked up hit after hit after hit, and then they didn't.",
			}, {
				story({ level = 2 }, fought({ size = 1.3 })),
				story({ level = 2 }, fought({ size = 1.6 })),
				story({ level = 2 }, fought({ size = 2.1 })),
				story({ level = 2 }, fought({ toughness = 1.6 })),
				story({ level = 2 }, fought({ toughness = 3 })),
			})
		end)

		it("tells what it cost you", function()
			assert.are.same({
				"They drew blood.",
				"They hit me hard. I hit back harder.",
				"They hit me hard, again and again. They still went down.",
				"I went down swinging, but I didn't go down alone.",
				"We lost one of ours in that one, but they paid for it.",
				"We lost some of ours in that one, but they paid for it.",
			}, {
				story({ level = 2 }, fought({ taken = 0.6, sideTaken = 0.6 })),
				story({ level = 2 }, fought({ taken = 1.2, sideTaken = 1.2 })),
				story({ level = 2 }, fought({ taken = 1.9, sideTaken = 1.9 })),
				story({ level = 2 }, fought({ died = true })),
				story({ level = 2 }, fought({ enemies = 3, allies = 3, allyDeaths = 1 })),
				story({ level = 2 }, fought({ enemies = 3, allies = 3, allyDeaths = 2 })),
			})
		end)

		it("tells your healing, the fight's length and a burst", function()
			assert.are.same({
				"I kept the heals coming.",
				"I kept the heals coming until they dropped.",
				"It dragged on.",
				"It went on and on. I outlasted them.",
				"One moment they were standing. The next, they weren't.",
			}, {
				story({ level = 2 }, fought({ healed = 0.7 })),
				story({ level = 2 }, fought({ healed = 1.8 })),
				story({ level = 2 }, fought({ secs = 40 })),
				story({ level = 2 }, fought({ secs = 75 })),
				story({ level = 2, gap = 0 }, fought({ secs = 5, taken = 0, sideTaken = 0 })),
			})
		end)

		it("tells the easy ones too, with no swagger about the odds", function()
			assert.are.same({
				"We had the numbers. They never stood a chance.",
				"We came in force. They never stood a chance.",
				"They never laid a finger on me.",
				"They keep coming back for more. I keep obliging.",
			}, {
				story({ level = 2 }, fought({ allies = 3 })),
				story({ level = 2 }, fought({ allies = 5 })),
				story({ level = 2 }, fought({ taken = 0, sideTaken = 0, size = 0.9 })),
				story({ level = 2, earlier = 2 }, fought({})),
			})
		end)
	end)

	describe("two reasons together", function()
		it("tells your Rimmy Wimmy assist: an edge, then a burst", function()
			assert.are.equal(
				"They had the edge on me. They never had the time.",
				story({ level = 2, gap = 2, assist = true }, fought({ secs = 6, taken = 0, sideTaken = 0 }))
			)
			assert.are.equal(
				"Built like a wall. They never had the time.",
				story({ level = 2 }, fought({ secs = 5, size = 2.1 }))
			)
		end)

		it("tells outnumbered and outlevelled together", function()
			assert.are.equal(
				"Outnumbered, outlevelled, and I still came out on top.",
				story({ level = 3, gap = 3 }, fought({ enemies = 2, taken = 0.5, sideTaken = 1 }))
			)
		end)

		it("never says you came through it when you died", function()
			assert.are.equal(
				"They came at me in a pack. I went down swinging, but I didn't go down alone.",
				story({ level = 2 }, fought({ enemies = 3, taken = 1.3, sideTaken = 1.3, died = true }))
			)
			assert.are.equal(
				"I went down swinging, but I didn't go down alone.",
				story({ level = 2 }, fought({ secs = 80, taken = 1.2, sideTaken = 1.2, died = true }))
			)
		end)

		it("tells the numbers with no damage taken as one", function()
			assert.are.equal(
				"We had the numbers, and they never laid a finger on any of us.",
				story({ level = 2 }, fought({ allies = 3, taken = 0, sideTaken = 0, size = 0.9 }))
			)
		end)

		it("tells a tanky foe and your healing as one", function()
			assert.are.equal(
				"They soaked up hit after hit, and I kept the heals coming until they dropped.",
				story(
					{ level = 2, assist = true },
					fought({
						enemies = 3,
						allies = 3,
						secs = 70,
						taken = 0.4,
						sideTaken = 2,
						healed = 1.8,
						toughness = 3,
					})
				)
			)
		end)
	end)

	describe("a grudge settled", function()
		local function settled(debt, guid)
			local fields = { guid = guid, vengeance = debt >= 3 and debt or nil }
			return Tales.Story(
				ear({ level = 4, gap = 6, debt = debt }, fought({ taken = 1.2, sideTaken = 1.2 }), fields)
			)
		end

		it("takes the story over, by degree of spite", function()
			local slights = {
				"They had their moment. I had mine.",
				"They got one over on me. Just the one.",
				"Last time went their way. This time didn't.",
			}
			local grudges = {
				"They'd made a habit of putting me down. I broke it.",
				"They kept coming for me. That ended here.",
			}
			local vendettas = {
				"They should have quit while they were ahead.",
				"They pushed their luck once too often.",
				"They kept pushing their luck. It ran out.",
			}
			local function among(lines, text)
				for _, line in ipairs(lines) do
					if line == text then
						return true
					end
				end
				return false
			end
			for i = 1, 6 do
				local guid = "Player-1-grudge" .. i
				assert.is_true(among(slights, settled(1, guid)))
				assert.is_true(among(grudges, settled(2, guid)))
				assert.is_true(among(vendettas, settled(3, guid)))
			end
		end)

		it("tells the same ear the same way every time, and varies between ears", function()
			local e = ear({ level = 2, debt = 3 }, fought({}), { vengeance = 3 })
			assert.are.equal(Tales.Story(e), Tales.Story(e))
			local seen = {}
			for i = 1, 20 do
				seen[settled(3, "Player-1-many" .. i)] = true
			end
			local count = 0
			for _ in pairs(seen) do
				count = count + 1
			end
			assert.is_true(count > 1)
		end)

		it("is told for a grey victim too, and only the grudge", function()
			local grey = ear({ level = 0, debt = 1 }, fought({ taken = 1.2, sideTaken = 1.2 }))
			local text = Tales.Story(grey)
			grey.fight.rule, grey.fight.why = nil, { "revenge" }
			assert.are.equal(Tales.Story(grey), text) -- the same slight a grudge alone would tell
		end)
	end)

	describe("nothing worth telling", function()
		it("tells nothing for an even kill, a small markdown, a lower level or a grey victim", function()
			assert.is_nil(story({ level = 2 }, fought({})))
			assert.is_nil(story({ level = 2, assist = true }, fought({ taken = 0.1 })))
			assert.is_nil(story({ level = 2, gap = -3 }, fought({})))
			assert.is_nil(story({ level = 2, earlier = 1 }, fought({})))
			assert.is_nil(story({ level = 0 }, fought({ taken = 1.2, sideTaken = 1.2 })))
			assert.is_nil(story({ level = 2 }, fought({ allies = 3, enemies = 3, disrupts = 4 })))
		end)

		it("tells nothing while the grade waits, or without a record of the grade", function()
			assert.is_nil(Tales.Story(ear({ level = 2, gap = 6 }, nil, { pending = true })))
			assert.is_nil(Tales.Story({ quality = 2 }))
		end)

		it("never mentions ears or counts", function()
			local lines = {
				story({ level = 3, gap = 3 }, fought({ enemies = 2, taken = 0.5, sideTaken = 1 })),
				story({ level = 2 }, fought({ allies = 5 })),
				story({ level = 4, gap = 6 }, fought({})),
			}
			for _, text in ipairs(lines) do
				assert.is_nil(text:find("ear"))
				assert.is_nil(text:find("%d"))
			end
		end)
	end)
end)
