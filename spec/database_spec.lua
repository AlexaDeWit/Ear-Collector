local wow = require("spec.support.wow")

describe("Database", function()
	local Database

	before_each(function()
		wow.reset()
		Database = wow.loadAddon("EarCollector.toc").Database
	end)

	it("creates a fresh database with default settings", function()
		local db = Database.Migrate(nil)
		assert.are.equal(Database.SCHEMA, db.schema)
		assert.are.same({}, db.ears)
		assert.are.equal(0, db.stats.hiddenKills)
		assert.are.same(Database.DEFAULT_SETTINGS, db.settings)
		assert.are.same({}, db.errors)
	end)

	it("keeps saved ears and settings, filling in new defaults", function()
		local saved = {
			schema = 1,
			ears = { { guid = "Player-1-A", name = "Grimbash", at = 100, lastAt = 200, camped = 1, quality = 3 } },
			settings = { campWindow = 300 },
		}
		local db = Database.Migrate(saved)
		assert.are.equal(saved, db)
		assert.are.equal(1, #db.ears)
		assert.are.equal(3, db.ears[1].quality)
		assert.are.equal(300, db.settings.campWindow)
		assert.is_true(db.settings.announce)
	end)

	it("repairs damaged saved data instead of failing later", function()
		local db = Database.Migrate({
			schema = "one",
			ears = {
				"garbage",
				{ name = "No GUID", at = 1 },
				{ guid = "Player-1-A", at = 100 }, -- missing optional fields
				{ guid = "Player-1-B", at = 200, name = 5, quality = 42, camped = "x" },
			},
			stats = 7,
			settings = { campWindow = "ten minutes", debug = "yes" },
			errors = false,
		})
		assert.are.equal(Database.SCHEMA, db.schema)
		assert.are.equal(2, #db.ears)
		assert.are.same(
			{ guid = "Player-1-A", at = 100, lastAt = 100, camped = 0, quality = 2, name = "Unknown" },
			db.ears[1]
		)
		assert.are.equal("Unknown", db.ears[2].name)
		assert.are.equal(2, db.ears[2].quality)
		assert.are.equal(0, db.ears[2].camped)
		assert.are.equal(0, db.stats.hiddenKills)
		assert.are.equal(600, db.settings.campWindow)
		assert.is_false(db.settings.debug)
		assert.are.same({}, db.errors)
	end)

	it("loads cleanly from a damaged SavedVariables file", function()
		wow.reset()
		local ns = wow.loadAddon("EarCollector.toc", { EarCollectorDB = { ears = 12, settings = "?" } })
		assert.are.same({}, ns.db.ears)
		assert.are.equal(ns.db, _G.EarCollectorDB)
		assert.are.equal(0, #ns.db.errors)
	end)

	it("keeps the debug log bounded", function()
		local db = Database.Migrate(nil)
		for i = 1, Database.DEBUG_LOG_SIZE + 10 do
			Database.LogDebug(db, { n = i })
		end
		assert.are.equal(Database.DEBUG_LOG_SIZE, #db.debugLog)
		assert.are.equal(11, db.debugLog[1].n)
	end)
end)
