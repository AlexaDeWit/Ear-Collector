-- Blizzard's Settings screen, after Blizzard_Settings_Shared: categories with a
-- layout (section headers and controls, in order) and settings. Proxy getters
-- and setters run in a securecall stand-in, where an error lands in
-- state.gameErrors, which specs expect to stay empty.
return function(state)
	local function securecall(fn, ...)
		local results = { pcall(fn, ...) }
		if not results[1] then
			state.gameErrors[#state.gameErrors + 1] = tostring(results[2])
			return
		end
		return unpack(results, 2)
	end

	local registry = { categories = {} }

	-- Blizzard_Setting.lua: SetValue type-checks (ErrorIfInvalidVariableType).
	local function newSetting(category, variable, variableType, name, default, get, set)
		local setting = { variable = variable, variableType = variableType, name = name, default = default }
		function setting.GetValue()
			return get()
		end
		function setting.SetValue(_, value)
			if type(value) ~= variableType then
				error(("setting '%s' needs a %s, got %s"):format(name, variableType, type(value)), 2)
			end
			set(value)
		end
		function setting.SetValueToDefault(self)
			self:SetValue(default)
		end
		category.settings[variable] = setting
		return setting
	end

	local function addInitializer(category, initializer)
		local list = category.layout.initializers
		list[#list + 1] = initializer
		return initializer
	end

	registry.api = {
		RegisterVerticalLayoutCategory = function(name)
			local category =
				{ name = name, id = 100 + #registry.categories, settings = {}, layout = { initializers = {} } }
			function category.GetID(self)
				return self.id
			end
			function category.layout.AddInitializer(self, initializer)
				self.initializers[#self.initializers + 1] = initializer
			end
			registry.categories[#registry.categories + 1] = category
			return category, category.layout
		end,
		RegisterAddOnCategory = function(category)
			category.addon = true
		end,
		RegisterAddOnSetting = function(category, variable, key, tbl, variableType, name, default)
			assert(type(tbl) == "table", "'variableTbl' argument must be a table.")
			if tbl[key] == nil then
				tbl[key] = default
			end
			return newSetting(category, variable, variableType, name, default, function()
				return tbl[key]
			end, function(value)
				tbl[key] = value
			end)
		end,
		RegisterProxySetting = function(category, variable, variableType, name, default, getValue, setValue)
			return newSetting(category, variable, variableType, name, default, function()
				return securecall(getValue)
			end, function(value)
				securecall(setValue, value)
			end)
		end,
		CreateCheckbox = function(category, setting, tooltip)
			assert(setting.variableType == "boolean")
			return addInitializer(category, { control = "checkbox", setting = setting, tooltip = tooltip })
		end,
		CreateSliderOptions = function(minValue, maxValue, rate)
			local options = { minValue = minValue or 0, maxValue = maxValue or 1, formatters = {} }
			options.steps = rate and (options.maxValue - options.minValue) / rate or 100
			function options.SetLabelFormatter(self, labelType, formatter)
				self.formatters[labelType] = formatter
			end
			return options
		end,
		CreateSlider = function(category, setting, options, tooltip)
			assert(setting.variableType == "number" and options ~= nil)
			return addInitializer(
				category,
				{ control = "slider", setting = setting, options = options, tooltip = tooltip }
			)
		end,
		CreateControlTextContainer = function()
			local container = { data = {} }
			function container.Add(self, value, label, tooltip)
				self.data[#self.data + 1] = { value = value, label = label, tooltip = tooltip }
			end
			function container.GetData(self)
				return self.data
			end
			return container
		end,
		CreateDropdown = function(category, setting, options, tooltip)
			return addInitializer(
				category,
				{ control = "dropdown", setting = setting, options = options(), tooltip = tooltip }
			)
		end,
		-- C_SettingsUtil.OpenSettingsPanel has restrictions: blocked for addons in combat.
		OpenToCategory = function(categoryID)
			if state.inCombat then
				error("OpenSettingsPanel is blocked in combat", 2)
			end
			state.settingsOpenedTo = categoryID
		end,
	}
	return registry
end
