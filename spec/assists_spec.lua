local wow = require("spec.support.wow")

local ME = "Player-4395-0000000A"
local GRIMBASH = "Player-4395-0B1C2D3E"
local VELARIA = "Player-4395-0C1D2E3F"
local ALLY = "Player-4395-0000A11E" -- a friendly player outside your group
local GROUPMATE = "Player-4395-0000BEEF"

describe("Assists", function()
	describe("matching (pure)", function()
		local Assists, tracker

		before_each(function()
			wow.reset()
			Assists = wow.loadAddon("EarCollector.toc").Assists
			tracker = Assists.New()
		end)

		local function death(guid, t)
			Assists.NoteDeath(tracker, { guid = guid, t = t, kill = { guid = guid, name = guid } })
		end

		it("ties an honor credit to the one enemy who died next to it", function()
			death(GRIMBASH, 100)
			Assists.NoteHonor(tracker, 1, 101)
			local assists, unnamed = Assists.Resolve(tracker, 104)
			assert.are.equal(1, #assists)
			assert.are.equal(GRIMBASH, assists[1].guid)
			assert.are.equal(0, unnamed)
		end)

		it("waits until the window has passed, for late events", function()
			Assists.NoteHonor(tracker, 1, 100)
			local assists, unnamed, pending = Assists.Resolve(tracker, 101)
			assert.are.same({}, assists)
			assert.are.equal(0, unnamed)
			assert.are.equal(1, pending)
			death(GRIMBASH, 101.5) -- the death arrives after the credit
			assists = Assists.Resolve(tracker, 103)
			assert.are.equal(1, #assists)
		end)

		it("uses a credit up on your group's own kill instead of making an assist", function()
			death(GRIMBASH, 100)
			Assists.NoteGroupKill(tracker, GRIMBASH, 100)
			Assists.NoteHonor(tracker, 1, 100.5)
			local assists, unnamed = Assists.Resolve(tracker, 104)
			assert.are.same({}, assists)
			assert.are.equal(0, unnamed)
		end)

		it("splits credits between a group kill and an assist", function()
			death(GRIMBASH, 100)
			death(VELARIA, 100.2)
			Assists.NoteGroupKill(tracker, GRIMBASH, 100)
			Assists.NoteHonor(tracker, 2, 100.5)
			local assists = Assists.Resolve(tracker, 104)
			assert.are.equal(1, #assists)
			assert.are.equal(VELARIA, assists[1].guid)
		end)

		it("names nobody when more players died than credits arrived", function()
			death(GRIMBASH, 100)
			death(VELARIA, 100.4)
			Assists.NoteHonor(tracker, 1, 100.5)
			local assists, unnamed = Assists.Resolve(tracker, 104)
			assert.are.same({}, assists)
			assert.are.equal(1, unnamed)
		end)

		it("counts a credit with no death nearby as unnamed", function()
			death(GRIMBASH, 90) -- too early
			Assists.NoteHonor(tracker, 1, 100)
			local assists, unnamed = Assists.Resolve(tracker, 104)
			assert.are.same({}, assists)
			assert.are.equal(1, unnamed)
		end)

		it("never gives one death two credits", function()
			death(GRIMBASH, 100)
			Assists.NoteHonor(tracker, 1, 100.5)
			Assists.NoteHonor(tracker, 1, 101)
			local assists, unnamed = Assists.Resolve(tracker, 105)
			assert.are.equal(1, #assists)
			assert.are.equal(1, unnamed)
		end)

		it("treats UNIT_DIED and PARTY_KILL reports of one death as one", function()
			death(GRIMBASH, 100)
			death(GRIMBASH, 100.1)
			assert.are.equal(1, #tracker.deaths)
		end)

		it("forgets old deaths", function()
			death(GRIMBASH, 100)
			death(VELARIA, 100 + Assists.KEEP + 1)
			assert.are.equal(1, #tracker.deaths)
			assert.are.equal(VELARIA, tracker.deaths[1].guid)
		end)
	end)

	describe("in game", function()
		local ns

		before_each(function()
			wow.reset()
			wow.addPlayer(GRIMBASH, { name = "Grimbash", class = "Warrior", race = "Orc", level = 60 })
			wow.addPlayer(VELARIA, { name = "Velaria", class = "Rogue", race = "Troll", level = 58 })
			wow.addPlayer(GROUPMATE, { name = "Brakka", class = "Warrior", race = "Human", level = 60 })
			wow.state().group[GROUPMATE] = true
			ns = wow.loadAddon("EarCollector.toc")
			wow.fireEvent("PLAYER_ENTERING_WORLD", false, false)
		end)

		it("collects an assist when an ally outside your group lands the blow", function()
			wow.fireEvent("UNIT_DIED", GRIMBASH)
			wow.advance(0.4)
			wow.honorableKill()
			assert.are.equal(0, #ns.db.ears) -- not until the window closes
			wow.advance(3)
			assert.are.equal(1, #ns.db.ears)
			local ear = ns.db.ears[1]
			assert.are.equal("assist", ear.by)
			assert.are.equal("Grimbash", ear.name)
			assert.are.equal(60, ear.level)
			assert.matches("You collected .*Grimbash's Ear.*Assist%.", wow.state().printed[1])
		end)

		it("collects an assist when PARTY_KILL names a killer outside the group", function()
			wow.fireEvent("PARTY_KILL", ALLY, VELARIA)
			wow.honorableKill()
			wow.advance(3)
			assert.are.equal(1, #ns.db.ears)
			assert.are.equal("assist", ns.db.ears[1].by)
		end)

		it("doesn't add an assist on top of your group's own kill", function()
			wow.fireEvent("UNIT_DIED", GRIMBASH)
			wow.fireEvent("PARTY_KILL", GROUPMATE, GRIMBASH)
			wow.honorableKill()
			wow.advance(3)
			assert.are.equal(1, #ns.db.ears)
			assert.are.equal("group", ns.db.ears[1].by)
			assert.are.equal(0, ns.db.stats.unnamedHonorKills)
		end)

		it("needs honor credit: a death you only watched is no assist", function()
			wow.fireEvent("UNIT_DIED", GRIMBASH)
			wow.advance(20)
			assert.are.equal(0, #ns.db.ears)
		end)

		it("ignores honor in battlegrounds", function()
			wow.state().inInstance, wow.state().instanceType = true, "pvp"
			wow.fireEvent("UNIT_DIED", GRIMBASH)
			wow.honorableKill(3)
			wow.advance(3)
			assert.are.equal(0, #ns.db.ears)
			assert.are.equal(0, ns.db.stats.unnamedHonorKills)
		end)

		it("ignores your own death and your groupmates' deaths", function()
			wow.fireEvent("UNIT_DIED", ME)
			wow.fireEvent("UNIT_DIED", GROUPMATE)
			wow.honorableKill()
			wow.advance(3)
			assert.are.equal(0, #ns.db.ears)
			assert.are.equal(1, ns.db.stats.unnamedHonorKills)
		end)

		it("skips hidden (secret) deaths and creature deaths without error", function()
			wow.fireEvent("UNIT_DIED", wow.secret())
			wow.fireEvent("UNIT_DIED", "Creature-0-4395-0-1-2738-00001234")
			wow.honorableKill()
			wow.advance(3)
			assert.are.equal(0, #ns.db.ears)
			assert.are.equal(0, #ns.db.errors)
		end)

		it("only starts counting once it knows the honorable-kill baseline", function()
			wow.reset()
			wow.addPlayer(GRIMBASH, { name = "Grimbash", class = "Warrior", race = "Orc", level = 60 })
			ns = wow.loadAddon("EarCollector.toc") -- no PLAYER_ENTERING_WORLD yet
			wow.fireEvent("UNIT_DIED", GRIMBASH)
			wow.honorableKill()
			wow.advance(3)
			assert.are.equal(0, #ns.db.ears)
		end)

		it("logs assist decisions while debug is on", function()
			ns.db.settings.debug = true
			wow.fireEvent("UNIT_DIED", GRIMBASH)
			wow.honorableKill()
			wow.advance(3)
			local decisions = {}
			for _, entry in ipairs(ns.db.debugLog) do
				decisions[#decisions + 1] = entry.event .. ": " .. entry.decision
			end
			assert.are.same({ "UNIT_DIED: assist candidate", "HONOR: new ear (assist)" }, decisions)
		end)

		it("contains an error in the delayed matching", function()
			wow.fireEvent("UNIT_DIED", GRIMBASH)
			wow.honorableKill()
			ns.Ears.Record = function()
				error("boom")
			end
			assert.has_no.errors(function()
				wow.advance(3)
			end)
			assert.are.equal("assist matching", ns.db.errors[1].where)
		end)
	end)
end)
