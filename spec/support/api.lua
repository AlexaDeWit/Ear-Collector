-- The game API the addon calls, stubbed over the fake client's `state`. Each
-- stub's returns match Blizzard's docs, in order
-- (.cache/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated).
-- When the addon starts using a new API, add its stub here.
local Secrets = require("spec.support.secrets")
local Widgets = require("spec.support.widgets")
local newSettings = require("spec.support.settings")

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

--- Install the stubs as globals. `frames` collects created frames, for events.
---@return table settings the Settings screen's registry
return function(state, frames)
	_G.UIParent = Widgets.new("Frame", "UIParent")
	_G.SOUNDKIT = {
		UI_RAID_LOOT_TOAST_LESSER_ITEM_WON = 51402,
		UI_EPICLOOT_TOAST = 31578,
		UI_LEGENDARY_LOOT_TOAST = 63971,
		IG_CHARACTER_INFO_TAB = 841,
		IG_ABILITY_PAGE_TURN = 836,
		IG_BACKPACK_OPEN = 862,
		IG_BACKPACK_CLOSE = 863,
	}
	_G.PlaySound = function(soundKitID, channel)
		state.sounds[#state.sounds + 1] = { id = soundKitID, channel = channel }
	end
	_G.GameTooltip = Widgets.tooltip()
	_G.CreateFrame = function(frameType, name, parent, template)
		local f = Widgets.new(frameType, name, parent, template)
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
	local settings = newSettings(state)
	_G.Settings = settings.api
	_G.CreateSettingsListSectionHeaderInitializer = function(name, tooltip)
		return { header = name, tooltip = tooltip }
	end
	_G.CreateSettingsButtonInitializer = function(name, buttonText, buttonClick, tooltip, addSearchTags)
		assert(addSearchTags ~= nil)
		return { control = "button", name = name, buttonText = buttonText, click = buttonClick, tooltip = tooltip }
	end
	_G.UnitFactionGroup = function(unit)
		if unit == "player" then
			return state.faction, state.faction
		end
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
	_G.issecretvalue = Secrets.isValue
	_G.issecrettable = Secrets.isTable
	_G.canaccesstable = function(t)
		return not Secrets.isTable(t)
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
			return state.recap ~= nil and (Secrets.isTable(state.recap) or #state.recap > 0)
		end,
		GetRecapEvents = function()
			return state.recap or {}
		end,
	}
	-- The damage meter (DamageMeterDocumentation.lua). Session data is secret in
	-- combat (SecretWhenInCombat), and the list of sessions isn't.
	local function meterSession(session, kind)
		if state.inCombat then
			return Secrets.table()
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
	return settings
end
