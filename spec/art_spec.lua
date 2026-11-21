local wow = require("spec.support.wow")

-- Forever's race tokens (GetPlayerInfoByGUID's englishRace), from Blizzard's
-- Camelot tutorial data.
local FOREVER_RACES = { "Human", "Dwarf", "Gnome", "NightElf", "Scourge", "Orc", "Troll", "Tauren", "Skyborne" }

local function exists(path)
	local f = io.open(path, "rb")
	if f then
		f:close()
		return true
	end
	return false
end

-- "Interface\AddOns\EarCollector\Media\Ears\orc" -> "Media/Ears/orc.tga"
local function onDisk(texture)
	local relative = texture:match("^Interface\\AddOns\\EarCollector\\(.+)$")
	assert(relative, "not an Ear Collector texture path: " .. texture)
	return relative:gsub("\\", "/") .. ".tga"
end

describe("ear art", function()
	local Art

	before_each(function()
		wow.reset()
		Art = wow.loadAddon("EarCollector.toc").Art
	end)

	it("has an ear texture for every Forever race", function()
		for _, race in ipairs(FOREVER_RACES) do
			local file = onDisk(Art.EarTexture(race))
			assert.is_true(exists(file), race .. " -> " .. file)
			assert.are_not.equal(Art.FALLBACK_EAR, Art.EarFile(race), race .. " should have its own ear")
		end
	end)

	it("gives unknown and missing races the generic ear", function()
		assert.are.equal("generic", Art.EarFile("Pandaren"))
		assert.are.equal("generic", Art.EarFile(nil))
		assert.is_true(exists(onDisk(Art.EarTexture(nil))))
	end)

	it("maps Scourge to the undead ear", function()
		assert.are.equal("Interface\\AddOns\\EarCollector\\Media\\Ears\\undead", Art.EarTexture("Scourge"))
	end)

	it("points the minimap drawer icon at a texture that exists", function()
		local file = assert(io.open("EarCollector.toc"))
		local toc = file:read("*a")
		file:close()
		local icon = toc:match("## IconTexture: (%S+)")
		assert.is_true(exists(onDisk(icon)), icon)
	end)
end)
