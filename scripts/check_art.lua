-- Check the ear textures against the painter that makes them (art/paint_ears.py):
--   * Media/Ears/manifest.txt lists every texture, and the folder holds no others;
--   * each texture is the TGA form WoW loads: uncompressed, 32-bit with alpha, at
--     the size the manifest records;
--   * the painter's hash matches the manifest, so a change to art/paint_ears.py
--     that wasn't rebuilt with scripts/build-art.sh fails here.
-- Usage: lua5.1 scripts/check_art.lua
local errors = 0
local function err(where, msg)
	errors = errors + 1
	print(("%s: error: %s"):format(where, msg))
end

local function lines(cmd)
	local p = assert(io.popen(cmd))
	local out = {}
	for line in p:lines() do
		out[#out + 1] = line
	end
	p:close()
	return out
end

local MANIFEST = "Media/Ears/manifest.txt"
local size, sourceHash, sourcePath = nil, nil, nil
local listed = {}
local f = io.open(MANIFEST, "r")
if not f then
	err(MANIFEST, "missing; run scripts/build-art.sh")
else
	for line in f:lines() do
		local key, rest = line:match("^(%S+)%s+(.+)$")
		if key == "size" then
			size = tonumber(rest)
		elseif key == "source" then
			sourceHash, sourcePath = rest:match("^(%x+)%s+(%S+)$")
		elseif key == "texture" then
			listed[rest] = true
		end
	end
	f:close()
end

if sourcePath then
	local current = lines(("sha256sum %q"):format(sourcePath))[1]
	current = current and current:match("^(%x+)")
	if not current then
		err(sourcePath, "missing (the manifest names it as the source of the art)")
	elseif current ~= sourceHash then
		err(sourcePath, "changed since the textures were built; run scripts/build-art.sh")
	end
elseif f then
	err(MANIFEST, "has no `source` line; run scripts/build-art.sh")
end

local present = {}
for _, file in ipairs(lines("ls Media/Ears 2>/dev/null")) do
	local name = file:match("^(.+)%.tga$")
	if name then
		present[name] = true
		if not listed[name] then
			err("Media/Ears/" .. file, "not in the manifest; run scripts/build-art.sh")
		end
	end
end
for name in pairs(listed) do
	if not present[name] then
		err("Media/Ears/" .. name .. ".tga", "missing; run scripts/build-art.sh")
	end
end

-- TGA header: byte 3 image type (2 = uncompressed true-color), bytes 13-16
-- width and height (little-endian), byte 17 bits per pixel, byte 18 low
-- nibble alpha bits.
for name in pairs(present) do
	local path = "Media/Ears/" .. name .. ".tga"
	local tga = assert(io.open(path, "rb"))
	local header = tga:read(18) or ""
	tga:close()
	if #header < 18 then
		err(path, "too short to be a TGA")
	else
		local imageType = header:byte(3)
		local width = header:byte(13) + header:byte(14) * 256
		local height = header:byte(15) + header:byte(16) * 256
		local bpp, alphaBits = header:byte(17), header:byte(18) % 16
		if imageType ~= 2 then
			err(path, ("image type %d; expected 2 (uncompressed true-color)"):format(imageType))
		end
		if width ~= height or (size and width ~= size) or width % 2 ~= 0 then
			err(path, ("is %dx%d; expected %sx%s"):format(width, height, size or "?", size or "?"))
		end
		if bpp ~= 32 or alphaBits ~= 8 then
			err(path, ("is %d-bit with %d alpha bits; expected 32-bit with 8"):format(bpp, alphaBits))
		end
	end
end

print(("Art check: %d error(s)"):format(errors))
os.exit(errors == 0 and 0 or 1)
