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

-- "Interface\AddOns\EarCollector\Media\Ears\orc-2" -> "Media/Ears/orc-2.tga"
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

	it("has a texture for every Forever race in every skin tone", function()
		for _, race in ipairs(FOREVER_RACES) do
			local seen = {}
			for i = 1, 400 do
				local texture = Art.EarTexture(race, ("Player-4395-%08X"):format(i * 7919))
				seen[texture] = true
			end
			local count = 0
			for texture in pairs(seen) do
				count = count + 1
				assert.is_true(exists(onDisk(texture)), race .. " -> " .. onDisk(texture))
			end
			assert.are.equal(Art.TONES, count, race .. " should use all " .. Art.TONES .. " tones")
		end
	end)

	it("keeps a player's tone the same every time", function()
		local guid = "Player-4395-0B1C2D3E"
		local tone = Art.Tone(guid)
		for _ = 1, 5 do
			assert.are.equal(tone, Art.Tone(guid))
		end
		assert.are.equal(("orc-%d"):format(tone), Art.EarFile("Orc", guid))
	end)

	it("spreads players across tones", function()
		local counts = {}
		for i = 1, 1000 do
			local tone = Art.Tone(("Player-%d-%08X"):format(i % 7, i * 104729))
			counts[tone] = (counts[tone] or 0) + 1
		end
		for tone = 1, Art.TONES do
			assert.is_true((counts[tone] or 0) > 150, ("tone %d used %d times in 1000"):format(tone, counts[tone] or 0))
		end
	end)

	it("falls back to tone 1 without a GUID, and the generic ear for unknown races", function()
		assert.are.equal(1, Art.Tone(nil))
		assert.are.equal("human-1", Art.EarFile("Human", nil))
		assert.are.equal("generic", Art.EarFile("Pandaren", "Player-1-A"))
		assert.are.equal("generic", Art.EarFile(nil, nil))
		assert.is_true(exists(onDisk(Art.EarTexture(nil))))
	end)

	it("maps Scourge to the undead ear", function()
		assert.matches("\\Ears\\undead%-[1-4]$", Art.EarTexture("Scourge", "Player-1-A"))
	end)

	it("matches the tone count the painter uses", function()
		local file = assert(io.open("art/paint_ears.py"))
		local painter = file:read("*a")
		file:close()
		local human = painter:match('"human": %[(.-)%],')
		local _, tones = human:gsub("dict%(", "")
		assert.are.equal(Art.TONES, tones)
	end)

	it("points the minimap drawer icon at a texture that exists", function()
		local file = assert(io.open("EarCollector.toc"))
		local toc = file:read("*a")
		file:close()
		local icon = toc:match("## IconTexture: (%S+)")
		assert.is_true(exists(onDisk(icon)), icon)
	end)
end)
