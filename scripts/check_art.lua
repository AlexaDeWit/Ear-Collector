-- Check the ear textures against their SVG sources:
--   * every art/ears/*.svg has a Media/Ears/*.tga, and every texture has a source;
--   * each texture is the TGA form WoW loads: uncompressed, 32-bit with alpha, 64x64;
--   * Media/Ears/sources.sha256 matches the current SVGs, so a changed source
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

local function names(dir, ext)
	local set = {}
	for _, file in ipairs(lines(("ls %s 2>/dev/null"):format(dir))) do
		local name = file:match("^(.+)%." .. ext .. "$")
		if name then
			set[name] = true
		end
	end
	return set
end

local svgs, tgas = names("art/ears", "svg"), names("Media/Ears", "tga")
if next(svgs) == nil then
	err("art/ears", "no SVG sources found")
end
for name in pairs(svgs) do
	if not tgas[name] then
		err("Media/Ears/" .. name .. ".tga", "missing; run scripts/build-art.sh")
	end
end
for name in pairs(tgas) do
	if not svgs[name] then
		err("Media/Ears/" .. name .. ".tga", "has no source art/ears/" .. name .. ".svg")
	end
end

-- TGA header: byte 3 image type (2 = uncompressed true-color), bytes 13-16
-- width and height (little-endian), byte 17 bits per pixel, byte 18 low
-- nibble alpha bits.
for name in pairs(tgas) do
	local path = "Media/Ears/" .. name .. ".tga"
	local f = assert(io.open(path, "rb"))
	local header = f:read(18) or ""
	f:close()
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
		if width ~= 64 or height ~= 64 then
			err(path, ("is %dx%d; expected 64x64"):format(width, height))
		end
		if bpp ~= 32 or alphaBits ~= 8 then
			err(path, ("is %d-bit with %d alpha bits; expected 32-bit with 8"):format(bpp, alphaBits))
		end
	end
end

-- Sources changed since the last build?
local recorded = {}
local manifest = io.open("Media/Ears/sources.sha256", "r")
if not manifest then
	err("Media/Ears/sources.sha256", "missing; run scripts/build-art.sh")
else
	for line in manifest:lines() do
		local hash, file = line:match("^(%x+)%s+%*?(%S+)$")
		if hash then
			recorded[file] = hash
		end
	end
	manifest:close()
	for _, line in ipairs(lines("cd art/ears && sha256sum -- *.svg")) do
		local hash, file = line:match("^(%x+)%s+%*?(%S+)$")
		if hash and recorded[file] ~= hash then
			err("art/ears/" .. file, "changed since the textures were built; run scripts/build-art.sh")
		end
	end
end

print(("Art check: %d error(s)"):format(errors))
os.exit(errors == 0 and 0 or 1)
