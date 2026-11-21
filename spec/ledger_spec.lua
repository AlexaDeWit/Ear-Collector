local wow = require("spec.support.wow")

local NOW = 1795293660
local DAY = 24 * 60 * 60

describe("Ledger and Rivals logic", function()
	local ns

	before_each(function()
		wow.reset()
		ns = wow.loadAddon("EarCollector.toc")
	end)

	local function ear(fields)
		local e = { guid = "Player-1-A", name = "Grimbash", at = NOW - 60, quality = 2, camped = 0, by = "you" }
		for k, v in pairs(fields or {}) do
			e[k] = v
		end
		e.lastAt = e.lastAt or e.at
		return e
	end

	describe("Ledger.Summarize", function()
		it("is all zeros with no ears", function()
			local s = ns.Ledger.Summarize({}, NOW)
			assert.are.same({ 0, 0, 0, 0, 0 }, { s.ears, s.kills, s.assists, s.week, s.players })
			assert.are.same({}, s.byClass)
			assert.are.same({}, s.zones)
			for grade = 0, 5 do
				assert.are.equal(0, s.byQuality[grade])
			end
		end)

		it("counts ears, kills with repeats, assists, players and the last 7 days", function()
			local s = ns.Ledger.Summarize({
				ear({ guid = "A", at = NOW - 10 * DAY, camped = 2 }),
				ear({ guid = "A", at = NOW - 2 * DAY }),
				ear({ guid = "B", at = NOW - 7 * DAY, by = "assist" }), -- exactly 7 days: counts
				ear({ guid = "C", at = NOW - 7 * DAY - 1, by = "group" }),
			}, NOW)
			assert.are.equal(4, s.ears)
			assert.are.equal(6, s.kills)
			assert.are.equal(1, s.assists)
			assert.are.equal(3, s.players)
			assert.are.equal(2, s.week)
		end)

		it("counts grades, treating an unknown grade as Uncommon", function()
			local s = ns.Ledger.Summarize({
				ear({ quality = 0 }),
				ear({ quality = 3 }),
				ear({ quality = 3 }),
				ear({ quality = 9 }),
			}, NOW)
			assert.are.same({ [0] = 1, [1] = 0, [2] = 1, [3] = 2, [4] = 0, [5] = 0 }, s.byQuality)
		end)

		it("ranks classes by count, then name, with unknown classes grouped", function()
			local s = ns.Ledger.Summarize({
				ear({ class = "ROGUE", className = "Rogue" }),
				ear({ class = "MAGE" }),
				ear({ class = "ROGUE" }),
				ear({ class = "HUNTER" }),
				ear({}),
			}, NOW)
			local order = {}
			for i, entry in ipairs(s.byClass) do
				order[i] = ("%s=%d"):format(entry.class, entry.count)
			end
			assert.are.same({ "ROGUE=2", "HUNTER=1", "MAGE=1", "UNKNOWN=1" }, order)
			assert.are.equal("Rogue", s.byClass[1].name)
			assert.is_nil(s.byClass[2].name)
		end)

		it("lists the top five zones, skipping ears without one", function()
			local ears = {}
			for i, zone in ipairs({ "A", "B", "B", "C", "C", "C", "D", "E", "F" }) do
				ears[i] = ear({ zone = zone })
			end
			ears[#ears + 1] = ear({})
			local s = ns.Ledger.Summarize(ears, NOW)
			local zones = {}
			for i, entry in ipairs(s.zones) do
				zones[i] = entry.zone .. "=" .. entry.count
			end
			assert.are.same({ "C=3", "B=2", "A=1", "D=1", "E=1" }, zones)
		end)
	end)

	describe("Rivals.List", function()
		it("groups ears by player GUID, not name", function()
			local rows = ns.Rivals.List({
				ear({ guid = "A", name = "Grimbash" }),
				ear({ guid = "B", name = "Grimbash" }), -- another Grimbash, another surname
			})
			assert.are.equal(2, #rows)
		end)

		it("counts kills with repeats, and takes name and details from the latest kill", function()
			local rows = ns.Rivals.List({
				ear({ guid = "A", name = "Old", at = NOW - 3 * DAY, camped = 1, level = 58 }),
				ear({ guid = "A", name = "New", at = NOW - DAY, level = 60 }),
				ear({ guid = "A", name = "Mid", at = NOW - 2 * DAY, lastAt = NOW - 2 * DAY + 300 }),
			})
			local r = rows[1]
			assert.are.same({ 3, 4 }, { r.ears, r.kills })
			assert.are.equal("New", r.name)
			assert.are.equal(60, r.latest.level)
			assert.are.equal(NOW - 3 * DAY, r.firstAt)
			assert.are.equal(NOW - DAY, r.lastAt)
		end)

		it("uses a repeat kill's time as the last time you killed them", function()
			local rows = ns.Rivals.List({ ear({ guid = "A", at = NOW - DAY, lastAt = NOW - 100, camped = 3 }) })
			assert.are.equal(NOW - 100, rows[1].lastAt)
		end)

		it("marks prey at three kills", function()
			local rows = ns.Rivals.List({
				ear({ guid = "A", camped = 2 }),
				ear({ guid = "B", camped = 1 }),
			})
			assert.is_true(rows[1].prey)
			assert.is_false(rows[2].prey)
		end)

		it("sorts by kills, then the most recent", function()
			local rows = ns.Rivals.List({
				ear({ guid = "A", at = NOW - 300 }),
				ear({ guid = "B", at = NOW - 100 }),
				ear({ guid = "C", at = NOW - 900, camped = 1 }),
			})
			assert.are.same({ "C", "B", "A" }, { rows[1].guid, rows[2].guid, rows[3].guid })
		end)
	end)
end)
