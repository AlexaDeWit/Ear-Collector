-- luacheck config for a WoW addon. WoW runs a modified Lua 5.1 without io,
-- package/require/dofile/loadfile or debug, so using them in addon code is
-- flagged. Specs and scripts run in plain Lua 5.1 and get them back below.
std = "lua51"
max_line_length = 120
codes = true
exclude_files = { ".cache/", ".release/", ".luarocks/", "Libs/", "types/" }
not_globals = { "io", "package", "require", "dofile", "loadfile", "module", "debug" }

-- Globals the addon writes: SavedVariables and slash-command registration.
globals = {
	"EarCollectorDB",
	"SLASH_EARCOLLECTOR1",
	"SLASH_EARCOLLECTOR2",
	SlashCmdList = { other_fields = true },
}

-- WoW API the addon reads. Keep this explicit: adding an entry should be a
-- deliberate choice, and lua-language-server checks that each one exists.
read_globals = {
	"C_Map",
	"C_PartyInfo",
	"C_PvP",
	"C_RestrictedActions",
	"C_Texture",
	"C_Timer",
	"CreateFrame",
	"Enum",
	"GetPVPLifetimeStats",
	"GetPlayerInfoByGUID",
	"GetRealZoneText",
	"GetServerTime",
	"GetSubZoneText",
	"GetTime",
	"IsInInstance",
	"RegionalUniqueNamesEnabled",
	"UnitGUID",
	"UnitLevel",
	"debugstack",
	"geterrorhandler",
	"issecretvalue",
	-- WoW additions to the Lua environment
	"date",
	"time",
}

local plainLua = { "io", "package", "require", "dofile", "loadfile", "debug" }
files["spec/**/*.lua"] = { std = "lua51+busted", read_globals = plainLua, globals = { "_G" } }
files["scripts/**/*.lua"] = { read_globals = plainLua }
