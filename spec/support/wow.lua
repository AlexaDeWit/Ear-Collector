-- A stand-in for the WoW Forever client, for busted specs. It loads the addon
-- the way the game does (TOC order, `...` = addonName, ns) and lets a spec fire
-- events and control what the API returns. The pieces:
--   spec/support/api.lua      the game API stubs, over `state`
--   spec/support/widgets.lua  frames, textures, the tooltip, animation groups
--   spec/support/settings.lua Blizzard's Settings screen
--   spec/support/secrets.lua  secret values and tables
local Secrets = require("spec.support.secrets")
local Widgets = require("spec.support.widgets")
local installApi = require("spec.support.api")

local wow = {}

local frames, state, settings

wow.secret = Secrets.value -- a value the addon must treat as secret
wow.secretTable = Secrets.table -- a table the addon must not index
wow.finishAnimations = Widgets.finishAnimations -- complete playing groups, firing OnFinished

--- Reset the fake client. Call from before_each. `overrides` sets initial state.
function wow.reset(overrides)
	frames = {}
	state = {
		playerGUID = "Player-4395-0000000A",
		playerLevel = 60,
		playerMaxHealth = 1000,
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
			["bags-glow-white"] = true,
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
	Widgets.reset(state)
	settings = installApi(state, frames)
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

--- Click a chat hyperlink, as Blizzard's "addon" link handler does: it fires
--- EventRegistry "SetItemRef" with (link, text, button, chatFrame).
function wow.clickLink(link, button)
	for _, cb in ipairs(_G.EventRegistry.callbacks) do
		if cb.event == "SetItemRef" then
			cb.func(cb.owner, link, "[link]", button or "LeftButton", nil)
		end
	end
end

--- Hover a chat hyperlink, or leave it with `link` nil, as ChatFrameMixin does:
--- EventRegistry "ChatFrame.OnHyperlinkEnter" (chatFrame, link, text) and
--- "ChatFrame.OnHyperlinkLeave" (chatFrame).
function wow.hoverLink(link)
	local chatFrame = _G.ChatFrame1 or _G.CreateFrame("Frame", "ChatFrame1")
	local event = link and "ChatFrame.OnHyperlinkEnter" or "ChatFrame.OnHyperlinkLeave"
	for _, cb in ipairs(_G.EventRegistry.callbacks) do
		if cb.event == event then
			cb.func(cb.owner, chatFrame, link, "[link]")
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

--- A fight on the damage meter, in which you or your group damaged `enemies`
--- ({ guid, name, amount? } each). `views` gives your side's other totals, by
--- Enum.DamageMeterType name: { DamageTaken = { { amount = 1200, me = true } } }.
function wow.meterFight(enemies, views)
	local sessions = state.damageMeter.sessions
	sessions[#sessions + 1] = { sessionID = #sessions + 1, enemies = enemies, views = views or {} }
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
	for _, category in ipairs(settings.categories) do
		if category.name == name then
			return category
		end
	end
	return nil
end

--- The decisions /ears debug logged: for one event, or all as "EVENT: decision".
---@param event string?
---@return string[]
function wow.decisions(event)
	local list = {}
	for _, entry in ipairs(_G.EarCollectorDB and _G.EarCollectorDB.debugLog or {}) do
		if not event then
			list[#list + 1] = entry.event .. ": " .. entry.decision
		elseif entry.event == event then
			list[#list + 1] = entry.decision
		end
	end
	return list
end

--- How many printed chat lines match `pattern`.
function wow.printed(pattern)
	local n = 0
	for _, line in ipairs(state.printed) do
		if line:find(pattern) then
			n = n + 1
		end
	end
	return n
end

--- The pouch's tab button titled `title`.
function wow.tab(title)
	for _, t in ipairs(rawget(_G.EarCollectorPouch, "Tabs") or {}) do
		if t:GetText() == title then
			return t
		end
	end
	error("no tab " .. title)
end

function wow.addPlayer(guid, info)
	state.players[guid] = info
end

function wow.state()
	return state
end

return wow
