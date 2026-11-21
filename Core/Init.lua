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
