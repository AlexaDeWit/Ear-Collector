-- Fixes from the adversarial review before v1.0: each spec reproduces a
-- failure the reviewer demonstrated.
local wow = require("spec.support.wow")

local ME = "Player-4395-0000000A"
local GRIMBASH = "Player-4395-0B1C2D3E"
local VELARIA = "Player-4395-0C1D2E3F"

describe("review fixes", function()
	local ns

	before_each(function()
		wow.reset()
		wow.addPlayer(GRIMBASH, { name = "Grimbash", class = "Warrior", race = "Orc", level = 60 })
		wow.addPlayer(VELARIA, { name = "Velaria", class = "Rogue", race = "Troll", level = 60 })
		for i = 1, 6 do
			wow.addPlayer(("Player-1-%08X"):format(i), { name = "V" .. i, class = "Mage", race = "Orc", level = 60 })
		end
		ns = wow.loadAddon("EarCollector.toc")
	end)

	describe("a UI error never switches off kill detection", function()
		it("keeps collecting when the pouch fails to build", function()
			_G.PanelTemplates_SetNumTabs = function()
				error("template differs")
			end
			wow.slash("/ears")
			wow.slash("/ears")
			for i = 1, 4 do
				wow.fireEvent("PARTY_KILL", ME, ("Player-1-%08X"):format(i))
			end
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
			for i = 1, 4 do
				wow.fireEvent("PARTY_KILL", ME, ("Player-1-%08X"):format(i))
			end
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
			for i = 1, 4 do
				wow.fireEvent("PARTY_KILL", ME, ("Player-1-%08X"):format(i))
			end
			assert.are.equal(4, #ns.db.ears)
			assert.is_false(ns.Errors.IsDisabled("PARTY_KILL handler 1"))
		end)
	end)

	describe("slash commands", function()
		it("switch off only the failing command, and /ears errors always works", function()
			ns.Pouch.Toggle = function()
				error("pouch bug")
			end
			for _ = 1, 3 do
				wow.slash("/ears")
			end
			assert.is_true(ns.Errors.IsDisabled("/ears pouch"))
			local before = #wow.state().printed
			wow.slash("/ears errors")
			wow.slash("/ears stats")
			assert.is_true(#wow.state().printed > before + 1)
		end)

		it("list a damaged saved error without failing", function()
			ns.db.errors[1] = { at = "yesterday" }
			ns.db.errors[2] = 5
			local before = #wow.state().printed
			assert.has_no.errors(function()
				wow.slash("/ears errors")
			end)
			assert.matches("%? in nil %(nil%): nil", wow.state().printed[before + 2])
			assert.is_nil(ns.Errors.SessionCounts()["/ears"])
		end)

		it("show at least one ear for /ears recent 0", function()
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
			wow.slash("/ears recent 0")
			assert.matches("Grimbash's Ear", wow.state().printed[#wow.state().printed])
		end)

		it("report hidden and unnamed kills in /ears stats", function()
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
			ns.db.stats.hiddenKills, ns.db.stats.unnamedHonorKills = 2, 3
			wow.slash("/ears stats")
			local text = table.concat(wow.state().printed, "\n")
			assert.matches("2 kill%(s%) the game hid", text)
			assert.matches("3 honorable kill%(s%) not tied", text)
		end)
	end)

	describe("bags", function()
		it("close a pouch they opened when the last bag closes with its own button", function()
			_G.ToggleAllBags()
			assert.is_true(ns.Pouch.IsShown())
			_G.CloseBag(0)
			assert.is_false(ns.Pouch.IsShown())
		end)

		it("don't open the pouch for a merchant, bank, mailbox or trade window", function()
			local merchant = _G.CreateFrame("Frame")
			_G.OpenAllBags(merchant)
			assert.is_true(wow.state().bagsOpen)
			assert.is_false(ns.Pouch.IsShown())
			_G.CloseAllBags()
			_G.OpenAllBags()
			assert.is_true(ns.Pouch.IsShown())
		end)

		it("leave a pouch opened from a chat link open when the bags close", function()
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
			_G.ToggleAllBags() -- the bags open the pouch
			ns.Pouch.FocusEar(ns.db.ears[1].guid, ns.db.ears[1].at) -- then you click an ear link
			_G.CloseAllBags()
			assert.is_true(ns.Pouch.IsShown())
		end)
	end)

	describe("options", function()
		it("wait for the Combat addon restriction to lift, not only lockdown", function()
			wow.state().restrictions.Combat = true
			wow.slash("/ears options")
			assert.is_nil(wow.state().settingsOpenedTo)
			assert.matches("during combat", wow.state().printed[#wow.state().printed])
		end)
	end)

	describe("Ledger", function()
		it("shows your deaths even before your first ear", function()
			table.insert(ns.db.deaths, { guid = GRIMBASH, name = "Grimbash", at = 100 })
			wow.slash("/ears")
			ns.Pouch.SelectTab("Ledger")
			local w = ns.LedgerTab.Widgets()
			assert.is_false(w.empty:IsShown())
			assert.are.equal("1", w.stats[4]:GetText())
		end)
	end)

	describe("the safety net", function()
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

		it("drops wrong-typed optional fields from saved ears and deaths", function()
			wow.reset()
			ns = wow.loadAddon("EarCollector.toc", {
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
end)
