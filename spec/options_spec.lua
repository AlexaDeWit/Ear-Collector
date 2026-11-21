local wow = require("spec.support.wow")

local ME = "Player-4395-0000000A"
local GRIMBASH = "Player-4395-0B1C2D3E"

describe("options page", function()
	local ns, Options

	local function load(saved)
		ns = wow.loadAddon("EarCollector.toc", saved and { EarCollectorDB = saved } or nil)
		Options = ns.Options
	end

	before_each(function()
		wow.reset()
		wow.addPlayer(GRIMBASH, { name = "Grimbash", class = "Warrior", race = "Orc", level = 60 })
	end)

	local function category()
		return wow.settingsCategory("Ear Collector")
	end

	-- The control whose setting is stored under `key` in db.settings.
	local function control(key)
		for _, init in ipairs(category().layout.initializers) do
			if init.setting and init.setting.variable == "EarCollector_" .. key then
				return init
			end
		end
		error("no control for " .. key)
	end

	describe("in Blizzard's Settings screen", function()
		before_each(function()
			load()
		end)

		it("adds Ear Collector to the AddOns list, with sections in order", function()
			assert.is_true(category().addon)
			assert.is_true(Options.IsRegistered())
			local shown = {}
			for _, init in ipairs(category().layout.initializers) do
				shown[#shown + 1] = init.header or init.setting.name
			end
			assert.are.same({
				"When you collect an ear",
				"Note it in your chat",
				"Show a toast",
				"Play a loot sound",
				"Ear Pouch",
				"Open with your bags",
				"What counts",
				"Free-for-all areas",
				"Zone-wide battles",
				"Repeat kill window",
			}, shown)
		end)

		it("gives every setting a name prefixed with the addon's, and a tooltip", function()
			for variable, setting in pairs(category().settings) do
				assert.matches("^EarCollector_", variable)
				assert.is_truthy(setting.name)
			end
			for _, init in ipairs(category().layout.initializers) do
				if init.setting then
					assert.is_truthy(init.tooltip and #init.tooltip > 20, init.setting.name)
				end
			end
		end)

		it("covers every setting except debug, with Blizzard's defaults matching the addon's", function()
			local covered = { campWindow = true, debug = true }
			for _, init in ipairs(category().layout.initializers) do
				if init.control == "checkbox" then
					local key = init.setting.variable:gsub("^EarCollector_", "")
					covered[key] = true
					assert.are.equal(ns.Database.DEFAULT_SETTINGS[key], init.setting.default, key)
				end
			end
			for key in pairs(ns.Database.DEFAULT_SETTINGS) do
				assert.is_true(covered[key], key .. " has no control")
			end
		end)
	end)

	describe("checkboxes", function()
		it("change the saved setting, and the addon follows at once", function()
			load()
			control("toast").setting:SetValue(false)
			assert.is_false(ns.db.settings.toast)
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
			assert.are.equal(0, #ns.Toast.Active())
			assert.are.equal(1, #ns.db.ears)
		end)

		it("show values changed with slash commands", function()
			load()
			wow.slash("/ears bags off")
			assert.is_false(control("openWithBags").setting:GetValue())
		end)

		it("show saved values from a previous session", function()
			load({ settings = { announce = false, includeBattlefields = true } })
			assert.is_false(control("announce").setting:GetValue())
			assert.is_true(control("includeBattlefields").setting:GetValue())
			assert.is_true(control("toast").setting:GetValue())
		end)

		it("reset to the addon's default", function()
			load({ settings = { toastSound = false } })
			control("toastSound").setting:SetValueToDefault()
			assert.is_true(ns.db.settings.toastSound)
		end)
	end)

	describe("repeat kill window slider", function()
		it("shows the saved window in minutes and saves seconds", function()
			load()
			local slider = control("campWindow")
			assert.are.equal(10, slider.setting:GetValue())
			assert.are.same({ 0, 60 }, { slider.options.minValue, slider.options.maxValue })
			assert.are.equal(60, slider.options.steps)
			assert.are.equal("15 min", slider.options.formatters[_G.MinimalSliderWithSteppersMixin.Label.Right](15))

			slider.setting:SetValue(15)
			assert.are.equal(900, ns.db.settings.campWindow)
			assert.are.equal(15, slider.setting:GetValue())
		end)

		it("changes how repeat kills count", function()
			load()
			control("campWindow").setting:SetValue(0)
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
			wow.state().now = wow.state().now + 60
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
			assert.are.equal(2, #ns.db.ears)
		end)

		it("keeps damaged or out-of-range saved values inside the slider", function()
			for _, case in ipairs({ { 99999, 60 }, { -30, 0 }, { 89, 1 }, { 0 / 0, 10 } }) do
				wow.reset()
				load({ settings = { campWindow = case[1] } })
				assert.are.equal(case[2], control("campWindow").setting:GetValue(), tostring(case[1]))
			end
		end)

		it("rounds and clamps what it saves, and ignores non-numbers", function()
			load()
			Options.SetCampMinutes(12.6)
			assert.are.equal(780, ns.db.settings.campWindow)
			Options.SetCampMinutes(500)
			assert.are.equal(3600, ns.db.settings.campWindow)
			Options.SetCampMinutes("ten")
			Options.SetCampMinutes(0 / 0)
			assert.are.equal(3600, ns.db.settings.campWindow)
			assert.are.equal("", control("campWindow").options.formatters[2](nil))
		end)

		it("keeps an error in its getter or setter away from the game", function()
			load()
			Options.GetCampMinutes = function()
				error("boom")
			end
			Options.SetCampMinutes = function()
				error("boom")
			end
			local slider = control("campWindow")
			assert.are.equal(10, slider.setting:GetValue()) -- the default, so the slider can still draw
			slider.setting:SetValue(20)
			assert.are.same({}, wow.state().gameErrors)
			assert.are.equal("options", ns.db.errors[1].where)
		end)
	end)

	describe("opening", function()
		before_each(function()
			load()
		end)

		it("opens with /ears options, config or settings", function()
			for _, command in ipairs({ "/ears options", "/ears config", "/ears settings" }) do
				wow.state().settingsOpenedTo = nil
				wow.slash(command)
				assert.are.equal(category().id, wow.state().settingsOpenedTo, command)
			end
		end)

		it("opens on right-click in the minimap drawer; left-click still toggles the pouch", function()
			_G.EarCollector_OnAddonCompartmentClick("EarCollector", "RightButton")
			assert.are.equal(category().id, wow.state().settingsOpenedTo)
			assert.is_false(ns.Pouch.IsShown())
			_G.EarCollector_OnAddonCompartmentClick("EarCollector", "LeftButton")
			assert.is_true(ns.Pouch.IsShown())
		end)

		it("waits for combat to end instead of being blocked", function()
			wow.state().inCombat = true
			wow.slash("/ears options")
			_G.EarCollector_OnAddonCompartmentClick("EarCollector", "RightButton")
			assert.is_nil(wow.state().settingsOpenedTo)
			assert.matches("during combat", wow.state().printed[#wow.state().printed])
			assert.are.same({}, ns.db.errors)

			wow.state().inCombat = false
			wow.slash("/ears options")
			assert.are.equal(category().id, wow.state().settingsOpenedTo)
		end)

		it("is listed in /ears help", function()
			wow.slash("/ears help")
			local found = false
			for _, line in ipairs(wow.state().printed) do
				found = found or line:find("/ears options", 1, true) ~= nil
			end
			assert.is_true(found)
		end)
	end)

	describe("when Blizzard's Settings API is missing or changes", function()
		it("loads without it, and says so when asked", function()
			_G.Settings = nil
			assert.has_no.errors(function()
				load()
			end)
			assert.is_false(Options.IsRegistered())
			assert.are.same({}, ns.db.errors) -- expected, not an error to report
			wow.slash("/ears options")
			assert.matches("isn't available", wow.state().printed[#wow.state().printed])
			wow.slash("/ears")
			assert.is_true(ns.Pouch.IsShown())
		end)

		it("contains an error while registering, and the rest of the addon works", function()
			_G.Settings.CreateSlider = function()
				error("changed API")
			end
			assert.has_no.errors(function()
				load()
			end)
			assert.matches("^ADDON_LOADED", ns.db.errors[1].where)
			wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
			assert.are.equal(1, #ns.db.ears)
		end)
	end)
end)
