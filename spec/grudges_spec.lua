local wow = require("spec.support.wow")

local ME = "Player-4395-0000000A"
local GRIMBASH = "Player-4395-0B1C2D3E"
local KORGA = "Player-4395-0D1E2F30"
local DAY = 24 * 60 * 60

describe("grudges", function()
	local ns

	before_each(function()
		wow.reset()
		wow.addPlayer(GRIMBASH, { name = "Grimbash", class = "Warrior", race = "Orc", level = 60 })
		wow.addPlayer(KORGA, { name = "Korga", class = "Shaman", race = "Orc", level = 60 })
		ns = wow.loadAddon("EarCollector.toc")
		wow.fireEvent("PLAYER_ENTERING_WORLD", false, false)
	end)

	local function killedBy(n)
		for _ = 1, n do
			ns.RecordDeath(ns.db, { guid = GRIMBASH, name = "Grimbash", class = "WARRIOR", race = "Orc", level = 60 })
			wow.advance(60)
		end
	end

	local function see(unit, event, guid)
		wow.state().units[unit] = guid or GRIMBASH
		wow.fireEvent(event, unit)
	end

	local function seePlate()
		see("nameplate1", "NAME_PLATE_UNIT_ADDED")
	end

	local function grudgePopups()
		local found = {}
		for _, toast in ipairs(ns.Toast.Active()) do
			if (toast.label:GetText() or ""):find(ns.Chat.GRUDGE) then
				found[#found + 1] = toast
			end
		end
		return found
	end

	local function raidWarnings()
		local n = 0
		for _, sound in ipairs(wow.state().sounds) do
			n = n + (sound.id == 8959 and 1 or 0)
		end
		return n
	end

	local function reminders()
		return wow.printed("an unsettled grudge")
	end

	it("reminds you of a Vengeance grudge from an earlier day with a pop-up, a chat line and a raid warning", function()
		killedBy(3)
		local last = ns.Deaths.LastFought(ns.db, GRIMBASH)
		wow.advance(2 * DAY)
		seePlate()
		local popup = grudgePopups()[1]
		assert.is_table(popup)
		assert.are.equal("|cffc69b6dGrimbash|r", popup.title:GetText())
		assert.are.equal("Their next ear is Legendary", popup.detail:GetText())
		assert.are.equal(
			1,
			wow.printed(
				("Grimbash|r: an unsettled grudge%%. They took your ear three times in a row, last on %s%%. "):format(
					ns.Chat.Date(last)
				) .. "Their next ear is Legendary%.$"
			)
		)
		assert.are.equal(1, raidWarnings())
	end)

	it("stays quiet on the day you fought them, however often they come back", function()
		killedBy(3)
		wow.advance(600)
		seePlate()
		see("target", "PLAYER_TARGET_CHANGED")
		assert.are.equal(0, reminders())
		assert.are.same({}, grudgePopups())
	end)

	it("waits for a grudge to age, even across midnight", function()
		local clock = os.date("*t", wow.state().now)
		clock.hour, clock.min, clock.sec = 23, 30, 0
		wow.state().now = os.time(clock)
		killedBy(1)
		local last = ns.Deaths.LastFought(ns.db, GRIMBASH)
		assert.are.equal(0, ns.Deaths.Reminder(ns.db, GRIMBASH, last + 60 * 60)) -- just after midnight
		assert.are.equal(1, ns.Deaths.Reminder(ns.db, GRIMBASH, last + 7 * 60 * 60)) -- the next morning
	end)

	it("waits for a new day, even when the fight was hours ago", function()
		local clock = os.date("*t", wow.state().now)
		clock.hour, clock.min, clock.sec = 8, 0, 0
		wow.state().now = os.time(clock)
		killedBy(3)
		local last = ns.Deaths.LastFought(ns.db, GRIMBASH)
		assert.are.equal(0, ns.Deaths.Reminder(ns.db, GRIMBASH, last + 12 * 60 * 60)) -- that evening
	end)

	it("logs why there was no reminder while debug is on", function()
		ns.db.settings.debug = true
		killedBy(3)
		seePlate()
		assert.are.same({ "no reminder: fought too recently, or details hidden" }, wow.decisions("GRUDGE"))
	end)

	it("reminds you once a day", function()
		killedBy(3)
		wow.advance(2 * DAY)
		seePlate()
		see("target", "PLAYER_TARGET_CHANGED")
		see("mouseover", "UPDATE_MOUSEOVER_UNIT")
		assert.are.equal(1, reminders())
		wow.advance(DAY)
		seePlate()
		assert.are.equal(2, reminders())
	end)

	it("gives a lesser grudge a chat line alone", function()
		killedBy(1)
		wow.advance(2 * DAY)
		wow.state().sounds = {}
		seePlate()
		assert.are.equal(1, wow.printed("They took your ear on .*%. Their next ear is worth more%.$"))
		assert.are.same({}, grudgePopups())
		assert.are.equal(0, raidWarnings())
	end)

	it("notices them as your target or mouseover too, without nameplates", function()
		killedBy(3)
		wow.advance(2 * DAY)
		see("mouseover", "UPDATE_MOUSEOVER_UNIT")
		assert.are.equal(1, reminders())
	end)

	it("forgets a grudge once you've taken their ear", function()
		killedBy(3)
		wow.advance(DAY)
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		wow.advance(2 * DAY)
		seePlate()
		assert.are.equal(0, reminders())
	end)

	it("only reminds you where kills count", function()
		killedBy(3)
		wow.advance(2 * DAY)
		wow.state().inInstance, wow.state().instanceType = true, "pvp"
		seePlate()
		assert.are.equal(0, reminders())
	end)

	it("leaves out the raid warning when it's turned off, and the pop-up when pop-ups are", function()
		killedBy(3)
		wow.advance(2 * DAY)
		ns.db.settings.grudgeSound, ns.db.settings.toast = false, false
		wow.state().sounds = {}
		seePlate()
		assert.are.equal(1, reminders())
		assert.are.same({}, grudgePopups())
		assert.are.equal(0, raidWarnings())
	end)

	it("leaves out the chat line when chat lines are turned off", function()
		killedBy(3)
		wow.advance(2 * DAY)
		ns.db.settings.announce = false
		seePlate()
		assert.are.equal(0, reminders())
		assert.are.equal(1, #grudgePopups())
	end)

	it("ignores someone it can't identify, or doesn't hold a grudge against", function()
		killedBy(3)
		wow.advance(2 * DAY)
		see("nameplate1", "NAME_PLATE_UNIT_ADDED", wow.secret())
		see("nameplate2", "NAME_PLATE_UNIT_ADDED", KORGA)
		assert.are.equal(0, reminders())
		assert.are.equal(0, #ns.db.errors)
	end)

	describe("on their tooltip", function()
		local function hover(guid)
			wow.state().units.mouseover = guid
			_G.GameTooltip:SetUnit("mouseover")
			return _G.GameTooltip.lines
		end

		it("shows the grudge whenever you hover them, even the same day", function()
			killedBy(3)
			assert.are.same({
				"An unsettled grudge: their next ear is Legendary",
				("Took your ear three times in a row, last on %s"):format(
					ns.Chat.Date(ns.Deaths.LastFought(ns.db, GRIMBASH))
				),
			}, hover(GRIMBASH))
		end)

		it("leaves other tooltips that show units alone", function()
			killedBy(3)
			wow.state().units.mouseover = GRIMBASH
			local other = { unit = "mouseover", lines = {} }
			function other:AddLine(text)
				self.lines[#self.lines + 1] = text
			end
			ns.Grudges.TooltipLines(other)
			assert.are.same({}, other.lines)
		end)

		it("shows nothing for someone you don't hold a grudge against", function()
			killedBy(1)
			assert.are.same({}, hover(KORGA))
		end)
	end)
end)
