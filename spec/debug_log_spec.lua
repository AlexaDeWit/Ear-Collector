local wow = require("spec.support.wow")

local ME = "Player-4395-0000000A"
local GRIMBASH = "Player-4395-0B1C2D3E"
local MOB = "Creature-0-4395-0-1-2738-00001234"

-- /ears debug is how in-game tests come back as fixtures: the saved log must
-- keep the PvP lines and the timing between events.
describe("the debug log", function()
	local ns

	before_each(function()
		wow.reset()
		wow.addPlayer(GRIMBASH, { name = "Grimbash", realm = "Ironhide", class = "Warrior", race = "Orc", level = 60 })
		ns = wow.loadAddon("EarCollector.toc")
		wow.fireEvent("PLAYER_ENTERING_WORLD", false, false)
		wow.slash("/ears debug")
	end)

	local decisions = wow.decisions

	it("logs only the first few NPC kills, so questing can't push PvP lines out", function()
		for _ = 1, ns.ROUTINE_TRACES + 5 do
			wow.fireEvent("PARTY_KILL", ME, MOB)
		end
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		local expected = {}
		for _ = 1, ns.ROUTINE_TRACES - 1 do
			expected[#expected + 1] = "PARTY_KILL: not a player"
		end
		expected[#expected + 1] = "PARTY_KILL: not a player (no more of these logged until /reload)"
		expected[#expected + 1] = "APPRAISAL: no fight record; no bands = 0: Uncommon (was Uncommon)"
		expected[#expected + 1] = "PARTY_KILL: new ear (you)"
		assert.are.same(expected, decisions())
	end)

	it("counts NPC kills toward that limit only while debug is on", function()
		wow.slash("/ears debug") -- off
		for _ = 1, ns.ROUTINE_TRACES + 1 do
			wow.fireEvent("PARTY_KILL", ME, MOB)
		end
		wow.slash("/ears debug") -- on
		wow.fireEvent("PARTY_KILL", ME, MOB)
		assert.are.same({ "PARTY_KILL: not a player" }, decisions())
	end)

	it("doesn't count a dungeon's hidden mob kills as kills the game hid", function()
		wow.state().inInstance, wow.state().instanceType = true, "party"
		for _ = 1, ns.ROUTINE_TRACES + 2 do
			wow.fireEvent("PARTY_KILL", wow.secret(), wow.secret())
		end
		assert.are.equal(0, ns.db.stats.hiddenKills)
		assert.are.equal(ns.ROUTINE_TRACES, #ns.db.debugLog)
		assert.matches("^PARTY_KILL: instance:party", decisions()[1])
	end)

	it("logs each honorable kill as it arrives, and few of those ignored in battlegrounds", function()
		wow.honorableKill()
		assert.are.same({ "HONOR: +1 honorable kill(s), 121 lifetime" }, decisions())
		wow.state().inInstance, wow.state().instanceType = true, "pvp"
		for n = 1, ns.ROUTINE_TRACES + 2 do
			wow.honorableKill(n) -- a different count each time, still one kind of line
		end
		assert.are.equal(1 + ns.ROUTINE_TRACES, #ns.db.debugLog)
		assert.matches("^HONOR: 1 honorable kill%(s%) ignored: instance:pvp$", decisions()[2])
	end)

	it("keeps the time of each entry to the millisecond, for the gaps between events", function()
		wow.fireEvent("UNIT_DIED", GRIMBASH)
		wow.advance(1.25)
		wow.honorableKill()
		local first, second = ns.db.debugLog[1], ns.db.debugLog[2]
		assert.are.equal(1.25, second.t - first.t)
		assert.are.equal("number", type(first.at))
	end)

	describe("deaths", function()
		local DeathWatch

		before_each(function()
			DeathWatch = ns.DeathWatch
		end)

		it("names who was in view when the recap's killer matches nobody", function()
			wow.state().units.target = GRIMBASH
			wow.state().recap = { { sourceName = "Grimbash Stonefist", spellName = "Mortal Strike" } }
			wow.fireEvent("PLAYER_DEAD")
			wow.advance(DeathWatch.RECAP_DELAY)
			assert.are.same({
				"PLAYER_DEAD: killer isn't an enemy player you saw or damaged"
					.. " (names: Grimbash, Grimbash Ironhide, Grimbash-Ironhide)",
			}, decisions())
		end)

		it("lists a bounded, sorted set of names, leaving out shared ones", function()
			assert.are.equal("nobody", DeathWatch.NamesInView({}))
			assert.are.equal("nobody", DeathWatch.NamesInView({ Grimbash = false }))
			local seen = {}
			for i = 1, DeathWatch.NAMES_LOGGED + 2 do
				seen[("Player%02d"):format(i)] = "Player-1-" .. i
			end
			local shown = DeathWatch.NamesInView(seen)
			assert.matches("^Player01, Player02, ", shown)
			assert.matches(("Player%02d, %%.%%.%%.$"):format(DeathWatch.NAMES_LOGGED), shown)
			assert.is_nil(shown:find(("Player%02d"):format(DeathWatch.NAMES_LOGGED + 1), 1, true))
		end)
	end)
end)
