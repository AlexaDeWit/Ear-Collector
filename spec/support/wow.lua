-- A small stand-in for the WoW Forever client, for busted specs.
-- It loads the addon the way the game does (TOC order, `...` = addonName, ns)
-- and lets a spec fire events and control what the API returns.
--
-- Only the API the addon uses is stubbed. When the addon starts using a new
-- API, add a stub here whose returns match Blizzard's docs, in order
-- (.cache/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated).
local wow = {}

local frames, state

-- Secret values: the client hands addons opaque values they may display but not
-- inspect. Here a secret is a table whose metatable errors on comparison,
-- concatenation, indexing and tostring, so a spec fails loudly if the addon
-- touches one. (Lua 5.1 only calls __eq between two tables, so `secret == "x"`
-- silently returns false; Context.Readable must still be checked first.)
local secretMeta = {}
local function forbid(op)
	return function()
		error("addon code tried to " .. op .. " a secret value", 2)
	end
end
secretMeta.__index = forbid("index")
secretMeta.__newindex = forbid("write to")
secretMeta.__concat = forbid("concatenate")
secretMeta.__lt = forbid("compare")
secretMeta.__le = forbid("compare")
secretMeta.__eq = forbid("compare")
secretMeta.__len = forbid("take the length of")
secretMeta.__call = forbid("call")
secretMeta.__tostring = forbid("convert to string")

--- A value the addon must treat as secret.
function wow.secret()
	return setmetatable({}, secretMeta)
end

-- Secret tables: not secret values themselves, but issecrettable is true and
-- the addon may not index them (canaccesstable is false). Lua 5.1 ignores __len
-- on tables, so #t is 0; specs set what HasRecapEvents etc. report separately.
local secretTableMeta = {
	__index = function()
		error("addon code tried to index a secret table", 2)
	end,
	__newindex = function()
		error("addon code tried to write to a secret table", 2)
	end,
}
local function isSecretTable(value)
	return type(value) == "table" and getmetatable(value) == secretTableMeta
end

--- A table the addon must not index.
function wow.secretTable()
	return setmetatable({}, secretTableMeta)
end

local function isSecret(value)
	return type(value) == "table" and getmetatable(value) == secretMeta
end

