local wow = require("spec.support.wow")

local ME = "Player-4395-0000000A"
local GRIMBASH = "Player-4395-0B1C2D3E"

describe("Ear Pouch", function()
	local ns, Pouch

	before_each(function()
		wow.reset()
		wow.addPlayer(GRIMBASH, {
			name = "Grimbash",
			realm = "Ironhide",
			class = "Warrior",
			race = "Orc",
			level = 60,
		})
		ns = wow.loadAddon("EarCollector.toc")
		Pouch = ns.Pouch
	end)

	-- Collect `n` ears, oldest first, one minute apart.
	local function collect(n, fields)
		for i = 1, n do
			local kill =
				{ guid = ("Player-1-%08X"):format(i), name = "Victim" .. i, race = "Orc", level = 60, by = "you" }
			for k, v in pairs(fields or {}) do
				kill[k] = v
			end
			ns.Ears.Record(ns.db, kill, 1795290000 + i * 60)
		end
	end

	local function frame()
		return _G.EarCollectorPouch
	end

	describe("window", function()
		it("opens and closes with /ears", function()
			wow.slash("/ears")
			assert.is_true(Pouch.IsShown())
			assert.are.equal("Ear Pouch", frame().TitleText:GetText())
			wow.slash("/ears")
			assert.is_false(Pouch.IsShown())
		end)

		it("shows an ear's tooltip while you hover its link in chat", function()
			collect(1)
			local ear = ns.db.ears[1]
			wow.hoverLink(("addon:EarCollector:ear:%s:%d"):format(ear.guid, ear.at))
			assert.is_true(_G.GameTooltip:IsShown())
			assert.are.equal("Victim1's Ear", _G.GameTooltip.lines[1])
			wow.hoverLink(nil)
			assert.is_false(_G.GameTooltip:IsShown())
		end)

		it("leaves other links' tooltips alone", function()
			_G.GameTooltip:Show() -- Blizzard's tooltip for an item link
			wow.hoverLink("item:12345")
			wow.hoverLink(nil)
			assert.is_true(_G.GameTooltip:IsShown())
		end)

		it("says once per account how to open the pouch", function()
			wow.fireEvent("PLAYER_LOGIN")
			assert.are.equal(1, wow.printed("Your Ear Pouch opens with your bags"))
			wow.fireEvent("PLAYER_LOGIN")
			assert.are.equal(1, wow.printed("Your Ear Pouch opens with your bags"))
		end)

		it("sounds like a bag opening and closing, and turns pages like the spellbook", function()
			local function ids()
				local list = {}
				for i, sound in ipairs(wow.state().sounds) do
					list[i] = sound.id
				end
				return list
			end
			collect(Pouch.PER_PAGE + 1)
			wow.slash("/ears")
			Pouch.Widgets().next:Click()
			wow.slash("/ears")
			assert.are.same({ 862, 836, 863 }, ids())
		end)

		it("stays quiet when your bags open and close it, since they have their own sound", function()
			_G.ToggleAllBags()
			_G.ToggleAllBags()
			assert.are.same({}, wow.state().sounds)
		end)

		it("sits at the layer of Blizzard's panels", function()
			wow.slash("/ears")
			assert.are.equal("MEDIUM", frame().strata)
		end)

		it("starts the grid below the count line", function()
			wow.slash("/ears")
			local _, _, _, _, y = ns.EarsTab.Widgets().slots[1]:GetPoint(1)
			assert.are.equal(-Pouch.GRID_TOP, y)
			local _, _, _, _, countY = ns.EarsTab.Widgets().count:GetPoint(1)
			assert.is_true(countY - 12 >= y) -- a line of small text clears the first row
		end)

		it("says how to get the first ear when empty", function()
			wow.slash("/ears")
			local w, ears = Pouch.Widgets(), ns.EarsTab.Widgets()
			assert.is_true(ears.empty:IsShown())
			assert.are.equal("No ears yet", ears.emptyHeading:GetText())
			assert.is_true(ears.empty:GetFrameLevel() > ears.slots[1]:GetFrameLevel()) -- drawn over the slots
			assert.are.equal("0 ears", ears.count:GetText())
			assert.are.equal("Page 1 / 1", w.page:GetText())
			assert.is_false(w.prev:IsEnabled())
			assert.is_false(w.next:IsEnabled())
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
			assert.is_false(ears.empty:IsShown())
			assert.are.equal("1 ear", ears.count:GetText())
		end)

		it("shows ears newest first, with race icon, grade border and camp count", function()
			collect(2)
			ns.db.ears[1].quality = 3
			ns.db.ears[2].camped = 2
			wow.slash("/ears")
			local slots = ns.EarsTab.Widgets().slots
			assert.are.equal("Victim2", slots[1].ear.name)
			assert.are.equal("Victim1", slots[2].ear.name)
			assert.is_nil(slots[3].ear)
			assert.are.equal(ns.Art.EarTexture("Orc", slots[1].ear.guid), slots[1].icon.texture)
			assert.matches("\\Ears\\orc%-[1-4]$", slots[1].icon.texture)
			assert.are.equal("3", slots[1].count:GetText())
			local rare = ns.QUALITY[3]
			assert.is_true(slots[2].border:IsShown())
			assert.are.same({ rare.r, rare.g, rare.b }, slots[2].border.vertexColor)
		end)

		it("frames Uncommon and better in their grade colour, as bags do, and not Common or Poor", function()
			collect(3)
			ns.db.ears[1].quality, ns.db.ears[2].quality, ns.db.ears[3].quality = 0, 1, 2
			wow.slash("/ears")
			local slots = ns.EarsTab.Widgets().slots
			assert.is_true(slots[1].border:IsShown()) -- newest first: the Uncommon ear
			assert.is_false(slots[2].border:IsShown())
			assert.is_false(slots[3].border:IsShown())
			assert.is_false(slots[4].border:IsShown()) -- an empty slot
		end)

		it("marks each ear with its class colour", function()
			collect(1)
			ns.db.ears[1].class = "MAGE"
			wow.slash("/ears")
			local dot = ns.EarsTab.Widgets().slots[1].dot
			assert.is_true(dot:IsShown())
			assert.are.same({ ns.Chat.RGB("ff3fc7eb") }, { unpack(dot.color, 1, 3) })
			ns.db.ears[1].class = nil
			ns.Pouch.Refresh()
			assert.is_false(dot:IsShown())
		end)

		it("makes new ears glow until hovered, or until the pouch closes", function()
			collect(2) -- before this session's start: not new
			wow.state().now = wow.state().now + 3600 * 24
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
			wow.slash("/ears")
			local slots = ns.EarsTab.Widgets().slots
			assert.is_true(slots[1].new:IsShown()) -- Grimbash, newest
			assert.is_false(slots[2].new:IsShown())
			slots[1]:Enter()
			assert.is_false(slots[1].new:IsShown())
			wow.state().now = wow.state().now + 60
			wow.addPlayer("Player-4395-00000040", { name = "Late", class = "Mage", race = "Orc", level = 60 })
			wow.fireEvent("PARTY_KILL", ME, "Player-4395-00000040")
			assert.is_true(slots[1].new:IsShown())
			assert.is_false(slots[2].new:IsShown()) -- Grimbash stays seen after the refresh
			wow.slash("/ears") -- close
			wow.slash("/ears") -- and open again
			assert.is_false(slots[1].new:IsShown())
		end)

		it("uses the generic ear for an unknown race, and greys out Poor ears", function()
			collect(1, { race = "Pandaren" })
			ns.db.ears[1].quality = 0
			wow.slash("/ears")
			local slot = ns.EarsTab.Widgets().slots[1]
			assert.are.equal("Interface\\AddOns\\EarCollector\\Media\\Ears\\generic", slot.icon.texture)
			assert.is_true(slot.icon.desaturated)
			assert.are.same({ 0.6, 0.6, 0.6 }, slot.icon.vertexColor) -- dimmed, not just grey
		end)

		it("pages through more ears than fit", function()
			collect(Pouch.PER_PAGE + 3)
			wow.slash("/ears")
			assert.are.same({ 1, 2 }, { Pouch.GetPage() })
			assert.is_true(Pouch.Widgets().next:IsEnabled())
			Pouch.Widgets().next:Click()
			assert.are.equal("Victim3", ns.EarsTab.Widgets().slots[1].ear.name)
			assert.is_nil(ns.EarsTab.Widgets().slots[4].ear)
			Pouch.SetPage(99) -- clamped
			assert.are.equal(2, (Pouch.GetPage()))
			frame():Wheel(1) -- scroll up: previous page
			assert.are.equal(1, (Pouch.GetPage()))
		end)

		it("adds a new ear while open", function()
			wow.slash("/ears")
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
			assert.are.equal("Grimbash", ns.EarsTab.Widgets().slots[1].ear.name)
		end)

		it("remembers where you dragged it", function()
			wow.slash("/ears")
			frame():Drag()
			assert.are.same({ point = "CENTER", relativePoint = "CENTER", x = 100, y = -50 }, ns.db.ui.pouch)
			local saved = ns.db
			wow.reset()
			wow.loadAddon("EarCollector.toc", { EarCollectorDB = saved })
			wow.slash("/ears")
			assert.are.same({ "CENTER", _G.UIParent, "CENTER", 100, -50 }, { frame():GetPoint(1) })
		end)

		it("ignores a damaged saved position", function()
			wow.reset()
			ns = wow.loadAddon("EarCollector.toc", { EarCollectorDB = { ui = { pouch = { point = 5 } } } })
			wow.slash("/ears")
			assert.are.equal("RIGHT", (frame():GetPoint(1)))
			assert.are.equal(0, #ns.db.errors)
		end)
	end)

	describe("tooltip", function()
		it("describes the ear", function()
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
			local lines = {}
			for _, line in ipairs(ns.EarsTab.TooltipLines(ns.db.ears[1])) do
				lines[#lines + 1] = line.text or (line.left .. " | " .. line.right)
			end
			assert.are.same({
				"Grimbash's Ear",
				"Trophy | Uncommon",
				"Grimbash Ironhide",
				"Level 60 |A:raceicon-orc-male:14:14|a Orc |cffc69b6dWarrior|r",
				" ",
				"Why it's |cff1eff00Uncommon|r",
				"No record of the fight",
				" ",
				"Taken at Tarren Mill",
				"Hillsbrad Foothills",
				"Killing blow: you",
				"You were level 60",
				os.date("%b %d, %Y %H:%M", ns.db.ears[1].at),
			}, lines)
		end)

		it("lists what counted, with a sign and squares for each, and closes with the story", function()
			wow.state().players[GRIMBASH].level = 63 -- orange to you: raised a grade
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
			local ear = ns.db.ears[1]
			ear.fight.read = true -- as if the meter had a record, so no "No record" line
			local lines = ns.EarsTab.TooltipLines(ear)
			local why
			for i, line in ipairs(lines) do
				why = why or (line.text == "Why it's |cff0070ddRare|r" and i)
			end
			local reason = lines[why + 1]
			assert.are.equal("+ Three levels above you", reason.left)
			assert.are.same({ 0.1, 1, 0.1 }, { reason.lr, reason.lg, reason.lb })
			local square = "|TInterface\\Buttons\\WHITE8X8:7:7:0:0:8:8:0:8:0:8:%s|t"
			assert.are.equal(
				table.concat({ square:format("26:255:26"), square:format("26:255:26"), square:format("74:77:84") }, " "),
				reason.right
			)
			assert.are.equal('"They outlevelled me, and it didn\'t save them."', lines[#lines].text)
		end)

		it("names group killers, assists, camping and unknown levels", function()
			collect(1, { by = "group", killer = "Brakka", level = false })
			ns.db.ears[1].level = nil
			ns.db.ears[1].camped = 1
			local text = {}
			for _, line in ipairs(ns.EarsTab.TooltipLines(ns.db.ears[1])) do
				text[#text + 1] = line.text or line.left
			end
			text = table.concat(text, "\n")
			assert.matches("Level %?%? |A:raceicon%-orc%-male:14:14|a Orc", text)
			assert.matches("Killing blow: Brakka %(your group%)", text)
			assert.matches("Camped: 1 more kill within 10 minutes", text)

			collect(1, { by = "assist", guid = "Player-1-ASSIST" })
			local assist = ns.EarsTab.TooltipLines(ns.db.ears[#ns.db.ears])
			local found = false
			for _, line in ipairs(assist) do
				found = found or line.text == "Assist: killing blow from outside your group"
			end
			assert.is_true(found)
		end)

		it("shows on hover and hides when the mouse leaves", function()
			collect(1)
			wow.slash("/ears")
			local slot = ns.EarsTab.Widgets().slots[1]
			slot:Enter()
			assert.is_true(_G.GameTooltip:IsShown())
			assert.are.equal(slot, _G.GameTooltip.owner)
			assert.are.equal("Victim1's Ear", _G.GameTooltip.lines[1])
			slot:Leave()
			assert.is_false(_G.GameTooltip:IsShown())
		end)

		it("contains an error from a damaged ear", function()
			collect(1)
			wow.slash("/ears")
			ns.EarsTab.Widgets().slots[1].ear = { name = "Broken", at = "not a time" }
			assert.has_no.errors(function()
				ns.EarsTab.Widgets().slots[1]:Enter()
			end)
			assert.are.equal("pouch tooltip", ns.db.errors[1].where)
		end)
	end)

	describe("opening with your bags", function()
		it("closes a pouch the bags opened when the last bag closes with its own button", function()
			_G.ToggleAllBags()
			assert.is_true(Pouch.IsShown())
			_G.CloseBag(0)
			assert.is_false(Pouch.IsShown())
		end)

		it("doesn't open for a merchant, bank, mailbox or trade window", function()
			local merchant = _G.CreateFrame("Frame")
			_G.OpenAllBags(merchant)
			assert.is_true(wow.state().bagsOpen)
			assert.is_false(Pouch.IsShown())
			_G.CloseAllBags()
			_G.OpenAllBags()
			assert.is_true(Pouch.IsShown())
		end)

		it("stays open when the bags close after you clicked an ear link", function()
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
			_G.ToggleAllBags() -- the bags open the pouch
			ns.EarsTab.Focus(ns.db.ears[1].guid, ns.db.ears[1].at) -- then you click an ear link
			_G.CloseAllBags()
			assert.is_true(Pouch.IsShown())
		end)

		it("opens and closes with the bags by default", function()
			_G.ToggleAllBags()
			assert.is_true(Pouch.IsShown())
			_G.ToggleAllBags()
			assert.is_false(Pouch.IsShown())
			_G.OpenBackpack()
			assert.is_true(Pouch.IsShown())
			_G.CloseAllBags()
			assert.is_false(Pouch.IsShown())
		end)

		it("stays open when you opened it yourself", function()
			wow.slash("/ears")
			_G.OpenAllBags()
			_G.CloseAllBags()
			assert.is_true(Pouch.IsShown())
		end)

		it("can be turned off with /ears bags off", function()
			wow.slash("/ears bags off")
			assert.is_false(ns.db.settings.openWithBags)
			_G.ToggleAllBags()
			assert.is_false(Pouch.IsShown())
			wow.slash("/ears bags on")
			_G.CloseAllBags()
			_G.OpenAllBags()
			assert.is_true(Pouch.IsShown())
		end)

		it("leaves Blizzard's bag functions working", function()
			_G.ToggleAllBags()
			assert.is_true(wow.state().bagsOpen)
		end)
	end)

	describe("minimap addon drawer", function()
		it("names functions in the TOC that the addon defines", function()
			local file = assert(io.open("EarCollector.toc"))
			local toc = file:read("*a")
			file:close()
			for _, key in ipairs({
				"AddonCompartmentFunc",
				"AddonCompartmentFuncOnEnter",
				"AddonCompartmentFuncOnLeave",
			}) do
				local global = toc:match("## " .. key .. ": (%S+)")
				assert.is_truthy(global, key)
				assert.are.equal("function", type(_G[global]), global)
			end
		end)

		it("toggles the pouch on click and shows totals on hover", function()
			collect(3)
			ns.db.ears[2].by = "assist"
			_G.EarCollector_OnAddonCompartmentClick("EarCollector", "LeftButton")
			assert.is_true(Pouch.IsShown())
			_G.EarCollector_OnAddonCompartmentClick("EarCollector", "LeftButton")
			assert.is_false(Pouch.IsShown())

			local button = _G.CreateFrame("Button")
			_G.EarCollector_OnAddonCompartmentEnter("EarCollector", button)
			assert.are.equal(button, _G.GameTooltip.owner)
			assert.are.equal("3 ears (1 assist)", _G.GameTooltip.lines[2])
			_G.EarCollector_OnAddonCompartmentLeave("EarCollector", button)
			assert.is_false(_G.GameTooltip:IsShown())
		end)
	end)

	describe("key binding", function()
		it("toggles the pouch, with a name in Key Bindings", function()
			wow.pressBinding("EARCOLLECTOR_TOGGLE")
			assert.is_true(Pouch.IsShown())
			wow.pressBinding("EARCOLLECTOR_TOGGLE")
			assert.is_false(Pouch.IsShown())
			assert.are.equal("Ear Collector", _G.BINDING_HEADER_EARCOLLECTOR)
			assert.are.equal("Toggle Ear Pouch", _G.BINDING_NAME_EARCOLLECTOR_TOGGLE)
		end)
	end)

	describe("Escape", function()
		it("closes the pouch without opening the game menu", function()
			wow.slash("/ears")
			wow.pressEscape()
			assert.is_false(Pouch.IsShown())
			assert.is_false(wow.state().gameMenuShown)
			wow.pressEscape() -- nothing left to close
			assert.is_true(wow.state().gameMenuShown)
		end)

		it("closes the pouch along with the bags that opened it", function()
			_G.ToggleAllBags()
			assert.is_true(Pouch.IsShown())
			wow.pressEscape()
			assert.is_false(Pouch.IsShown())
			assert.is_false(wow.state().bagsOpen)
			assert.is_false(wow.state().gameMenuShown)
		end)

		it("clears a focused ear, like the close button", function()
			collect(1)
			ns.EarsTab.Focus(ns.db.ears[1].guid, ns.db.ears[1].at)
			wow.pressEscape()
			assert.is_false(_G.GameTooltip:IsShown())
			wow.slash("/ears")
			assert.is_false(ns.EarsTab.Widgets().slots[1].highlightLocked)
		end)

		it("works in combat, from every way of opening the pouch", function()
			collect(1)
			wow.state().inCombat = true
			local opens = {
				function()
					wow.slash("/ears")
				end,
				function()
					_G.ToggleAllBags()
				end,
				function()
					wow.pressBinding("EARCOLLECTOR_TOGGLE")
				end,
				function()
					_G.EarCollector_OnAddonCompartmentClick("EarCollector", "LeftButton")
				end,
				function()
					ns.EarsTab.Focus(ns.db.ears[1].guid, ns.db.ears[1].at)
				end,
			}
			for i, open in ipairs(opens) do
				open()
				assert.is_true(Pouch.IsShown(), "opened by way " .. i)
				wow.pressEscape()
				assert.is_false(Pouch.IsShown(), "closed after way " .. i)
				assert.is_false(wow.state().gameMenuShown, "no game menu after way " .. i)
			end
			assert.are.same({}, ns.db.errors)
		end)

		it("adds its name to Blizzard's list once, keeping the entries already there", function()
			local before = { unpack(_G.UISpecialFrames) }
			for _ = 1, 3 do
				wow.slash("/ears")
				wow.slash("/ears")
			end
			local expected = { unpack(before) }
			expected[#expected + 1] = "EarCollectorPouch"
			assert.are.same(expected, _G.UISpecialFrames)
		end)

		it("leaves the list alone until the pouch is first opened", function()
			assert.is_falsy(table.concat(_G.UISpecialFrames, " "):find("EarCollector"))
		end)

		it("still opens on a client without the list", function()
			_G.UISpecialFrames = nil
			assert.has_no.errors(function()
				wow.slash("/ears")
			end)
			assert.is_true(Pouch.IsShown())
			assert.is_nil(_G.UISpecialFrames)
			assert.are.same({}, ns.db.errors)
		end)
	end)

	describe("ear links in chat", function()
		local function linkIn(line)
			return line:match("|H(addon:[^|]+)|h")
		end

		it("makes the ear name in the chat line a link", function()
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
			local link = linkIn(wow.state().printed[1])
			assert.are.equal(("addon:EarCollector:ear:%s:%d"):format(GRIMBASH, ns.db.ears[1].at), link)
		end)

		it("opens the pouch on the clicked ear, on its page, with its tooltip", function()
			collect(Pouch.PER_PAGE + 5)
			local oldest = ns.db.ears[1]
			wow.clickLink(("addon:EarCollector:ear:%s:%d"):format(oldest.guid, oldest.at))
			assert.is_true(Pouch.IsShown())
			assert.are.equal(2, (Pouch.GetPage()))
			local slot = ns.EarsTab.Widgets().slots[5] -- 45 ears: the oldest is 5th on page 2
			assert.are.equal(oldest, slot.ear)
			assert.is_true(slot.highlightLocked)
			assert.are.equal(slot, _G.GameTooltip.owner)
		end)

		it("says so when the ear is gone, and ignores other addons' links", function()
			wow.clickLink("addon:EarCollector:ear:Player-1-GONE:123")
			assert.matches("no longer in your pouch", wow.state().printed[1])
			wow.clickLink("addon:SomeOtherAddon:thing")
			wow.clickLink("item:12345")
			assert.are.equal(1, #wow.state().printed)
			assert.is_false(Pouch.IsShown())
		end)
	end)

	describe("/ears stats", function()
		it("prints a summary for /ears stats", function()
			collect(2, { by = "assist" })
			wow.slash("/ears stats")
			assert.matches("2 ears %(2 assists%) collected, 2 in the last 7 days%.", wow.state().printed[1])
		end)
	end)
end)
