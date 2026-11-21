local wow = require("spec.support.wow")

local ME = "Player-4395-0000000A"
local NOW = 1795293660

describe("pouch tabs", function()
	local ns, Pouch

	before_each(function()
		wow.reset()
		ns = wow.loadAddon("EarCollector.toc")
		Pouch = ns.Pouch
	end)

	-- Ears from `specs`: { guid=, name=, class=, zone=, quality=, camped=, by= }, oldest
	-- first, an hour apart (outside the repeat-kill window, so each is its own ear).
	local function at(i)
		return NOW - 100000 + i * 3600
	end
	local function collect(specs)
		for i, spec in ipairs(specs) do
			local kill = {
				guid = spec.guid or ("Player-1-%08X"):format(i),
				name = spec.name or ("Victim" .. i),
				class = spec.class,
				race = "Orc",
				level = 60,
				zone = spec.zone,
				by = spec.by or "you",
			}
			ns.Ears.Record(ns.db, kill, at(i))
			if spec.quality then
				ns.db.ears[#ns.db.ears].quality = spec.quality
			end
			if spec.camped then
				ns.db.ears[#ns.db.ears].camped = spec.camped
			end
		end
	end

	local function tab(title)
		for _, t in ipairs(_G.EarCollectorPouch.Tabs) do
			if t:GetText() == title then
				return t
			end
		end
		error("no tab " .. title)
	end

	describe("the tab strip", function()
		it("has Ears, Ledger and Rivals, as Blizzard tabs under the window", function()
			wow.slash("/ears")
			assert.are.same({ "Ears", "Ledger", "Rivals" }, Pouch.TabTitles())
			local frame = _G.EarCollectorPouch
			assert.are.equal(3, frame.numTabs)
			assert.are.equal(1, frame.selectedTab)
			assert.are.equal("Ears", Pouch.ActiveTab())
			assert.are.same({ "TOPLEFT", frame, "BOTTOMLEFT", 11, 2 }, { frame.Tabs[1]:GetPoint(1) })
		end)

		it("switches panels on click, with Blizzard's tab sound", function()
			wow.slash("/ears")
			tab("Ledger"):Click()
			assert.are.equal("Ledger", Pouch.ActiveTab())
			assert.are.equal(2, _G.EarCollectorPouch.selectedTab)
			assert.is_false(Pouch.Slots()[1]:IsShown() and Pouch.Slots()[1].parent:IsShown())
			assert.are.same({ id = 841, channel = "SFX" }, wow.state().sounds[1])
			tab("Ears"):Click()
			assert.is_true(Pouch.Slots()[1].parent:IsShown())
		end)

		it("keeps the chosen tab when the pouch reopens", function()
			wow.slash("/ears")
			tab("Rivals"):Click()
			wow.slash("/ears")
			wow.slash("/ears")
			assert.are.equal("Rivals", Pouch.ActiveTab())
		end)

		it("goes back to Ears to show a clicked ear", function()
			collect({ {} })
			wow.slash("/ears")
			tab("Ledger"):Click()
			Pouch.FocusEar(ns.db.ears[1].guid, ns.db.ears[1].at)
			assert.are.equal("Ears", Pouch.ActiveTab())
			assert.is_true(Pouch.Slots()[1].highlightLocked)
		end)

		it("hides the page buttons on the Ledger, which has one page", function()
			wow.slash("/ears")
			tab("Ledger"):Click()
			local w = Pouch.Widgets()
			assert.is_false(w.prev:IsShown())
			assert.is_false(w.page:IsShown())
			assert.are.same({ 1, 1 }, { Pouch.GetPage() })
			tab("Ears"):Click()
			assert.is_true(w.prev:IsShown())
		end)

		it("doesn't take new tabs once the window is built", function()
			wow.slash("/ears")
			assert.is_false(Pouch.AddTab({ title = "Late", build = function() end, refresh = function() end }))
			assert.are.equal(3, #Pouch.TabTitles())
		end)
	end)

	describe("Ledger", function()
		it("shows your deaths even before your first ear", function()
			table.insert(ns.db.deaths, { guid = "Player-4395-0B1C2D3E", name = "Grimbash", at = NOW })
			wow.slash("/ears")
			Pouch.SelectTab("Ledger")
			local w = ns.LedgerTab.Widgets()
			assert.is_false(w.empty:IsShown())
			assert.are.equal("1", w.stats[4]:GetText())
		end)

		it("shows totals, a grade bar, classes and top zones", function()
			collect({
				{ guid = "A", class = "ROGUE", zone = "Hillsbrad Foothills", quality = 3 },
				{ guid = "A", class = "ROGUE", zone = "Hillsbrad Foothills", by = "assist" },
				{ guid = "B", class = "MAGE", zone = "Stranglethorn Vale", quality = 0 },
				{ guid = "C", class = "ROGUE", zone = "Hillsbrad Foothills" },
			})
			wow.slash("/ears")
			tab("Ledger"):Click()
			local w = ns.LedgerTab.Widgets()
			local stats = {}
			for i, fs in ipairs(w.stats) do
				stats[i] = fs:GetText()
			end
			assert.are.same({ "4", "4", "1", "0" }, stats) -- ears, last 7 days, assists, ears lost

			local inner = Pouch.WIDTH - 2 * Pouch.PAD
			assert.are.equal(inner / 4, w.grades[0]:GetWidth())
			assert.are.equal(inner / 2, w.grades[2]:GetWidth())
			assert.is_false(w.grades[1]:IsShown())
			local _, _, _, x = w.grades[2]:GetPoint(1)
			assert.are.equal(Pouch.PAD + inner / 4, x) -- right after Poor
			assert.matches("Poor|r 1", w.legend:GetText())
			assert.is_nil(w.legend:GetText():find("Common"))

			assert.are.equal("|cfffff468Rogue|r", w.classes[1].name:GetText())
			assert.are.equal("3", w.classes[1].count:GetText())
			assert.are.equal("|cff3fc7ebMage|r", w.classes[2].name:GetText())
			assert.is_true(w.classes[1].bar:GetWidth() > w.classes[2].bar:GetWidth())
			assert.are.equal("", w.classes[3].name:GetText())
			assert.is_false(w.classes[3].bar:IsShown())

			assert.are.equal("Hillsbrad Foothills", w.zones[1].name:GetText())
			assert.are.equal("3", w.zones[1].count:GetText())
			assert.are.equal("", w.zones[3].name:GetText())
		end)

		it("says it's empty before your first ear, and fills in when one arrives", function()
			wow.addPlayer("Player-4395-0B1C2D3E", { name = "Grimbash", class = "Warrior", race = "Orc", level = 60 })
			wow.slash("/ears")
			tab("Ledger"):Click()
			local w = ns.LedgerTab.Widgets()
			assert.is_true(w.empty:IsShown())
			assert.is_false(w.content:IsShown())
			wow.fireEvent("PARTY_KILL", ME, "Player-4395-0B1C2D3E")
			assert.is_false(w.empty:IsShown())
			assert.are.equal("1", w.stats[1]:GetText())
		end)

		it("names unknown classes in grey", function()
			assert.are.same({ "Unknown", "ff9d9d9d" }, { ns.LedgerTab.ClassStyle({ class = "UNKNOWN" }) })
			assert.are.same({ "Paladin", "fff48cba" }, { ns.LedgerTab.ClassStyle({ class = "PALADIN" }) })
			assert.are.same({ "DEMONHUNTER", "ff9d9d9d" }, { ns.LedgerTab.ClassStyle({ class = "DEMONHUNTER" }) })
		end)
	end)

	describe("Rivals", function()
		it("lists players by kills, with the last kill date and a Prey mark", function()
			collect({
				{ guid = "A", name = "Velaria", class = "ROGUE", camped = 2 },
				{ guid = "B", name = "Grimbash", class = "WARRIOR" },
			})
			wow.slash("/ears")
			tab("Rivals"):Click()
			local rows = ns.RivalsTab.Rows()
			assert.are.equal("|cfffff468Velaria|r", rows[1].name:GetText())
			assert.are.equal("3", rows[1].kills:GetText())
			assert.are.equal("Prey", rows[1].mark:GetText())
			assert.are.equal(os.date("%b %d", at(1)), rows[1].last:GetText())
			assert.are.equal("|cffc69b6dGrimbash|r", rows[2].name:GetText())
			assert.are.equal("", rows[2].mark:GetText())
			assert.is_false(rows[3]:IsShown())
		end)

		it("pages ten rivals at a time", function()
			local specs = {}
			for i = 1, 23 do
				specs[i] = { guid = ("G%02d"):format(i) }
			end
			collect(specs)
			wow.slash("/ears")
			tab("Rivals"):Click()
			assert.are.same({ 1, 3 }, { Pouch.GetPage() })
			Pouch.Widgets().next:Click()
			Pouch.Widgets().next:Click()
			assert.are.same({ 3, 3 }, { Pouch.GetPage() })
			assert.is_true(ns.RivalsTab.Rows()[3]:IsShown())
			assert.is_false(ns.RivalsTab.Rows()[4]:IsShown())
			_G.EarCollectorPouch:Wheel(1)
			assert.are.same({ 2, 3 }, { Pouch.GetPage() })
			Pouch.SetPage(99)
			assert.are.same({ 3, 3 }, { Pouch.GetPage() })
			Pouch.SetPage(-4)
			assert.are.same({ 1, 3 }, { Pouch.GetPage() })
			tab("Ears"):Click()
			assert.are.same({ 1, 1 }, { Pouch.GetPage() }) -- the Ears tab kept its own page
		end)

		it("shows details on hover and opens their latest ear on click", function()
			collect({
				{ guid = "A", name = "Velaria", class = "ROGUE" },
				{ guid = "A", name = "Velaria", class = "ROGUE" },
			})
			ns.db.ears[2].surname = "Duskwhisper"
			ns.db.ears[2].zone, ns.db.ears[2].subzone = "Hillsbrad Foothills", "Tarren Mill"
			wow.slash("/ears")
			tab("Rivals"):Click()
			local row = ns.RivalsTab.Rows()[1]
			row:Enter()
			local lines = _G.GameTooltip.lines
			assert.are.equal("|cfffff468Velaria Duskwhisper|r", lines[1])
			assert.matches("^Level 60", lines[2])
			assert.are.equal("You killed them 2 times (2 ears)", lines[4])
			assert.matches("Tarren Mill$", lines[6])
			assert.are.equal("Click to see their latest ear.", lines[#lines])
			row:Click()
			assert.are.equal("Ears", Pouch.ActiveTab())
			assert.are.equal(ns.db.ears[2], Pouch.Slots()[1].ear)
			assert.is_true(Pouch.Slots()[1].highlightLocked)
		end)

		it("says so when there are no rivals", function()
			wow.slash("/ears")
			tab("Rivals"):Click()
			assert.is_false(ns.RivalsTab.Rows()[1]:IsShown())
			assert.is_true(ns.RivalsTab.Widgets().empty:IsShown())
			assert.is_false(ns.RivalsTab.Widgets().headings:IsShown())
		end)
	end)

	describe("errors", function()
		it("leave out a tab whose build fails, and the pouch still opens", function()
			local refreshed = false
			Pouch.AddTab({
				title = "Broken",
				build = function()
					error("bad build")
				end,
				refresh = function()
					refreshed = true
				end,
			})
			collect({ {} })
			assert.has_no.errors(function()
				wow.slash("/ears")
			end)
			assert.is_true(Pouch.IsShown())
			assert.are.equal("pouch Broken", ns.db.errors[1].where)
			tab("Broken"):Click()
			assert.is_false(refreshed)
			assert.are.equal(1, #ns.db.errors)
			tab("Ears"):Click()
			assert.are.equal("Victim1", Pouch.Slots()[1].ear.name)
		end)

		it("keep a failing tab from breaking the pouch", function()
			ns.Ledger.Summarize = function()
				error("boom")
			end
			collect({ {} })
			wow.slash("/ears")
			assert.has_no.errors(function()
				tab("Ledger"):Click()
			end)
			assert.are.equal("pouch Ledger", ns.db.errors[1].where)
			tab("Ears"):Click()
			assert.are.equal("Victim1", Pouch.Slots()[1].ear.name)
		end)
	end)
end)
