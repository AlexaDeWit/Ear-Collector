local wow = require("spec.support.wow")

local ME = "Player-4395-0000000A"
local GRIMBASH = "Player-4395-0B1C2D3E"

describe("error containment", function()
	local ns

	before_each(function()
		wow.reset()
		wow.addPlayer(GRIMBASH, { name = "Grimbash", class = "Warrior", race = "Orc", level = 60 })
		ns = wow.loadAddon("EarCollector.toc")
	end)

	describe("a UI error never switches off kill detection", function()
		local victims = {}

		before_each(function()
			for i = 1, 4 do
				victims[i] = ("Player-1-%08X"):format(i)
				wow.addPlayer(victims[i], { name = "V" .. i, class = "Mage", race = "Orc", level = 60 })
			end
		end)

		local function killAll()
			for i = 1, 4 do
				wow.fireEvent("PARTY_KILL", ME, victims[i])
			end
		end

		it("keeps collecting when the pouch fails to build", function()
			_G.PanelTemplates_SetNumTabs = function()
				error("template differs")
			end
			wow.slash("/ears")
			wow.slash("/ears")
			killAll()
			assert.are.equal(4, #ns.db.ears)
			assert.is_false(ns.Errors.IsDisabled("PARTY_KILL handler 1"))
			assert.is_false(ns.Pouch.IsShown())
			assert.are.equal(1, #ns.db.errors) -- built once, not retried on every refresh
			assert.are.equal("pouch", ns.db.errors[1].where)
		end)

		it("keeps collecting and recording deaths when the pouch refresh fails", function()
			ns.Pouch.Refresh = function()
				error("refresh bug")
			end
			killAll()
			for _ = 1, 3 do
				ns.RecordDeath(ns.db, { guid = GRIMBASH, name = "Grimbash" })
			end
			assert.are.equal(4, #ns.db.ears)
			assert.are.equal(3, #ns.db.deaths)
			assert.is_false(ns.Errors.IsDisabled("PARTY_KILL handler 1"))
		end)

		it("keeps collecting when the toast or chat line fails", function()
			ns.Toast.Show = function()
				error("toast bug")
			end
			ns.Chat.Announce = function()
				error("chat bug")
			end
			killAll()
			assert.are.equal(4, #ns.db.ears)
			assert.is_false(ns.Errors.IsDisabled("PARTY_KILL handler 1"))
		end)
	end)

	it("stays quiet if reporting an error fails", function()
		local realPrint = _G.print
		_G.print = function()
			error("chat frame gone")
		end
		local ok
		assert.has_no.errors(function()
			ok = ns.Errors.Call("x", function()
				error("boom")
			end)
		end)
		_G.print = realPrint
		assert.is_false(ok)
	end)

	local function printedMatching(pattern)
		local n = 0
		for _, line in ipairs(wow.state().printed) do
			if line:find(pattern) then
				n = n + 1
			end
		end
		return n
	end

	it("keeps a handler's error inside the addon and records it", function()
		ns.On("PARTY_KILL", function()
			error("boom")
		end)
		assert.has_no.errors(function()
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		end)
		assert.are.equal(1, #ns.db.errors)
		local entry = ns.db.errors[1]
		assert.are.equal("PARTY_KILL handler 2", entry.where)
		assert.matches("boom", entry.message)
		assert.are.equal("dev", entry.version)
		assert.are.equal(1, printedMatching("Hit an error and kept going"))
	end)

	it("still runs the other handlers for the same event", function()
		ns.On("PARTY_KILL", function()
			error("boom")
		end)
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		assert.are.equal(1, #ns.db.ears) -- the real detector (handler 1) still collected the ear
	end)

	it("warns once per session, then switches a repeatedly failing handler off", function()
		local calls = 0
		ns.On("PARTY_KILL", function()
			calls = calls + 1
			error("boom " .. calls)
		end)
		for _ = 1, 5 do
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		end
		assert.are.equal(3, calls) -- MAX_PER_HANDLER, then it is no longer called
		assert.is_true(ns.Errors.IsDisabled("PARTY_KILL handler 2"))
		assert.are.equal(3, #ns.db.errors)
		assert.are.equal(1, printedMatching("Hit an error and kept going"))
		assert.are.equal(1, printedMatching("Turned off PARTY_KILL handler 2 after repeated errors"))
	end)

	it("keeps the error log bounded", function()
		for i = 1, ns.Errors.LOG_SIZE + 5 do
			ns.Errors.Report("test " .. i, { message = "boom" })
		end
		assert.are.equal(ns.Errors.LOG_SIZE, #ns.db.errors)
		assert.are.equal("test 6", ns.db.errors[1].where)
	end)

	it("saves errors raised before SavedVariables loaded", function()
		wow.reset()
		local loadedNs = wow.loadAddon("EarCollector.toc", { EarCollectorDB = { ears = {} } })
		-- simulate an error reported while ns.db was not yet set
		local db = loadedNs.db
		loadedNs.db = nil
		loadedNs.Errors.Report("early", { message = "too soon" })
		loadedNs.db = db
		loadedNs.Errors.Flush()
		assert.are.equal("early", db.errors[1].where)
	end)

	it("contains errors in slash commands", function()
		ns.db.ears = "not a table" -- corrupt state at runtime
		assert.has_no.errors(function()
			wow.slash("/ears stats")
		end)
		assert.are.equal("/ears stats", ns.db.errors[1].where)
	end)

	it("lists caught errors with /ears errors and clears them", function()
		ns.Errors.Report("PARTY_KILL handler 1", { message = "attempt to index a nil value" })
		wow.slash("/ears errors")
		assert.are.equal(1, printedMatching("in PARTY_KILL handler 1 %(dev%): attempt to index a nil value"))
		wow.slash("/ears errors clear")
		assert.are.equal(0, #ns.db.errors)
	end)
end)
