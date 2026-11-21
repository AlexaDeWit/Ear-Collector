local wow = require("spec.support.wow")

local ME = "Player-4395-0000000A"
local GRIMBASH = "Player-4395-0B1C2D3E"
local VELARIA = "Player-1-00FF00FF"

describe("PARTY_KILL detection", function()
	local ns

	before_each(function()
		wow.reset()
		wow.addPlayer(GRIMBASH, { name = "Grimbash", class = "Warrior", race = "Orc", level = 60 })
		ns = wow.loadAddon("EarCollector.toc")
	end)

	it("collects an ear for your killing blow on a player in the open world", function()
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		assert.are.equal(1, #ns.db.ears)
		local ear = ns.db.ears[1]
		assert.are.equal("Grimbash", ear.name)
		assert.is_nil(ear.realm) -- same realm
		assert.are.equal("WARRIOR", ear.class)
		assert.are.equal("Orc", ear.race)
		assert.are.equal(60, ear.level)
		assert.are.equal(60, ear.yourLevel)
		assert.are.equal(1424, ear.mapID)
		assert.are.equal("Tarren Mill", ear.subzone)
		assert.are.equal(2, ear.quality)
		assert.matches("You collected .*Grimbash's Ear.* %(Uncommon%)", wow.state().printed[1])
	end)

	it("keeps the realm of a player from another realm", function()
		wow.addPlayer(VELARIA, { name = "Velaria", realm = "Stonemaul", class = "Rogue", race = "Scourge" })
		wow.fireEvent("PARTY_KILL", ME, VELARIA)
		assert.are.equal("Stonemaul", ns.db.ears[1].realm)
		assert.is_nil(ns.db.ears[1].level) -- level unknown
		assert.are.equal(2, ns.db.ears[1].quality)
	end)

	it("collects an ear when a group member lands the killing blow", function()
		wow.addPlayer(VELARIA, { name = "Velaria", class = "Rogue", race = "Human" })
		wow.state().group[VELARIA] = true
		wow.fireEvent("PARTY_KILL", VELARIA, GRIMBASH)
		assert.are.equal(1, #ns.db.ears)
		assert.are.equal("group", ns.db.ears[1].by)
		assert.are.equal("Velaria", ns.db.ears[1].killer)
		assert.matches("You collected .*Grimbash's Ear.*Killing blow: Velaria%.", wow.state().printed[1])
	end)

	it("credits your own killing blows and your pet's to you", function()
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		assert.are.equal("you", ns.db.ears[1].by)
		assert.is_nil(ns.db.ears[1].killer)

		wow.addPlayer("Player-4395-0C0C0C0C", { name = "Drogmar", class = "Shaman", race = "Orc" })
		wow.state().units.pet = "Pet-0-4395-0-1-416-0100000001"
		wow.fireEvent("PARTY_KILL", "Pet-0-4395-0-1-416-0100000001", "Player-4395-0C0C0C0C")
		assert.are.equal("you", ns.db.ears[2].by)
	end)

	it("counts a group member's pet", function()
		wow.state().units.partypet2 = "Pet-0-4395-0-1-1860-0200000002"
		wow.fireEvent("PARTY_KILL", "Pet-0-4395-0-1-1860-0200000002", GRIMBASH)
		assert.are.equal(1, #ns.db.ears)
		assert.are.equal("group", ns.db.ears[1].by)
	end)

	it("ignores killing blows by players and pets outside your group", function()
		wow.fireEvent("PARTY_KILL", "Player-4395-0000BEEF", GRIMBASH)
		wow.fireEvent("PARTY_KILL", "Pet-0-4395-0-1-416-0900000009", GRIMBASH)
		assert.are.equal(0, #ns.db.ears)
	end)

	it("shows the victim's race icon, and skips it when the client has none", function()
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		assert.matches("|A:raceicon%-orc%-male:14:14|a", wow.state().printed[1])

		wow.addPlayer("Player-4395-0D0D0D0D", { name = "Nethra", class = "Mage", race = "Scourge", sex = 3 })
		wow.fireEvent("PARTY_KILL", ME, "Player-4395-0D0D0D0D")
		assert.matches("|A:raceicon%-undead%-female:14:14|a", wow.state().printed[2])

		wow.addPlayer("Player-4395-0E0E0E0E", { name = "Ailee", class = "Mage", race = "Skyborne" })
		wow.fireEvent("PARTY_KILL", ME, "Player-4395-0E0E0E0E")
		assert.is_nil(wow.state().printed[3]:find("|A:", 1, true))
		assert.are.equal(3, #ns.db.ears)
	end)

	it("ignores NPCs", function()
		wow.fireEvent("PARTY_KILL", ME, "Creature-0-4395-0-1-2738-00001234")
		assert.are.equal(0, #ns.db.ears)
	end)

	it("ignores kills in battlegrounds and arenas", function()
		wow.state().inInstance, wow.state().instanceType = true, "pvp"
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		wow.state().instanceType = "arena"
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		assert.are.equal(0, #ns.db.ears)
	end)

	it("never inspects hidden (secret) GUIDs and counts them separately", function()
		wow.fireEvent("PARTY_KILL", wow.secret(), wow.secret())
		wow.fireEvent("PARTY_KILL", ME, wow.secret())
		assert.are.equal(0, #ns.db.ears)
		assert.are.equal(2, ns.db.stats.hiddenKills)
	end)

	it("skips the kill when the client hides the victim's details", function()
		wow.addPlayer(GRIMBASH, { name = wow.secret(), class = "Warrior", race = "Orc" })
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		assert.are.equal(0, #ns.db.ears)
	end)

	it("counts a camped repeat kill on the same ear", function()
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		wow.state().now = wow.state().now + 120
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		assert.are.equal(1, #ns.db.ears)
		assert.are.equal(1, ns.db.ears[1].camped)
		assert.matches("Camped Grimbash again %(kill 2%)", wow.state().printed[2])
	end)

	it("stays quiet when announcements are off", function()
		ns.db.settings.announce = false
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		assert.are.equal(1, #ns.db.ears)
		assert.are.equal(0, #wow.state().printed)
	end)

	it("logs every decision while debug is on", function()
		ns.db.settings.debug = true
		wow.fireEvent("PARTY_KILL", ME, wow.secret())
		wow.fireEvent("PARTY_KILL", "Player-4395-0000BEEF", GRIMBASH)
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		local decisions = {}
		for _, entry in ipairs(ns.db.debugLog) do
			decisions[#decisions + 1] = entry.decision
		end
		assert.are.same({ "hidden by the client", "not you or your group", "new ear (you)" }, decisions)
		assert.are.equal("<secret>", ns.db.debugLog[1].target)
	end)

	it("replays a recorded open-world skirmish", function()
		wow.replay(dofile("spec/fixtures/tarren_mill_skirmish.lua"))
		local names = {}
		for _, ear in ipairs(ns.db.ears) do
			names[#names + 1] = ear.name
		end
		assert.are.same({ "Grimbash", "Velaria", "Velaria" }, names)
		assert.are.equal("group", ns.db.ears[2].by)
		assert.are.equal("Brakka", ns.db.ears[2].killer)
		assert.are.equal(1, ns.db.ears[1].camped)
		assert.are.equal(1, ns.db.stats.hiddenKills)
	end)
end)
