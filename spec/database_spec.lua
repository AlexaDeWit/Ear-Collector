local wow = require("spec.support.wow")

local ME = "Player-4395-0000000A"
local GRIMBASH = "Player-4395-0B1C2D3E"

describe("Database", function()
	local Database

	before_each(function()
		wow.reset()
		Database = wow.loadAddon("EarCollector.toc").Database
	end)

	describe("account-wide data", function()
		it("starts with default settings and empty logs", function()
			local db = Database.MigrateAccount(nil)
			assert.are.equal(Database.SCHEMA, db.schema)
			assert.are.same(Database.DEFAULT_SETTINGS, db.settings)
			assert.are.same({}, db.ui)
			assert.are.same({}, db.errors)
			assert.are.same({}, db.debugLog)
			assert.is_nil(db.ears)
		end)

		it("keeps saved settings, filling in new defaults", function()
			local saved = { schema = 1, settings = { campWindow = 300 } }
			local db = Database.MigrateAccount(saved)
			assert.are.equal(saved, db)
			assert.are.equal(300, db.settings.campWindow)
			assert.is_true(db.settings.announce)
		end)

		it("repairs damaged settings, position and logs", function()
			local db = Database.MigrateAccount({
				schema = "one",
				settings = { campWindow = "ten minutes", debug = "yes" },
				ui = { pouch = 5 },
				errors = false,
			})
			assert.are.equal(Database.SCHEMA, db.schema)
			assert.are.equal(600, db.settings.campWindow)
			assert.is_false(db.settings.debug)
			assert.is_nil(db.ui.pouch)
			assert.are.same({}, db.errors)
		end)
	end)

	describe("per-character data", function()
		it("starts with no ears or deaths", function()
			local db = Database.MigrateCharacter(nil)
			assert.are.same({}, db.ears)
			assert.are.same({}, db.deaths)
			assert.are.equal(0, db.stats.hiddenKills)
			assert.are.equal(0, db.stats.unnamedHonorKills)
			assert.is_nil(db.settings)
		end)

		it("repairs damaged ears and stats instead of failing later", function()
			local db = Database.MigrateCharacter({
				ears = {
					"garbage",
					{ name = "No GUID", at = 1 },
					{ guid = "Player-1-A", at = 100 }, -- missing optional fields
					{ guid = "Player-1-B", at = 200, name = 5, quality = 42, camped = "x" },
				},
				stats = 7,
			})
			assert.are.equal(2, #db.ears)
			assert.are.same(
				{ guid = "Player-1-A", at = 100, lastAt = 100, camped = 0, quality = 2, name = "Unknown" },
				db.ears[1]
			)
			assert.are.equal("Unknown", db.ears[2].name)
			assert.are.equal(2, db.ears[2].quality)
			assert.are.equal(0, db.ears[2].camped)
			assert.are.equal(0, db.stats.hiddenKills)
		end)

		it("drops wrong-typed optional fields from saved ears and deaths", function()
			local ns = wow.loadAddon("EarCollector.toc", {
				EarCollectorCharDB = {
					ears = { { guid = GRIMBASH, at = 100, level = "sixty", zone = 5, class = {} } },
					deaths = { { guid = GRIMBASH, at = 50, spell = 7 } },
				},
			})
			local ear = ns.db.ears[1]
			assert.is_nil(ear.level)
			assert.is_nil(ear.zone)
			assert.is_nil(ear.class)
			assert.is_nil(ns.db.deaths[1].spell)
			assert.has_no.errors(function()
				ns.Pouch.TooltipLines(ear)
			end)
		end)
	end)

	describe("loading", function()
		local function load(saved)
			return wow.loadAddon("EarCollector.toc", saved)
		end

		it("loads cleanly from damaged SavedVariables files", function()
			wow.reset()
			local ns = load({ EarCollectorDB = { ears = 12, settings = "?" }, EarCollectorCharDB = 7 })
			assert.are.same({}, ns.db.ears)
			assert.are.equal(0, #ns.db.errors)
			assert.are.equal("table", type(_G.EarCollectorCharDB))
		end)

		it("saves ears per character and settings for the whole account", function()
			wow.reset()
			wow.addPlayer(GRIMBASH, { name = "Grimbash", class = "Warrior", race = "Orc", level = 60 })
			local ns = load()
			assert.are.equal(_G.EarCollectorCharDB.ears, ns.db.ears)
			assert.are.equal(_G.EarCollectorDB.settings, ns.db.settings)
			assert.are.equal(_G.EarCollectorDB.errors, ns.db.errors)
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
			wow.slash("/ears toast off")
			assert.are.equal(1, #_G.EarCollectorCharDB.ears)
			assert.is_nil(_G.EarCollectorDB.ears)
			assert.is_false(_G.EarCollectorDB.settings.toast)

			-- Log out, then in on another character: same account data, no character data.
			local account = _G.EarCollectorDB
			wow.reset()
			ns = load({ EarCollectorDB = account })
			assert.are.same({}, ns.db.ears)
			assert.is_false(ns.db.settings.toast)
		end)

		it("moves ears saved account-wide (schema 1) to the first character that loads", function()
			wow.reset()
			local ears = { { guid = GRIMBASH, name = "Grimbash", at = 100 } }
			local deaths = { { guid = GRIMBASH, name = "Grimbash", at = 50 } }
			local ns = load({ EarCollectorDB = { schema = 1, ears = ears, deaths = deaths, settings = {} } })
			assert.are.equal(1, #ns.db.ears)
			assert.are.equal(1, #ns.db.deaths)
			assert.are.equal(ears[1], _G.EarCollectorCharDB.ears[1]) -- the same records, repaired
			assert.is_nil(_G.EarCollectorDB.ears)
			assert.is_nil(_G.EarCollectorDB.deaths)
		end)

		it("leaves them for the next character if this one has its own", function()
			wow.reset()
			local shared = { { guid = GRIMBASH, name = "Grimbash", at = 100 } }
			local ns = load({
				EarCollectorDB = { ears = shared },
				EarCollectorCharDB = { ears = { { guid = "Player-1-X", name = "Own", at = 300 } } },
			})
			assert.are.equal("Own", ns.db.ears[1].name)
			assert.are.equal(shared, _G.EarCollectorDB.ears)
		end)

		it("clears the error log in place, so the clearing is saved", function()
			local ns = wow.loadAddon("EarCollector.toc")
			ns.db.errors[1] = { where = "x", message = "y", at = 1, version = "dev" }
			local saved = _G.EarCollectorDB.errors
			wow.slash("/ears errors clear")
			assert.are.equal(saved, ns.db.errors)
			assert.are.same({}, _G.EarCollectorDB.errors)
		end)
	end)

	it("keeps the debug log bounded", function()
		local db = Database.MigrateAccount(nil)
		for i = 1, Database.DEBUG_LOG_SIZE + 10 do
			Database.LogDebug(db, { n = i })
		end
		assert.are.equal(Database.DEBUG_LOG_SIZE, #db.debugLog)
		assert.are.equal(11, db.debugLog[1].n)
	end)
end)
