-- luacheck config for a WoW addon. WoW runs a modified Lua 5.1 without io,
-- package/require/dofile/loadfile or debug, so using them in addon code is
-- flagged. Specs and scripts run in plain Lua 5.1 and get them back below.
std = "lua51"
max_line_length = 120
codes = true
exclude_files = { ".cache/", ".release/", ".luarocks/", "Libs/", "types/", ".claude/worktrees/" }
not_globals = { "io", "package", "require", "dofile", "loadfile", "module", "debug" }

-- Globals the addon writes: SavedVariables and slash-command registration.
globals = {
	"EarCollectorDB",
	"SLASH_EARCOLLECTOR1",
	"SLASH_EARCOLLECTOR2",
	SlashCmdList = { other_fields = true },
	-- Key binding (Bindings.xml) and minimap addon drawer (TOC AddonCompartmentFunc*)
	"BINDING_HEADER_EARCOLLECTOR",
	"BINDING_NAME_EARCOLLECTOR_TOGGLE",
	"EarCollector_TogglePouch",
	"EarCollector_OnAddonCompartmentClick",
	"EarCollector_OnAddonCompartmentEnter",
	"EarCollector_OnAddonCompartmentLeave",
}

-- WoW API the addon reads. Keep this explicit: adding an entry should be a
-- deliberate choice, and lua-language-server checks that each one exists.
read_globals = {
	"C_ClassColor",
	"C_Map",
	"C_PartyInfo",
	"C_PvP",
	"C_RestrictedActions",
	"C_Texture",
	"C_Timer",
	"CreateFrame",
	"CreateSettingsListSectionHeaderInitializer",
	"Enum",
	"EventRegistry",
	"GameTooltip",
	"GetPVPLifetimeStats",
	"GetPlayerInfoByGUID",
	"GetRealZoneText",
	"GetServerTime",
	"GetSubZoneText",
	"GetTime",
	"InCombatLockdown",
	"IsAnyBagOpen",
	"IsInInstance",
	"LOCALIZED_CLASS_NAMES_MALE",
	"MinimalSliderWithSteppersMixin",
	"PlaySound",
	"SOUNDKIT",
	"Settings",
	"RegionalUniqueNamesEnabled",
	"UIParent",
	"UISpecialFrames", -- the addon appends its pouch's name; see UI/Pouch.lua closeOnEscape
	"UnitGUID",
	"UnitLevel",
	"debugstack",
	"geterrorhandler",
	"hooksecurefunc",
	"issecretvalue",
	-- WoW additions to the Lua environment
	"date",
	"time",
}

local plainLua = { "io", "package", "require", "dofile", "loadfile", "debug" }
files["spec/**/*.lua"] = { std = "lua51+busted", read_globals = plainLua, globals = { "_G" } }
files["scripts/**/*.lua"] = { read_globals = plainLua }
