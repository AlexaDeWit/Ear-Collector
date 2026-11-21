-- The addon's own textures. Ear art lives in Media/Ears/ as 128x128 TGAs painted
-- by art/paint_ears.py: Media/Ears/<race>-<tone>.tga, plus generic.tga.
local addonName, ns = ...

local Art = {}
ns.Art = Art

local ROOT = "Interface\\AddOns\\" .. addonName .. "\\Media\\"

-- Forever's race tokens (GetPlayerInfoByGUID's englishRace) to ear art.
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

-- Skin tones painted per race (tauren: fur colours). Must match TONES in art/paint_ears.py.
Art.TONES = 4

--- A stable number from a string (djb2), so a player's tone never changes.
---@param text string
---@return integer
local function hash(text)
	local h = 5381
	for i = 1, #text do
		h = (h * 33 + text:byte(i)) % 2147483647
	end
	return h
end

--- Which skin tone a victim's ear is drawn in. The game doesn't expose skin
--- tone, so it's picked from the GUID: random across players, the same every
--- time for one player.
---@param guid string?
---@return integer tone 1..Art.TONES
function Art.Tone(guid)
	if type(guid) ~= "string" or guid == "" then
		return 1
	end
	return hash(guid) % Art.TONES + 1
end

--- The ear art file name for a race and victim; unknown races get the generic ear.
---@param race string?
---@param guid string?
---@return string
function Art.EarFile(race, guid)
	local base = race and Art.EAR_FILES[race]
	if not base then
		return Art.FALLBACK_EAR
	end
	return ("%s-%d"):format(base, Art.Tone(guid))
end

--- The texture path for a victim's ear, for Texture:SetTexture or |T markup.
---@param race string?
---@param guid string?
---@return string
function Art.EarTexture(race, guid)
	return ROOT .. "Ears\\" .. Art.EarFile(race, guid)
end
