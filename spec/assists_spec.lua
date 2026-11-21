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
			local early, _, stillPending = Assists.Resolve(tracker, 103)
			assert.are.same({}, early) -- another credit could still link to that death
			assert.are.equal(1, stillPending)
			assists = Assists.Resolve(tracker, 104)
			assert.are.equal(1, #assists)
		end)

		it("names both enemies when two die a second apart, each followed by a credit", function()
			death(GRIMBASH, 100)
			Assists.NoteHonor(tracker, 1, 100.5)
			death(VELARIA, 101)
			Assists.NoteHonor(tracker, 1, 101.5)
			local early, _, pending = Assists.Resolve(tracker, 103.2)
			assert.are.same({}, early) -- the second credit is still settling
			assert.are.equal(2, pending)
			local assists, unnamed = Assists.Resolve(tracker, 104.1)
			assert.are.equal(2, #assists)
			assert.are.equal(0, unnamed)
		end)

		it("names nobody when three die near two credits", function()
			death(GRIMBASH, 100)
			death(VELARIA, 100.5)
			death(ALLY, 101)
			Assists.NoteHonor(tracker, 1, 101)
			Assists.NoteHonor(tracker, 1, 101.5)
			local assists, unnamed = Assists.Resolve(tracker, 105)
			assert.are.same({}, assists)
			assert.are.equal(2, unnamed)
		end)

		it("keeps a death far from any credit out of a clear match", function()
			death(VELARIA, 90) -- someone else's kill, long before
			death(GRIMBASH, 100)
			Assists.NoteHonor(tracker, 1, 100.5)
			local assists = Assists.Resolve(tracker, 104)
			assert.are.equal(1, #assists)
			assert.are.equal(GRIMBASH, assists[1].guid)
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

		it("hands back the deaths no credit named, once they settle", function()
			death(GRIMBASH, 100) -- no credit at all
			local _, _, _, early, settling = Assists.Resolve(tracker, 101)
			assert.are.same({}, early)
			assert.are.equal(1, settling)
			death(VELARIA, 110)
			death(ALLY, 110.5)
			Assists.NoteHonor(tracker, 1, 111) -- one credit for two deaths
			local _, unnamed, _, unclaimed = Assists.Resolve(tracker, 114)
			assert.are.equal(1, unnamed)
			local guids = {}
			for _, d in ipairs(unclaimed) do
				guids[#guids + 1] = d.guid
			end
			table.sort(guids)
			local expected = { GRIMBASH, VELARIA, ALLY }
			table.sort(expected)
			assert.are.same(expected, guids)
			local _, _, _, again = Assists.Resolve(tracker, 115)
			assert.are.same({}, again) -- each death is handed back once
		end)

		it("keeps your group's kills out of the unclaimed deaths", function()
			death(GRIMBASH, 100)
			Assists.NoteGroupKill(tracker, GRIMBASH, 100)
			local _, _, _, unclaimed = Assists.Resolve(tracker, 104)
			assert.are.same({}, unclaimed)
		end)

		describe("from the damage meter", function()
			local function kill(guid, t)
				return { guid = guid, t = t, kill = { guid = guid, name = guid } }
			end

			it("names a death you damaged during your fight or soon after", function()
				local fight = { start = 100, finish = 130 }
				local assists, rejected = Assists.FromDamage({
					kill(GRIMBASH, 99), -- just before the fight started
					kill(VELARIA, 130 + Assists.RECENT),
				}, { [GRIMBASH] = "Grimbash", [VELARIA] = false }, fight)
				assert.are.equal(2, #assists)
				assert.are.same({}, rejected)
			end)

			it("rejects a death you didn't damage, or outside your fight", function()
				local fight = { start = 100, finish = 130 }
				local _, rejected = Assists.FromDamage({
					kill(GRIMBASH, 120),
					kill(VELARIA, 100 - Assists.WINDOW - 1),
					kill(ALLY, 130 + Assists.RECENT + 1),
				}, { [VELARIA] = "Velaria", [ALLY] = "Ally" }, fight)
				assert.are.same({
					{ guid = GRIMBASH, reason = "not on the damage meter" },
					{ guid = VELARIA, reason = "not during or just after your last fight" },
					{ guid = ALLY, reason = "not during or just after your last fight" },
				}, rejected)
			end)

			it("names nothing before your first fight, and counts a fight still going", function()
				local _, rejected = Assists.FromDamage({ kill(GRIMBASH, 100) }, { [GRIMBASH] = "Grimbash" }, nil)
				assert.are.same({ { guid = GRIMBASH, reason = "no fight on record" } }, rejected)
				local assists = Assists.FromDamage(
					{ kill(GRIMBASH, 500) },
					{ [GRIMBASH] = "Grimbash" },
					{ start = 100 }
				)
				assert.are.equal(1, #assists)
			end)
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

		it("replays an assist recorded in Western Plaguelands", function()
			wow.replay(dofile("spec/fixtures/western_plaguelands_assist.lua"))
			assert.are.equal(1, #ns.db.ears)
			local ear = ns.db.ears[1]
			assert.are.equal("assist", ear.by)
			assert.are.equal("Tobble Sparkwhistle", ear.name)
			assert.is_nil(ear.surname)
			assert.are.equal(3, ear.quality) -- 6 levels above you: Rare
			assert.are.equal("Dalson's Tears", ear.subzone)
			assert.matches("Tobble Sparkwhistle's Ear.*%(Rare%)%. Assist%.", wow.state().printed[1])
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
			assert.are.same({
				"UNIT_DIED: assist candidate",
				"HONOR: +1 honorable kill(s), 121 lifetime",
				"HONOR: new ear (assist)",
			}, decisions)
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
