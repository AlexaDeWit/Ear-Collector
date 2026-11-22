local wow = require("spec.support.wow")

local ME = "Player-4395-0000000A"
local GRIMBASH = "Player-4395-0B1C2D3E"
local VELARIA = "Player-4395-0C1D2E3F"
local OTHER_GRIMBASH = "Player-4395-0D0D0D0D"

describe("deaths and vengeance", function()
	local ns

	before_each(function()
		wow.reset()
		wow.addPlayer(GRIMBASH, { name = "Grimbash", realm = "Ironhide", class = "Warrior", race = "Orc", level = 60 })
		wow.addPlayer(VELARIA, { name = "Velaria", class = "Rogue", race = "Troll", level = 60 })
		wow.addPlayer(OTHER_GRIMBASH, { name = "Grimbash", class = "Mage", race = "Orc", level = 60 })
		ns = wow.loadAddon("EarCollector.toc")
	end)

	-- A recap whose killing blow (first event) came from `sourceName`.
	local function recap(sourceName, extra)
		local first = { sourceName = sourceName, spellName = "Mortal Strike", amount = 1200, timestamp = 100 }
		for k, v in pairs(extra or {}) do
			first[k] = v
		end
		return { first, { sourceName = "Velaria", spellName = "Sinister Strike", amount = 300, timestamp = 98 } }
	end

	-- Die with `units` in view (unit token -> GUID) and `events` in the recap.
	local function die(units, events)
		for unit, guid in pairs(units or {}) do
			wow.state().units[unit] = guid
		end
		wow.state().recap = events
		wow.fireEvent("PLAYER_DEAD")
		wow.advance(ns.DeathWatch.RECAP_DELAY)
	end

	describe("recording who killed you", function()
		it("records an enemy player in view who landed the killing blow", function()
			die({ target = GRIMBASH }, recap("Grimbash"))
			local death = ns.db.deaths[1]
			assert.are.equal(GRIMBASH, death.guid)
			assert.are.equal("Grimbash", death.name)
			assert.are.equal("Ironhide", death.surname)
			assert.are.equal("WARRIOR", death.class)
			assert.are.equal(60, death.level)
			assert.are.equal("Hillsbrad Foothills", death.zone)
			assert.are.equal("Mortal Strike", death.spell)
			assert.are.equal(wow.state().now, death.at)
			assert.matches(
				"Grimbash|r killed you%. Revenge owed: their next ear is worth more%.$",
				wow.state().printed[#wow.state().printed]
			)
		end)

		it("finds the killer by nameplate, focus or mouseover too", function()
			die({ nameplate7 = GRIMBASH }, recap("Grimbash"))
			die({ nameplate7 = "none", focus = VELARIA }, recap("Velaria"))
			assert.are.same({ GRIMBASH, VELARIA }, { ns.db.deaths[1].guid, ns.db.deaths[2].guid })
		end)

		it("matches a recap name with a surname or realm attached", function()
			die({ target = GRIMBASH }, recap("Grimbash Ironhide"))
			die({ target = GRIMBASH }, recap("Grimbash-Ironhide"))
			assert.are.equal(2, #ns.db.deaths)
		end)

		it("doesn't blame a namesake with another surname", function()
			-- A stealthed Grimbash Stonefist kills you while Grimbash Ironhide is your target.
			die({ target = GRIMBASH }, recap("Grimbash Stonefist"))
			assert.are.equal(0, #ns.db.deaths)
		end)

		it("matches a first name when the client gives name and surname as one", function()
			wow.state().players[VELARIA].name = "Velaria Duskwhisper"
			die({ target = VELARIA }, recap("Velaria"))
			assert.are.equal(VELARIA, ns.db.deaths[1].guid)
		end)

		it("uses the recap's player GUID when it has one, even with nobody in view", function()
			wow.slash("/ears debug")
			die({}, recap("Velaria", { sourceGUID = VELARIA }))
			assert.are.equal(VELARIA, ns.db.deaths[1].guid)
			assert.matches("by GUID", ns.db.debugLog[#ns.db.debugLog].decision)
			wow.state().group[GRIMBASH] = true
			die({}, recap("Grimbash", { sourceGUID = GRIMBASH }))
			assert.are.equal(1, #ns.db.deaths)
		end)

		it("falls back to the name when the GUID is a pet's", function()
			die({ target = GRIMBASH }, recap("Grimbash", { sourceGUID = "Pet-0-4395-1-2-3" }))
			assert.are.equal(GRIMBASH, ns.db.deaths[1].guid)
		end)

		it("matches the players in view when you died, not after", function()
			wow.state().units.target = GRIMBASH
			wow.state().recap = recap("Grimbash")
			wow.fireEvent("PLAYER_DEAD")
			wow.state().units.target = nil -- they ran off before the recap was read
			wow.advance(ns.DeathWatch.RECAP_DELAY)
			assert.are.equal(1, #ns.db.deaths)
		end)

		it("ignores an empty recap, a hidden caster, or an NPC", function()
			wow.slash("/ears debug")
			die({ target = GRIMBASH }, nil)
			die({ target = GRIMBASH }, recap("Grimbash", { hideCaster = true }))
			die({ target = GRIMBASH }, recap("Defias Bandit"))
			assert.are.equal(0, #ns.db.deaths)
			assert.are.same({
				"no death recap",
				"recap names no killer",
				"killer isn't an enemy player you saw or damaged (names: Grimbash, Grimbash Ironhide, Grimbash-Ironhide)",
			}, wow.decisions("PLAYER_DEAD"))
		end)

		it("reads every nameplate on screen, however it's numbered", function()
			die({ nameplate57 = GRIMBASH }, recap("Grimbash"))
			assert.are.equal(1, #ns.db.deaths)
		end)

		it("falls back to the numbered nameplates without C_NamePlate", function()
			_G.C_NamePlate = nil
			die({ nameplate57 = VELARIA, ["nameplate" .. ns.DeathWatch.NAMEPLATES] = GRIMBASH }, recap("Grimbash"))
			assert.are.equal(1, #ns.db.deaths)
			local seen = {}
			for _, guid in pairs(ns.DeathWatch.EnemiesInView()) do
				seen[guid] = true
			end
			assert.are.same({ [GRIMBASH] = true }, seen) -- nameplate57 is past the numbered range
		end)

		it("doesn't let a friendly player in view share the killer's name", function()
			wow.state().players[OTHER_GRIMBASH].faction = "Alliance" -- your faction
			die({ target = GRIMBASH, nameplate1 = OTHER_GRIMBASH }, recap("Grimbash"))
			assert.are.equal(1, #ns.db.deaths)
			assert.are.equal(GRIMBASH, ns.db.deaths[1].guid)
		end)

		it("counts anyone in a free-for-all area", function()
			wow.state().freeForAll = true
			wow.state().players[GRIMBASH].faction = "Alliance"
			die({ target = GRIMBASH }, recap("Grimbash"))
			assert.are.equal(1, #ns.db.deaths)
		end)

		it("ignores a name two players in view share", function()
			die({ target = GRIMBASH, nameplate1 = OTHER_GRIMBASH }, recap("Grimbash"))
			assert.are.equal(0, #ns.db.deaths)
		end)

		it("ignores groupmates and yourself", function()
			wow.state().group[VELARIA] = true
			die({ target = VELARIA, mouseover = ME }, recap("Velaria"))
			assert.are.equal(0, #ns.db.deaths)
		end)

		it("doesn't count deaths in battlegrounds or instances", function()
			wow.state().inInstance, wow.state().instanceType = true, "pvp"
			die({ target = GRIMBASH }, recap("Grimbash"))
			assert.are.equal(0, #ns.db.deaths)
			assert.are.equal(0, #wow.state().timers)
		end)

		it("survives secret values in the recap or unit names", function()
			die({ target = GRIMBASH }, { { sourceName = wow.secret() } })
			die({ target = GRIMBASH }, wow.secretTable())
			die({ target = GRIMBASH }, { wow.secretTable() })
			wow.state().players[GRIMBASH].name = wow.secret()
			wow.state().units.target = GRIMBASH
			-- A secret can't be a table key in the client, so it must never be collected.
			assert.are.same({}, ns.DeathWatch.EnemiesInView())
			die({ target = GRIMBASH }, recap("Grimbash"))
			die({ target = wow.secret() }, recap("Grimbash"))
			assert.are.equal(0, #ns.db.deaths)
			assert.are.same({}, ns.db.errors)
		end)

		it("contains an error reading the recap", function()
			_G.C_DeathRecap.GetRecapEvents = function()
				error("boom")
			end
			wow.state().recap = recap("Grimbash")
			assert.has_no.errors(function()
				wow.fireEvent("PLAYER_DEAD")
				wow.advance(ns.DeathWatch.RECAP_DELAY)
			end)
			assert.are.equal("death recap", ns.db.errors[1].where)
		end)
	end)

	describe("vengeance", function()
		local function killGrimbash()
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
			return ns.db.ears[#ns.db.ears]
		end

		it("counts deaths since you last killed them", function()
			die({ target = GRIMBASH }, recap("Grimbash"))
			killGrimbash()
			wow.advance(3600)
			die({ target = GRIMBASH }, recap("Grimbash"))
			die({ target = GRIMBASH }, recap("Grimbash"))
			assert.are.equal(2, ns.Deaths.Debt(ns.db, GRIMBASH))
			assert.matches("2 times since you last killed them", wow.state().printed[#wow.state().printed])
		end)

		it("makes the next ear Legendary after three deaths, with its own toast and sound", function()
			for _ = 1, 3 do
				die({ target = GRIMBASH }, recap("Grimbash"))
				wow.advance(60)
			end
			assert.matches("Vengeance owed", wow.state().printed[#wow.state().printed])
			wow.state().sounds = {}
			local ear = killGrimbash()
			assert.are.equal(5, ear.quality)
			assert.are.equal(3, ear.vengeance)
			assert.matches(
				"|r Vengeance! You collected .*%(Legendary%)%. "
					.. "They had taken your ear three times in a row%. You finally have theirs%.$",
				wow.state().printed[#wow.state().printed]
			)
			local toast = ns.Toast.Active()[1]
			assert.are.equal("Vengeance!", toast.label:GetText())
			assert.are.equal("Legendary · Avenged 3 deaths", toast.detail:GetText())
			assert.are.equal(63971, wow.state().sounds[1].id)
			local text = {}
			for _, line in ipairs(ns.EarsTab.TooltipLines(ear)) do
				text[#text + 1] = line.text or line.left
			end
			assert.matches("\nVengeance for 3 deaths\n", table.concat(text, "\n"))
		end)

		it("clears the debt once taken", function()
			for _ = 1, 3 do
				die({ target = GRIMBASH }, recap("Grimbash"))
			end
			killGrimbash()
			assert.are.equal(0, ns.Deaths.Debt(ns.db, GRIMBASH))
			wow.advance(3600)
			assert.is_nil(killGrimbash().vengeance)
		end)

		it("drops a new ear even inside the repeat-kill window", function()
			killGrimbash()
			for _ = 1, 3 do
				wow.advance(30)
				die({ target = GRIMBASH }, recap("Grimbash"))
			end
			wow.advance(30)
			local ear = killGrimbash()
			assert.are.equal(2, #ns.db.ears)
			assert.are.equal(5, ear.quality)
		end)
	end)

	describe("in the pouch", function()
		local tab = wow.tab

		it("lists killers on the Rivals tab, with deaths and marks", function()
			die({ target = VELARIA }, recap("Velaria"))
			wow.advance(60)
			die({ target = VELARIA }, recap("Velaria"))
			wow.advance(3600)
			for _ = 1, 3 do
				die({ target = GRIMBASH }, recap("Grimbash"))
				wow.advance(60)
			end
			wow.slash("/ears")
			tab("Rivals"):Click()
			local rows = ns.RivalsTab.Rows()
			assert.matches("Grimbash", rows[1].name:GetText())
			assert.are.equal("0", rows[1].kills:GetText())
			assert.are.equal("3", rows[1].deaths:GetText())
			assert.are.equal("Avenge", rows[1].mark:GetText())
			assert.are.equal("Nemesis", rows[2].mark:GetText())
			assert.are.equal("2 rivals", ns.RivalsTab.Widgets().count:GetText())

			rows[1]:Enter()
			local lines = _G.GameTooltip.lines
			assert.are.equal("They killed you 3 times", lines[4])
			assert.matches("^Vengeance owed", lines[#lines])
			rows[1]:Click() -- no ear to show yet: nothing happens, the tooltip stays
			assert.are.equal("Rivals", ns.Pouch.ActiveTab())
			assert.is_true(_G.GameTooltip:IsShown())
		end)

		it("counts ears lost on the Ledger", function()
			die({ target = GRIMBASH }, recap("Grimbash"))
			wow.fireEvent("PARTY_KILL", ME, VELARIA)
			wow.slash("/ears")
			tab("Ledger"):Click()
			assert.are.equal("1", ns.LedgerTab.Widgets().stats[4]:GetText())
		end)
	end)

	describe("saved deaths", function()
		it("are repaired on load", function()
			wow.reset()
			ns = wow.loadAddon("EarCollector.toc", {
				EarCollectorDB = {
					deaths = {
						{ guid = GRIMBASH, at = 100 },
						{ guid = 7, at = 100 },
						"junk",
						{ guid = VELARIA },
					},
				},
			})
			assert.are.equal(1, #ns.db.deaths)
			assert.are.equal("Unknown", ns.db.deaths[1].name)
		end)
	end)
end)
