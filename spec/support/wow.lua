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

local function isSecret(value)
	return type(value) == "table" and getmetatable(value) == secretMeta
end

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
	return w
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
	fire(self, "OnEnter")
end
function widgetMethods:Leave()
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
		players = {}, -- guid -> { name, realm (the surname on Forever), class, race, sex, level }
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
	_G.IsAnyBagOpen = function()
		return state.bagsOpen
	end
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
	_G.UnitGUID = function(unit)
		if unit == "player" then
			return state.playerGUID
		end
		return state.units[unit]
	end
	_G.RegionalUniqueNamesEnabled = function()
		return state.regionalNames
	end
	_G.Enum = {
		AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
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

--- Let `seconds` pass: both clocks move and due C_Timer callbacks run, in order.
function wow.advance(seconds)
	state.clock = state.clock + seconds
	state.now = state.now + math.floor(seconds)
	local due, waiting = {}, {}
	for _, timer in ipairs(state.timers) do
		if timer.due <= state.clock then
			due[#due + 1] = timer
		else
			waiting[#waiting + 1] = timer
		end
	end
	state.timers = waiting
	table.sort(due, function(a, b)
		return a.due < b.due
	end)
	for _, timer in ipairs(due) do
		timer.fn()
	end
end

--- Your honorable-kill count goes up by `n`, as the client reports it.
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
		if e.set then
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

function wow.addPlayer(guid, info)
	state.players[guid] = info
end

function wow.state()
	return state
end

return wow
