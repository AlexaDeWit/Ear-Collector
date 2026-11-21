-- Namespace setup. Every file receives (addonName, ns) from the client; ns is
-- the addon's private table, so nothing here leaks into the global scope.
local addonName, ns = ...

ns.name = addonName

-- The packager replaces the token below with the git tag (e.g. v0.1.0).
local version = "@project-version@"
ns.version = version:find("^@") and "dev" or version

-- Ear grades use the familiar item-quality colors.
ns.QUALITY = {
	[0] = { name = "Poor", color = "ff9d9d9d" },
	[1] = { name = "Common", color = "ffffffff" },
	[2] = { name = "Uncommon", color = "ff1eff00" },
	[3] = { name = "Rare", color = "ff0070dd" },
	[4] = { name = "Epic", color = "ffa335ee" },
	[5] = { name = "Legendary", color = "ffff8000" },
}
for _, quality in pairs(ns.QUALITY) do
	quality.r = tonumber(quality.color:sub(3, 4), 16) / 255
	quality.g = tonumber(quality.color:sub(5, 6), 16) / 255
	quality.b = tonumber(quality.color:sub(7, 8), 16) / 255
end

--- A grade's name and colours; an unknown grade shows as Uncommon.
---@param grade any
---@return { name: string, color: string, r: number, g: number, b: number }
function ns.Quality(grade)
	return ns.QUALITY[grade] or ns.QUALITY[2]
end
