-- Saved files from past releases, loaded through today's code: nothing lost,
-- every ear able to say why it has its grade, and a newer file left intact.
-- The fixtures and how to record one: docs/testing.md, "Saved files from past releases".
local wow = require("spec.support.wow")

local RELEASES = { "v1.0.0", "v1.4.0", "v2.0.0-test-build" }

local function fixture(name)
	return dofile(("spec/fixtures/saved/%s.lua"):format(name))
end

local function copy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = copy(v)
	end
	return out
end

local function saved()
	return copy({ EarCollectorDB = _G.EarCollectorDB, EarCollectorCharDB = _G.EarCollectorCharDB })
end

local function load(files)
	wow.reset()
	return wow.loadAddon("EarCollector.toc", copy(files))
end

describe("a saved file from", function()
	for _, release in ipairs(RELEASES) do
		describe(release, function()
			local before, ns

			before_each(function()
				before = fixture(release)
				ns = load(before)
			end)

			it("loads at today's schema with nothing lost", function()
				assert.are.same({}, ns.db.errors)
				assert.are.equal(ns.Database.SCHEMA, _G.EarCollectorDB.schema)
				assert.are.equal(ns.Database.SCHEMA, _G.EarCollectorCharDB.schema)
				local old = before.EarCollectorCharDB
				assert.are.equal(#old.ears, #ns.db.ears)
				assert.are.same(old.deaths, ns.db.deaths)
				for i, ear in ipairs(old.ears) do
					local now = ns.db.ears[i]
					for key, value in pairs(ear) do
						if key ~= "fight" then
							assert.are.same(value, now[key], ("%s's %s"):format(ear.name, key))
						end
					end
				end
				assert.are.equal(300, ns.db.settings.campWindow)
				assert.are.equal(2, ns.db.settings.toastMinQuality)
			end)

			it("gives every ear a record of how it was graded that explains its grade", function()
				for _, ear in ipairs(ns.db.ears) do
					local fight, why = ear.fight, ear.name
					assert.is_table(fight, why)
					if fight.rule == "vengeance" then
						assert.are.equal(5, ear.quality, why)
					elseif fight.rule == "grey" then
						assert.are.equal(math.min(fight.debt or 0, 2), ear.quality, why)
					else
						local score = 0
						for _, band in ipairs(fight.why) do
							score = score + fight.points[band]
						end
						assert.are.equal(ear.quality, ns.Appraisal.Bucket(score), why)
					end
				end
			end)

			it("loads the same way a second time", function()
				local once = saved()
				load(once)
				assert.are.same(once, saved())
			end)

			it("shows in the pouch, its tooltips and every tab without an error", function()
				wow.slash("/ears")
				for _, ear in ipairs(ns.db.ears) do
					ns.EarsTab.TooltipLines(ear)
				end
				for _, title in ipairs(ns.Pouch.TabTitles()) do
					ns.Pouch.SelectTab(title)
				end
				assert.are.same({}, ns.db.errors)
			end)
		end)
	end

	it("v1.4.0 keeps the grades you hid", function()
		load(fixture("v1.4.0"))
		assert.are.same({ [0] = true }, _G.EarCollectorCharDB.hiddenGrades)
	end)

	it("a newer version keeps everything, and you're told once", function()
		local newer = fixture("newer")
		local ns = load(newer)
		assert.are.equal(99, _G.EarCollectorDB.schema)
		assert.are.equal(99, _G.EarCollectorCharDB.schema)
		local ear, old = ns.db.ears[1], newer.EarCollectorCharDB.ears[1]
		assert.are.equal(old.note, ear.note)
		assert.are.same(old.fight, ear.fight)
		assert.are.same(newer.EarCollectorCharDB.folders, _G.EarCollectorCharDB.folders)
		assert.are.equal("grade", ns.db.settings.pouchSort)
		assert.are.equal(2, _G.EarCollectorDB.ui.pouchTab)
		assert.are.equal(1, wow.printed("saved by a newer version"))
		ns.EarsTab.TooltipLines(ear)
		assert.are.same({}, ns.db.errors)
	end)
end)

describe("the steps that change what's saved", function()
	local Database, ns

	before_each(function()
		ns = load({})
		Database = ns.Database
	end)

	it("run once each, in order, from the schema a table was saved at", function()
		Database.SCHEMA = 5
		for n = 4, 5 do
			Database.STEPS.character[n] = function(db)
				db.ran = (db.ran or "") .. n
			end
		end
		assert.are.equal("45", Database.MigrateCharacter({ schema = 3 }).ran)
		assert.are.equal("5", Database.MigrateCharacter({ schema = 4 }).ran)
		local current = { schema = 5 }
		assert.are.equal(current, Database.MigrateCharacter(current)) -- nothing to do: no copy
		assert.is_nil(current.ran)
		assert.are.equal(5, Database.MigrateCharacter(nil).schema)
	end)

	it("leave a table exactly as it was when one fails, and try again next load", function()
		local character = fixture("v1.4.0").EarCollectorCharDB
		local step = Database.STEPS.character[3]
		Database.STEPS.character[3] = function(db)
			db.ears[1].name = "Changed"
			error("boom")
		end
		local db = Database.MigrateCharacter(character)
		assert.are.equal(character, db)
		assert.are.equal(2, db.schema)
		assert.are.equal("Sylvara Nightbloom", db.ears[1].name)
		assert.is_nil(db.ears[1].fight)
		assert.are.equal("saved data", ns.db.errors[1].where)

		Database.STEPS.character[3] = step
		db = Database.MigrateCharacter(db)
		assert.are.equal(Database.SCHEMA, db.schema)
		assert.is_table(db.ears[1].fight)
	end)

	it("give an ear from before fight grading the record its grade came from", function()
		local db = Database.MigrateCharacter({
			schema = 2,
			ears = {
				{ guid = "Player-1-A", at = 1, quality = 4 },
				{ guid = "Player-1-B", at = 2, quality = 5, vengeance = 3 },
				{ guid = "Player-1-C", at = 3, quality = 0 },
				{ guid = "Player-1-D", at = 4, quality = 2 },
			},
		})
		local function record(i)
			local fight = db.ears[i].fight
			return { fight.read, fight.why, fight.points, fight.rule or false }
		end
		assert.are.same({ false, { "red" }, { red = 16 }, false }, record(1))
		assert.are.same({ false, {}, {}, "vengeance" }, record(2))
		assert.are.equal(3, db.ears[2].fight.debt)
		assert.are.same({ false, {}, {}, "grey" }, record(3))
		assert.are.same({ false, {}, {}, false }, record(4))
	end)

	it("leave an ear without a record when its grade can't be explained", function()
		local db = Database.MigrateCharacter({
			schema = 2,
			ears = { { guid = "Player-1-A", at = 1, quality = 5 } }, -- Legendary, but no vengeance
		})
		assert.is_nil(db.ears[1].fight)
	end)

	it("give an ear graded by its fight each band's points and its rule", function()
		local db = Database.MigrateCharacter({
			schema = 2,
			ears = {
				{
					guid = "Player-1-A",
					at = 1,
					quality = 4,
					fight = { read = true, debt = 2, earlier = 1, why = { "nearDeath", "revenge", "repeat", "ambush" } },
				},
				{ guid = "Player-1-B", at = 2, quality = 1, fight = { read = true, debt = 1, why = { "revenge" } } },
				{ guid = "Player-1-C", at = 3, quality = 0, fight = { read = true, debt = 0, why = { "zerg" } } },
			},
		})
		assert.are.same({ nearDeath = 8, revenge = 18, ["repeat"] = -4 }, db.ears[1].fight.points)
		assert.is_nil(db.ears[1].fight.rule)
		assert.is_nil(db.ears[2].fight.rule) -- a grey ear raised by revenge reads as an ordinary one
		assert.are.equal("grey", db.ears[3].fight.rule)
	end)
end)
