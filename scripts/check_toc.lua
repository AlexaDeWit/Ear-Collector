-- Validate WoW .toc files: required fields, Interface format, listed files exist
-- (case-sensitively), no duplicates, and no .lua/.xml file is left unloaded.
-- Usage: lua5.1 scripts/check_toc.lua [addon_root]
local root = (arg[1] or "."):gsub("/$", "")
local errors, warnings = 0, 0
local function err(where, msg)
	errors = errors + 1
	print(("%s: error: %s"):format(where, msg))
end
local function warn(where, msg)
	warnings = warnings + 1
	print(("%s: warning: %s"):format(where, msg))
end

local function sh(cmd)
	local p = assert(io.popen(cmd))
	local out = {}
	for line in p:lines() do
		out[#out + 1] = line
	end
	p:close()
	return out
end
local function exists(path)
	local f = io.open(path, "rb")
	if f then
		f:close()
		return true
	end
	return false
end
local function readAll(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

-- Directories that are not part of the shipped addon.
local IGNORE = "-path '*/.git' -o -path '*/.cache' -o -path '*/.luarocks' -o -path '*/spec' "
	.. "-o -path '*/scripts' -o -path '*/types' -o -path '*/.github' -o -path '*/.claude' -o -path '*/.release'"
local tocs = sh(("find %q -maxdepth 1 -name '*.toc' | sort"):format(root))
if #tocs == 0 then
	err(root, "no .toc file found")
end

local loaded = {} -- relative path -> true
local function markXmlIncludes(rel, seen)
	seen = seen or {}
	if seen[rel] then
		return
	end
	seen[rel] = true
	local text = readAll(root .. "/" .. rel)
	if not text then
		return
	end
	local dir = rel:match("^(.*)/[^/]+$")
	for tag, file in text:gmatch('<(%a+)[^>]-%sfile%s*=%s*"([^"]+)"') do
		if tag == "Script" or tag == "Include" then
			local target = file:gsub("\\", "/")
			if dir then
				target = dir .. "/" .. target
			end
			if not exists(root .. "/" .. target) then
				err(rel, ("<%s file=%q>: file not found (paths are case-sensitive)"):format(tag, file))
			else
				loaded[target] = true
				if target:find("%.xml$") then
					markXmlIncludes(target, seen)
				end
			end
		end
	end
end

for _, toc in ipairs(tocs) do
	local name = toc:match("([^/]+)$")
	local fields, files, n = {}, {}, 0
	for line in io.lines(toc) do
		n = n + 1
		local where = ("%s:%d"):format(name, n)
		line = line:gsub("^\239\187\191", ""):gsub("\r$", "")
		local key, value = line:match("^##%s*([^:]+):%s*(.-)%s*$")
		if key then
			fields[key] = value
		elseif line:find("^%s*#") or line:find("^%s*$") then -- luacheck: ignore 542
			-- comment or blank
		else
			local file = line:match("^%s*(.-)%s*$"):gsub("%s+%[.-%]$", "") -- drop trailing [AllowLoad...] directives
			if file:find("%[") then
				warn(where, ("%q uses a TOC variable; not checked"):format(file))
			elseif not file:find("%.lua$") and not file:find("%.xml$") then
				err(where, ("%q: only .lua and .xml files can be listed"):format(file))
			else
				local rel = file:gsub("\\", "/")
				if files[rel] then
					err(where, ("%q is listed twice"):format(file))
				end
				files[rel] = true
				if not exists(root .. "/" .. rel) then
					err(where, ("%q: file not found (paths are case-sensitive)"):format(file))
				else
					loaded[rel] = true
					if rel:find("%.xml$") then
						markXmlIncludes(rel)
					end
				end
			end
		end
	end
	local interface = fields["Interface"]
	if not interface then
		err(name, "missing ## Interface")
	else
		local values = {}
		for v in (interface .. ","):gmatch("%s*([^,]-)%s*,") do
			if not v:find("^%d%d%d%d%d%d?$") then
				err(name, ("## Interface value %q is not a 5-6 digit number"):format(v))
			end
			values[v] = true
		end
		-- The client build we target is pinned in scripts/setup-tools.sh; its
		-- version.txt (e.g. 1.60.1.71037) gives the Interface number (16001).
		local build = readAll(root .. "/.cache/wow-ui-source/version.txt")
		local major, minor, patch = (build or ""):match("^(%d+)%.(%d+)%.(%d+)")
		if major then
			local expected = tostring(tonumber(major) * 10000 + tonumber(minor) * 100 + tonumber(patch))
			if not values[expected] then
				err(
					name,
					("## Interface %s does not include %s, the pinned WoW Forever build %s"):format(
						interface,
						expected,
						build:match("^%S+")
					)
				)
			end
		end
	end
	if not fields["Title"] then
		err(name, "missing ## Title")
	end
	for _, key in ipairs({ "SavedVariables", "SavedVariablesPerCharacter" }) do
		for sv in (fields[key] or ""):gmatch("[^,%s]+") do
			if not sv:find("^[%a_][%w_]*$") then
				err(name, ("%s: %q is not a valid Lua identifier"):format(key, sv))
			end
			local rc = readAll(root .. "/.luacheckrc")
			if rc and not rc:find("[\"']" .. sv .. "[\"']") then
				warn(name, ("%s %q is not declared in .luacheckrc globals"):format(key, sv))
			end
		end
	end
end

local findAll = ("cd %q && find . \\( %s \\) -prune -o -type f \\( -name '*.lua' -o -name '*.xml' \\) -print"):format(
	root,
	IGNORE
)
for _, f in ipairs(sh(findAll .. " | sed 's|^\\./||' | sort")) do
	-- Bindings.xml is loaded by the client itself, never through the TOC.
	if not loaded[f] and f ~= ".luacheckrc" and f ~= "Bindings.xml" and not f:find("^%.") then
		warn(f, "not loaded by any .toc or XML <Script>/<Include>")
	end
end

print(("TOC check: %d error(s), %d warning(s)"):format(errors, warnings))
os.exit(errors == 0 and 0 or 1)