-- Blizzard's securecallfunction: an error inside goes to the game's error
-- handler (here state.gameErrors, which specs expect to stay empty) and the
-- caller carries on with no results.
local function securecall(fn, ...)
	local results = { pcall(fn, ...) }
	if not results[1] then
		state.gameErrors[#state.gameErrors + 1] = tostring(results[2])
		return
	end
	return unpack(results, 2)
end

-- Blizzard's Settings screen, after Blizzard_Settings_Shared: categories with a
-- layout (section headers and controls, in order) and settings.
local function newSettingsApi()
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

local settingsRegistry

-- Widgets: frames, buttons, textures and font strings. Methods whose state
-- specs inspect are real; any other capitalized method is a no-op so UI code can
-- run. lua-language-server, not these stubs, checks that method names exist.
local widgetMethods = {}
local function noop() end

local function fire(self, script, ...)
	local handler = self.scripts[script]
	if handler then
		return handler(self, ...)
	end
end

local newWidget

local widgetMeta = {
	__index = function(_, key)
		if widgetMethods[key] then
			return widgetMethods[key]
		end
		if type(key) == "string" and key:find("^%u") then
			return noop -- an unstubbed widget method
		end
		return nil -- an unset field, e.g. slot.ear
	end,
}

newWidget = function(widgetType, name, parent, template)
	local w = setmetatable({
		widgetType = widgetType,
		name = name,
		parent = parent,
		events = {},
		scripts = {},
		points = {},
		shown = true,
		enabled = true,
	}, widgetMeta)
	if template and template:find("BasicFrameTemplate") then
		w.TitleText = newWidget("FontString", nil, w)
		w.CloseButton = newWidget("Button", nil, w)
	end
	if template == "PanelTabButtonTemplate" then
		-- parentArray="Tabs": the client adds each tab to its parent's Tabs array.
		w.Text = newWidget("FontString", nil, w)
		w.Left = newWidget("Texture", nil, w)
		w.Right = newWidget("Texture", nil, w)
		local tabs = rawget(parent, "Tabs") or {}
		tabs[#tabs + 1] = w
		rawset(parent, "Tabs", tabs)
	end
	return w
end

-- Frame methods Forever restricts in combat (HasRestrictions in Blizzard's
-- SimpleFrame and SimpleScriptRegion API docs). The client blocks them from
-- addon code during combat; here they raise, so a spec fails if the addon uses
-- one while `state.inCombat` is true.
for _, method in ipairs({
	"SetPropagateKeyboardInput",
	"SetPassThroughButtons",
	"SetPropagateMouseClicks",
	"SetPropagateMouseMotion",
}) do
	widgetMethods[method] = function()
		if state.inCombat then
			error(method .. " is blocked in combat", 2)
		end
	end
end

function widgetMethods:RegisterEvent(event)
	self.events[event] = true
end
function widgetMethods:UnregisterEvent(event)
	self.events[event] = nil
end
function widgetMethods:IsEventRegistered(event)
	return self.events[event] == true
end
function widgetMethods:SetScript(script, handler)
	self.scripts[script] = handler
end
function widgetMethods:GetScript(script)
	return self.scripts[script]
end
function widgetMethods:Show()
	if not self.shown then
		self.shown = true
		fire(self, "OnShow")
	end
end
function widgetMethods:Hide()
	if self.shown then
		self.shown = false
		fire(self, "OnHide")
		-- Hiding a frame under the mouse sends it OnLeave. (Assumed, not
		-- verified in game: code must be safe either way.)
		if self.hovered then
			self.hovered = false
			fire(self, "OnLeave")
		end
	end
end
function widgetMethods:IsShown()
	return self.shown
end
function widgetMethods:SetShown(shown)
	if shown then
		self:Show()
	else
		self:Hide()
	end
end
function widgetMethods:SetText(text)
	self.text = text
end
function widgetMethods:GetText()
	return self.text
end
function widgetMethods:SetAtlas(atlas)
	self.atlas, self.texture = atlas, nil
end
function widgetMethods:SetTexture(texture)
	self.texture, self.atlas = texture, nil
end
function widgetMethods:SetColorTexture(r, g, b, a)
	self.color = { r, g, b, a }
end
function widgetMethods:SetDesaturated(desaturated)
	self.desaturated = desaturated
end
function widgetMethods:SetEnabled(enabled)
	self.enabled = enabled
end
function widgetMethods:IsEnabled()
	return self.enabled
end
function widgetMethods:SetPoint(...)
	self.points[#self.points + 1] = { ... }
end
function widgetMethods:GetPoint(i)
	local p = self.points[i or 1]
	if p then
		return unpack(p)
	end
end
function widgetMethods:ClearAllPoints()
	self.points = {}
end
function widgetMethods:SetSize(width, height)
	self.width, self.height = width, height
end
function widgetMethods:GetWidth()
	return self.width or 0
end
function widgetMethods:SetWidth(width)
	self.width = width
end
function widgetMethods:SetHeight(height)
	self.height = height
end
function widgetMethods:GetHeight()
	return self.height or 0
end
function widgetMethods:SetID(id)
	self.id = id
end
function widgetMethods:GetID()
	return self.id or 0
end
function widgetMethods:LockHighlight()
	self.highlightLocked = true
end
function widgetMethods:UnlockHighlight()
	self.highlightLocked = false
end
function widgetMethods:SetAlpha(alpha)
	self.alpha = alpha
end
function widgetMethods:GetAlpha()
	return self.alpha or 1
end
-- Animation groups: Play/Stop/IsPlaying; wow.finishAnimations() completes them.
local animationGroups = {}
function widgetMethods.CreateAnimationGroup(owner)
	local group = newWidget("AnimationGroup", nil, owner)
	group.playing, group.plays = false, 0
	function group:Play()
		self.playing, self.plays = true, self.plays + 1
	end
	function group:Stop()
		self.playing = false
	end
	function group:IsPlaying()
		return self.playing
	end
	function group:CreateAnimation(kind)
		return newWidget(kind or "Animation", nil, self)
	end
	animationGroups[#animationGroups + 1] = group
	return group
end
function widgetMethods:CreateTexture(name)
	return newWidget("Texture", name, self)
end
function widgetMethods:CreateFontString(name)
	return newWidget("FontString", name, self)
end
--- Spec helpers: act like the player.
function widgetMethods:Click(button)
	fire(self, "OnClick", button or "LeftButton")
end
function widgetMethods:Enter()
	self.hovered = true
	fire(self, "OnEnter")
end
function widgetMethods:Leave()
	self.hovered = false
	fire(self, "OnLeave")
end
function widgetMethods:Drag()
	fire(self, "OnDragStart")
	self.points = { { "CENTER", _G.UIParent, "CENTER", 100, -50 } }
	fire(self, "OnDragStop")
end
function widgetMethods:Wheel(delta)
	fire(self, "OnMouseWheel", delta)
end

-- The game tooltip records its lines.
local function newTooltip()
	local tip = newWidget("GameTooltip", "GameTooltip")
	tip.shown = false
	tip.lines = {}
	function tip:SetOwner(owner)
		self.owner = owner
		self.lines = {}
	end
	function tip:IsOwned(frame)
		return self.owner == frame
	end
	function tip:AddLine(text)
		self.lines[#self.lines + 1] = text
	end
	function tip:AddDoubleLine(left, right)
		self.lines[#self.lines + 1] = left .. " | " .. right
	end
	return tip
end

local CLASS_COLORS = {
	WARRIOR = "ffc69b6d",
	ROGUE = "fffff468",
	HUNTER = "ffaad372",
	MAGE = "ff3fc7eb",
	WARLOCK = "ff8788ee",
	PRIEST = "ffffffff",
	SHAMAN = "ff0070dd",
	DRUID = "ffff7c0a",
	PALADIN = "fff48cba",
}

--- Reset the fake client. Call from before_each. `overrides` sets initial state.
function wow.reset(overrides)
	frames = {}
	state = {
		playerGUID = "Player-4395-0000000A",
		playerLevel = 60,
		trivialRange = 12, -- how far below you the game shows levels green
		faction = "Alliance", -- yours; other players are Horde unless their info says
		freeForAll = false, -- in a free-for-all area anyone can be attacked
		inInstance = false,
		instanceType = "none",
		pvpType = "contested",
		mapID = 1424,
		zone = "Hillsbrad Foothills",
		subzone = "Tarren Mill",
		now = 1795293660, -- GetServerTime(), seconds
		clock = 5000, -- GetTime(), seconds since the client started
		timers = {}, -- pending C_Timer.After callbacks
		lifetimeHonorableKills = 120,
		players = {}, -- guid -> { name, realm, class, race, sex, level, faction }; Forever's name is "First Surname"
		group = {}, -- guid -> true for players in your party/raid
		units = {}, -- extra unit tokens -> guid, e.g. pet = "Pet-...", partypet1 = "Pet-..."
		atlases = { -- atlases the client has; Skyborne is left out to exercise the fallback
			["raceicon-orc-male"] = true,
			["raceicon-orc-female"] = true,
			["raceicon-undead-male"] = true,
			["raceicon-undead-female"] = true,
			["raceicon-troll-male"] = true,
			["raceicon-tauren-male"] = true,
		},
		regionalNames = true, -- Forever: first name + surname instead of realms
		restrictions = {}, -- Enum.AddOnRestrictionType name -> true while active
		bagsOpen = false,
		recap = nil, -- death recap events, newest first
		-- The built-in damage meter: each fight is { sessionID, enemies = { { guid, name, amount } } },
		-- newest last. wow.meterFight adds one.
		damageMeter = { available = true, sessions = {} },
		inCombat = false,
		gameMenuShown = false,
		gameErrors = {}, -- errors that reached the game's error handler (see securecall)
		settingsOpenedTo = nil, -- category ID the Settings screen was opened on
		sounds = {}, -- PlaySound calls
		printed = {},
	}
	for k, v in pairs(overrides or {}) do
		state[k] = v
	end

	animationGroups = {}
	_G.UIParent = newWidget("Frame", "UIParent")
	_G.SOUNDKIT = {
		UI_RAID_LOOT_TOAST_LESSER_ITEM_WON = 51402,
		UI_EPICLOOT_TOAST = 31578,
		UI_LEGENDARY_LOOT_TOAST = 63971,
		IG_CHARACTER_INFO_TAB = 841,
	}
	_G.PlaySound = function(soundKitID, channel)
		state.sounds[#state.sounds + 1] = { id = soundKitID, channel = channel }
	end
	_G.GameTooltip = newTooltip()
	_G.CreateFrame = function(frameType, name, parent, template)
		local f = newWidget(frameType, name, parent, template)
		frames[#frames + 1] = f
		if name then
			_G[name] = f
		end
		return f
	end
	_G.hooksecurefunc = function(tbl, name, hook)
		if type(tbl) == "string" then
			tbl, name, hook = _G, tbl, name
		end
		local original = tbl[name]
		tbl[name] = function(...)
			local results = { original(...) }
			hook(...)
			return unpack(results)
		end
	end
	-- Bags: Blizzard's bag functions, reduced to one open/closed flag.
	_G.ToggleAllBags = function()
		state.bagsOpen = not state.bagsOpen
	end
	_G.OpenAllBags = function()
		state.bagsOpen = true
	end
	_G.CloseAllBags = function()
		state.bagsOpen = false
	end
	_G.ToggleBackpack = _G.ToggleAllBags
	_G.OpenBackpack = _G.OpenAllBags
	_G.CloseBackpack = _G.CloseAllBags
	-- One bag: the fake has a single bag, so these act on "the bags". CloseBag is
	-- what a bag frame's own close button calls.
	_G.ToggleBag = _G.ToggleAllBags
	_G.OpenBag = function()
		state.bagsOpen = true
	end
	_G.CloseBag = _G.CloseAllBags
	_G.IsAnyBagOpen = function()
		return state.bagsOpen
	end
	_G.UnitAffectingCombat = function(unit)
		return unit == "player" and state.inCombat
	end
	_G.InCombatLockdown = function()
		return state.inCombat
	end
	settingsRegistry = newSettingsApi()
	_G.Settings = settingsRegistry.api
	_G.CreateSettingsListSectionHeaderInitializer = function(name, tooltip)
		return { header = name, tooltip = tooltip }
	end
	-- Tabs (SharedUIPanelTemplates.lua). UpdateTabs indexes frame.Tabs[1..numTabs],
	-- so a missing tab errors there as it would in the client.
	_G.PanelTemplates_SetNumTabs = function(frame, numTabs)
		frame.numTabs = numTabs
	end
	_G.PanelTemplates_SetTab = function(frame, id)
		frame.selectedTab = id
		for i = 1, frame.numTabs do
			local tabs = rawget(frame, "Tabs")
			assert(tabs and tabs[i], "no tab " .. i).selected = i == id
		end
	end
	_G.MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 } }
	-- Frames Escape hides, as Forever's UIParentPanelManager.lua starts it.
	_G.UISpecialFrames = {
		"ItemRefTooltip",
		"ColorPickerFrame",
		"FloatingPetBattleAbilityTooltip",
		"FloatingGarrisonFollowerTooltip",
		"FloatingGarrisonShipyardFollowerTooltip",
	}
	-- EventRegistry: only what "addon" chat links use.
	_G.EventRegistry = {
		callbacks = {},
		RegisterCallback = function(self, event, func, owner)
			self.callbacks[#self.callbacks + 1] = { event = event, func = func, owner = owner }
		end,
	}
	_G.C_ClassColor = {
		-- Returns a ColorMixin; only GenerateHexColor is stubbed.
		GetClassColor = function(className)
			local hex = CLASS_COLORS[className]
			return hex and {
				GenerateHexColor = function()
					return hex
				end,
			} or nil
		end,
	}
	_G.LOCALIZED_CLASS_NAMES_MALE = {
		WARRIOR = "Warrior",
		ROGUE = "Rogue",
		HUNTER = "Hunter",
		MAGE = "Mage",
		WARLOCK = "Warlock",
		PRIEST = "Priest",
		SHAMAN = "Shaman",
		DRUID = "Druid",
		PALADIN = "Paladin",
	}
	_G.issecretvalue = isSecret
	_G.issecrettable = isSecretTable
	_G.canaccesstable = function(t)
		return not isSecretTable(t)
	end
	_G.UnitGUID = function(unit)
		if unit == "player" then
			return state.playerGUID
		end
		return state.units[unit]
	end
	-- Units: a unit exists when state.units (or "player") names a GUID. Players
	-- are GUIDs starting "Player-". You can attack players who aren't you or in
	-- your group. UnitName returns name, server (the surname on Forever).
	_G.UnitExists = function(unit)
		return _G.UnitGUID(unit) ~= nil
	end
	_G.UnitIsPlayer = function(unit)
		local guid = _G.UnitGUID(unit)
		return type(guid) == "string" and guid:find("^Player%-") ~= nil
	end
	-- Players of the other faction, or anyone outside your group in a free-for-all area.
	_G.UnitCanAttack = function(_, target)
		local guid = _G.UnitGUID(target)
		if guid == nil or guid == state.playerGUID or state.group[guid] then
			return false
		end
		local p = state.players[guid]
		return state.freeForAll or not p or (p.faction or "Horde") ~= state.faction
	end
	-- The nameplates on screen: a frame for each `nameplateN` in state.units,
	-- with Blizzard's NamePlateBaseMixin:GetUnit().
	_G.C_NamePlate = {
		GetNamePlates = function()
			local plates = {}
			for token in pairs(state.units) do
				if token:find("^nameplate%d+$") then
					plates[#plates + 1] = {
						GetUnit = function()
							return token
						end,
					}
				end
			end
			return plates
		end,
	}
	_G.UnitName = function(unit)
		local guid = _G.UnitGUID(unit)
		local p = guid ~= nil and state.players[guid]
		if not p then
			return nil
		end
		return p.name, p.realm or ""
	end
	-- Death recap: state.recap is the event list, newest first (the first caused
	-- the death), or nil when there is none.
	_G.C_DeathRecap = {
		HasRecapEvents = function()
			return state.recap ~= nil and (isSecretTable(state.recap) or #state.recap > 0)
		end,
		GetRecapEvents = function()
			return state.recap or {}
		end,
	}
	-- The damage meter (DamageMeterDocumentation.lua). Session data is secret in
	-- combat (SecretWhenInCombat), and the list of sessions isn't.
	local function meterSession(session, kind)
		if state.inCombat then
			return wow.secretTable()
		end
		local sources = {}
		if session and kind == _G.Enum.DamageMeterType.EnemyDamageTaken then
			for _, enemy in ipairs(session.enemies) do
				sources[#sources + 1] = {
					sourceGUID = enemy.guid,
					name = enemy.name,
					totalAmount = enemy.amount or 100,
					sourceDisplayType = _G.Enum.DamageMeterSourceDisplayType.Enemy,
				}
			end
		end
		return { combatSources = sources, maxAmount = 0, totalAmount = 0 }
	end
	_G.C_DamageMeter = {
		IsDamageMeterAvailable = function()
			return state.damageMeter.available, state.damageMeter.available and "" or "unavailable"
		end,
		GetAvailableCombatSessions = function()
			local list = {}
			for _, session in ipairs(state.damageMeter.sessions) do
				list[#list + 1] = { sessionID = session.sessionID, name = "", durationSeconds = 10 }
			end
			return list
		end,
		GetCombatSessionFromID = function(sessionID, kind)
			for _, session in ipairs(state.damageMeter.sessions) do
				if session.sessionID == sessionID then
					return meterSession(session, kind)
				end
			end
			return meterSession(nil, kind)
		end,
		GetCombatSessionFromType = function(sessionType, kind)
			local sessions = state.damageMeter.sessions
			local current = sessionType == _G.Enum.DamageMeterSessionType.Current and sessions[#sessions] or nil
			return meterSession(current, kind)
		end,
	}
	_G.RegionalUniqueNamesEnabled = function()
		return state.regionalNames
	end
	_G.Enum = {
		AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
		DamageMeterType = { DamageDone = 0, DamageTaken = 7, Deaths = 9, EnemyDamageTaken = 10 },
		DamageMeterSessionType = { Overall = 0, Current = 1, Expired = 2 },
		DamageMeterSourceDisplayType = { None = 0, Ally = 1, Enemy = 2 },
	}
	_G.C_RestrictedActions = {
		IsAddOnRestrictionActive = function(kind)
			for name, value in pairs(_G.Enum.AddOnRestrictionType) do
				if value == kind then
					return state.restrictions[name] == true
				end
			end
			return false
		end,
	}
	_G.C_PartyInfo = {
		IsGUIDInGroup = function(guid)
			return state.group[guid] == true
		end,
	}
	_G.C_Texture = {
		-- Returns an AtlasInfo table, or nothing when the atlas doesn't exist.
		GetAtlasInfo = function(atlas)
			if state.atlases[atlas] then
				return { width = 64, height = 64, file = 0 }
			end
			return nil
		end,
	}
	_G.UnitLevel = function(unit)
		if unit == "player" then
			return state.playerLevel
		end
		return 0
	end
	_G.UnitQuestTrivialLevelRange = function()
		return state.trivialRange
	end
	_G.IsInInstance = function()
		return state.inInstance, state.instanceType
	end
	_G.C_PvP = {
		-- Returns pvpType, isSubZonePvP, factionName.
		GetZonePVPInfo = function()
			return state.pvpType, false, nil
		end,
	}
	_G.C_Map = {
		GetBestMapForUnit = function(unit)
			return unit == "player" and state.mapID or nil
		end,
	}
	_G.GetRealZoneText = function()
		return state.zone
	end
	_G.GetSubZoneText = function()
		return state.subzone
	end
	-- Returns localizedClass, englishClass, localizedRace, englishRace, sex, name, realmName, level.
	_G.GetPlayerInfoByGUID = function(guid)
		local p = state.players[guid]
		if not p then
			return nil
		end
		return p.class, p.class:upper(), p.raceName or p.race, p.race, p.sex or 2, p.name, p.realm or "", p.level
	end
	_G.GetServerTime = function()
		return state.now
	end
	_G.GetTime = function()
		return state.clock
	end
	-- Returns lifetimeHonorableKills, lifetimeMaxPVPRank.
	_G.GetPVPLifetimeStats = function()
		return state.lifetimeHonorableKills, 0
	end
	_G.C_Timer = {
		After = function(seconds, callback)
			state.timers[#state.timers + 1] = { due = state.clock + seconds, fn = callback }
		end,
	}
	_G.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		state.printed[#state.printed + 1] = table.concat(parts, " ")
	end
	_G.date = os.date
	_G.SlashCmdList = {}
	_G.SLASH_EARCOLLECTOR1, _G.SLASH_EARCOLLECTOR2 = nil, nil
	_G.EarCollectorDB = nil
	_G.EarCollectorCharDB = nil
end

--- Load the addon from its TOC like the client does: SavedVariables are set as
--- globals first, each listed file runs with (addonName, ns), then ADDON_LOADED fires.
---@param tocPath string
---@param savedVariables table|nil e.g. { EarCollectorDB = {...} }
function wow.loadAddon(tocPath, savedVariables)
	local dir = tocPath:match("^(.*)/[^/]+$") or "."
	local addonName = tocPath:match("([^/\\]+)%.toc$")
	local ns = {}
	for k, v in pairs(savedVariables or {}) do
		_G[k] = v
	end
	for line in io.lines(tocPath) do
		line = line:gsub("\r$", ""):match("^%s*(.-)%s*$")
		if line ~= "" and not line:find("^#") then
			local path = dir .. "/" .. line:gsub("\\", "/")
			if path:find("%.lua$") then
				local chunk = assert(loadfile(path))
				chunk(addonName, ns)
			end
		end
	end
	wow.fireEvent("ADDON_LOADED", addonName)
	return ns, addonName
end

function wow.fireEvent(event, ...)
	for _, f in ipairs(frames) do
		local handler = f.scripts.OnEvent
		if f.events[event] and handler then
			handler(f, event, ...)
		end
	end
end

--- Finish every playing animation group, firing OnFinished as the client does.
function wow.finishAnimations()
	for _, group in ipairs(animationGroups) do
		if group.playing then
			group.playing = false
			local handler = group.scripts.OnFinished
			if handler then
				handler(group, false)
			end
		end
	end
end

--- Click a chat hyperlink, as Blizzard's "addon" link handler does: it fires
--- EventRegistry "SetItemRef" with (link, text, button, chatFrame).
function wow.clickLink(link, button)
	for _, cb in ipairs(_G.EventRegistry.callbacks) do
		if cb.event == "SetItemRef" then
			cb.func(cb.owner, link, "[link]", button or "LeftButton", nil)
		end
	end
end

--- Run a key binding's body, as the client does when the key is pressed.
function wow.pressBinding(name)
	local file = assert(io.open("Bindings.xml"))
	local xml = file:read("*a")
	file:close()
	local body = xml:match('<Binding name="' .. name .. '"[^>]*>(.-)</Binding>')
	assert(body, "no binding " .. name)
	assert(loadstring(body))()
end

--- Press Escape. Forever's binding runs ToggleGameMenu (Blizzard_GameMenuEsc),
--- which offers the key to handlers in priority order and opens the game menu
--- only if none takes it. Modelled here: the game menu closing (Framework), then
--- CloseAllWindows (AddOnPost), which closes the bags and hides each shown frame
--- named in UISpecialFrames.
function wow.pressEscape()
	if state.gameMenuShown then
		state.gameMenuShown = false
		return
	end
	local found = _G.IsAnyBagOpen()
	_G.CloseAllBags()
	for _, name in pairs(_G.UISpecialFrames) do
		local f = _G[name]
		if f and f:IsShown() then
			f:Hide()
			found = true
		end
	end
	if not found then
		state.gameMenuShown = true
	end
end

--- Let `seconds` pass: both clocks move and due C_Timer callbacks run, in order.
function wow.advance(seconds)
	-- Timers run in order, each at its own time, including timers that an
	-- earlier one starts within the same span, as the client runs them.
	local startClock, startNow = state.clock, state.now
	local target = startClock + seconds
	while true do
		local nextIndex
		for i, timer in ipairs(state.timers) do
			if timer.due <= target and (not nextIndex or timer.due < state.timers[nextIndex].due) then
				nextIndex = i
			end
		end
		if not nextIndex then
			break
		end
		local timer = table.remove(state.timers, nextIndex)
		state.clock = math.max(state.clock, timer.due)
		state.now = startNow + math.floor(state.clock - startClock)
		timer.fn()
	end
	state.clock = target
	state.now = startNow + math.floor(seconds)
end

--- Your honorable-kill count goes up by `n`, as the client reports it.
--- A fight on the damage meter, in which you or your group damaged `enemies`
--- ({ guid, name, amount? } each).
function wow.meterFight(enemies)
	local sessions = state.damageMeter.sessions
	sessions[#sessions + 1] = { sessionID = #sessions + 1, enemies = enemies }
end

--- You enter combat, as the client reports it.
function wow.startCombat()
	state.inCombat = true
	wow.fireEvent("PLAYER_REGEN_DISABLED")
end

--- You leave combat, as the client reports it.
function wow.endCombat()
	state.inCombat = false
	wow.fireEvent("PLAYER_REGEN_ENABLED")
end

function wow.honorableKill(n)
	state.lifetimeHonorableKills = state.lifetimeHonorableKills + (n or 1)
	wow.fireEvent("PLAYER_PVP_KILLS_CHANGED", "player")
end

--- Run a slash command as if the player typed it.
function wow.slash(text)
	local command, rest = text:match("^(/%S+)%s*(.*)$")
	for key, fn in pairs(_G.SlashCmdList) do
		for i = 1, 9 do
			if _G["SLASH_" .. key .. i] == command then
				return fn(rest)
			end
		end
	end
	error("no slash command " .. command)
end

--- Replay a recorded fixture: { setup = {...}, events = { {event, ...}, { set = {...} }, ... } }.
--- The string "<secret>" (how /ears debug logs a secret value) becomes a secret value.
function wow.replay(fixture)
	for k, v in pairs(fixture.setup or {}) do
		state[k] = v
	end
	for _, e in ipairs(fixture.events) do
		if e.advance then
			wow.advance(e.advance)
		elseif e.set then
			for k, v in pairs(e.set) do
				state[k] = v
			end
		else
			local args = {}
			for i = 1, #e do
				args[i] = e[i] == "<secret>" and wow.secret() or e[i]
			end
			wow.fireEvent(unpack(args, 1, #e))
		end
	end
end

--- A category registered in the Settings screen, by name, or nil.
function wow.settingsCategory(name)
	for _, category in ipairs(settingsRegistry.categories) do
		if category.name == name then
			return category
		end
	end
	return nil
end

function wow.addPlayer(guid, info)
	state.players[guid] = info
end

function wow.state()
	return state
end

return wow
