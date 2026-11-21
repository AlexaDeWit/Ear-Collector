-- The addon's own textures. Ear art lives in Media/Ears/ as 64x64 TGAs built from
-- the SVG sources in art/ears/ by scripts/build-art.sh.
local addonName, ns = ...

local Art = {}
ns.Art = Art

local ROOT = "Interface\\AddOns\\" .. addonName .. "\\Media\\"

-- Forever's race tokens (GetPlayerInfoByGUID's englishRace) to ear art files.
Art.EAR_FILES = {
	Human = "human",
	Dwarf = "dwarf",
	Gnome = "gnome",
	NightElf = "nightelf",
	Skyborne = "skyborne",
	Orc = "orc",
	Troll = "troll",
	Scourge = "undead",
	Tauren = "tauren",
}
Art.FALLBACK_EAR = "generic"

--- The ear art file name for a race; unknown races get the generic ear.
---@param race string?
---@return string
function Art.EarFile(race)
	return race and Art.EAR_FILES[race] or Art.FALLBACK_EAR
end

--- The texture path for a race's ear, for Texture:SetTexture or |T markup.
---@param race string?
---@return string
function Art.EarTexture(race)
	return ROOT .. "Ears\\" .. Art.EarFile(race)
end
