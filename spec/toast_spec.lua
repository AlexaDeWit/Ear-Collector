local wow = require("spec.support.wow")

local ME = "Player-4395-0000000A"
local GRIMBASH = "Player-4395-0B1C2D3E"
local VELARIA = "Player-4395-0C1D2E3F"
local GROUPMATE = "Player-4395-0000BEEF"

describe("loot toast", function()
	local ns, Toast

	before_each(function()
		wow.reset()
		wow.addPlayer(GRIMBASH, { name = "Grimbash", class = "Warrior", race = "Orc", level = 60 })
		wow.addPlayer(VELARIA, { name = "Velaria", class = "Rogue", race = "Troll", level = 63 })
		wow.addPlayer(GROUPMATE, { name = "Brakka", class = "Warrior", race = "Human", level = 60 })
		wow.state().group[GROUPMATE] = true
		ns = wow.loadAddon("EarCollector.toc")
		Toast = ns.Toast
	end)

	local function kills(n)
		for i = 1, n do
			local guid = ("Player-1-%08X"):format(i)
			wow.addPlayer(guid, { name = "Victim" .. i, class = "Mage", race = "Orc", level = 60 })
			wow.fireEvent("PARTY_KILL", ME, guid)
		end
	end

	it("pops up when you collect an ear, with art, name, details and a sound", function()
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		local active = Toast.Active()
		assert.are.equal(1, #active)
		local toast = active[1]
		assert.is_true(toast:IsShown())
		assert.are.equal("You collected", toast.label:GetText())
		assert.are.equal("|cff1eff00Grimbash's Ear|r", toast.title:GetText())
		assert.are.equal("Level 60 Orc Warrior", toast.detail:GetText())
		assert.are.equal(ns.Art.EarTexture("Orc", GRIMBASH), toast.icon.texture)
		assert.is_true(toast.appear:IsPlaying())
		assert.is_true(toast.leave:IsPlaying())
		assert.are.same({ { id = 51402, channel = "SFX" } }, wow.state().sounds)
	end)

	it("plays the epic loot sound for a Rare ear", function()
		wow.state().playerLevel = 59
		wow.fireEvent("PARTY_KILL", ME, VELARIA) -- 4 levels above you: orange, Rare
		assert.are.equal(3, ns.db.ears[1].quality)
		assert.are.equal(31578, wow.state().sounds[1].id)
	end)

	it("plays the epic loot sound for an Epic ear too", function()
		wow.state().playerLevel = 58
		wow.fireEvent("PARTY_KILL", ME, VELARIA) -- 5 levels above you: red, Epic
		assert.are.equal(4, ns.db.ears[1].quality)
		assert.are.equal(31578, wow.state().sounds[1].id)
	end)

	it("names a groupmate's killing blow, and marks assists", function()
		wow.fireEvent("PARTY_KILL", GROUPMATE, GRIMBASH)
		assert.are.equal("Level 60 Orc Warrior · Killing blow: Brakka", Toast.Active()[1].detail:GetText())

		wow.fireEvent("PLAYER_ENTERING_WORLD", false, false)
		wow.advance(30) -- a later fight, so this credit isn't the group kill's
		wow.fireEvent("UNIT_DIED", VELARIA)
		wow.honorableKill()
		wow.advance(3)
		local toast = Toast.Active()[1]
		assert.are.equal("Assist collected", toast.label:GetText())
		assert.matches("· Assist$", toast.detail:GetText())
	end)

	it("doesn't pop up for a camped repeat kill", function()
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		wow.state().now = wow.state().now + 60
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		assert.are.equal(1, #Toast.Active())
		assert.are.equal(1, #wow.state().sounds)
	end)

	it("goes away when it has faded, and reuses its frame next time", function()
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		local first = Toast.Active()[1]
		wow.finishAnimations()
		assert.are.equal(0, #Toast.Active())
		assert.is_false(first:IsShown())
		wow.fireEvent("PARTY_KILL", ME, VELARIA)
		assert.are.equal(first, Toast.Active()[1])
	end)

	it("stacks up to three, newest on top, and drops the oldest", function()
		kills(4)
		local active = Toast.Active()
		assert.are.equal(Toast.MAX, #active)
		assert.matches("Victim4", active[1].title:GetText())
		assert.matches("Victim2", active[3].title:GetText())
		local _, _, _, _, firstY = active[1]:GetPoint(1)
		local _, _, _, _, secondY = active[2]:GetPoint(1)
		assert.are.equal(Toast.TOP, firstY)
		assert.are.equal(Toast.TOP - Toast.HEIGHT - Toast.GAP, secondY)
	end)

	it("pauses and shows the ear's tooltip while hovered", function()
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		local toast = Toast.Active()[1]
		toast:Enter()
		assert.is_false(toast.leave:IsPlaying())
		assert.are.equal(toast, _G.GameTooltip.owner)
		assert.are.equal("Grimbash's Ear", _G.GameTooltip.lines[1])
		toast:Leave()
		assert.is_true(toast.leave:IsPlaying())
		assert.is_false(_G.GameTooltip:IsShown())
	end)

	it("opens the pouch on the ear when clicked, and just closes on right-click", function()
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		Toast.Active()[1]:Click("LeftButton")
		assert.are.equal(0, #Toast.Active())
		assert.is_true(ns.Pouch.IsShown())
		assert.is_true(ns.EarsTab.Widgets().slots[1].highlightLocked)

		ns.Pouch.Hide()
		wow.fireEvent("PARTY_KILL", ME, VELARIA)
		Toast.Active()[1]:Click("RightButton")
		assert.are.equal(0, #Toast.Active())
		assert.is_false(ns.Pouch.IsShown())
	end)

	it("isn't pooled twice when clicked while hovered", function()
		kills(1)
		local toast = Toast.Active()[1]
		toast:Enter()
		toast:Click("RightButton") -- hides it, which sends OnLeave and replays the fade
		wow.finishAnimations()
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		wow.fireEvent("PARTY_KILL", ME, VELARIA)
		local active = Toast.Active()
		assert.are.equal(2, #active)
		assert.are_not.equal(active[1], active[2])
	end)

	it("can be turned off, or muted", function()
		wow.slash("/ears sound off")
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		assert.are.equal(1, #Toast.Active())
		assert.are.equal(0, #wow.state().sounds)

		wow.slash("/ears toast off")
		wow.fireEvent("PARTY_KILL", ME, VELARIA)
		assert.are.equal(1, #Toast.Active())
		assert.are.equal(2, #ns.db.ears) -- the ear is still collected
	end)

	it("contains an error from a click", function()
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		ns.EarsTab.Focus = function()
			error("boom")
		end
		assert.has_no.errors(function()
			Toast.Active()[1]:Click("LeftButton")
		end)
		assert.are.equal("toast", ns.db.errors[1].where)
	end)
end)
