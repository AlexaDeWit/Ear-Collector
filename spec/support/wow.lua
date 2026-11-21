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

local function newFrame(frameType, name)
	local f = { frameType = frameType, name = name, events = {}, scripts = {}, shown = true }
	function f:RegisterEvent(event)
		self.events[event] = true
	end
	function f:UnregisterEvent(event)
		self.events[event] = nil
	end
	function f:IsEventRegistered(event)
		return self.events[event] == true
	end
	function f:SetScript(script, handler)
		self.scripts[script] = handler
	end
	function f:GetScript(script)
		return self.scripts[script]
	end
	return f
end

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
		now = 1795293660,
		players = {}, -- guid -> { name, realm, class, race, sex, level }
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
		printed = {},
	}
	for k, v in pairs(overrides or {}) do
		state[k] = v
	end

	_G.CreateFrame = function(frameType, name)
		local f = newFrame(frameType, name)
		frames[#frames + 1] = f
		if name then
			_G[name] = f
		end
		return f
	end
	_G.issecretvalue = isSecret
	_G.UnitGUID = function(unit)
		if unit == "player" then
			return state.playerGUID
		end
		return state.units[unit]
	end
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
		return p.class, p.class:upper(), p.race, p.race, p.sex or 2, p.name, p.realm or "", p.level
	end
	_G.GetServerTime = function()
		return state.now
	end
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
