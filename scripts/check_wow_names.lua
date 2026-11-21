-- Check event and script-handler names used in addon code.
-- lua-language-server cannot catch these: the annotations type them as
-- `string | "KNOWN_NAME" | ...`, so a typo like "PARTY_KIL" is accepted and the
-- handler silently never fires in game.
--
-- Events are checked against Blizzard's generated API docs for the WoW Forever
-- client (authoritative for the game version we ship for). Script handlers
-- (OnEvent, OnUpdate, ...) are checked against Ketho's annotations.
--
-- Usage: lua5.1 scripts/check_wow_names.lua <Annotations/Core dir> \
--          <Blizzard_APIDocumentationGenerated dir> <file.lua>...
local core, blizzardDocs = arg[1], arg[2]
if not core or not blizzardDocs then
	io.stderr:write("usage: check_wow_names.lua <Annotations/Core> <Blizzard_APIDocumentationGenerated> <files...>\n")
	os.exit(2)
end

local function readLines(path)
	local f = io.open(path, "r")
	if not f then
		io.stderr:write(("check_wow_names: cannot read %s\n"):format(path))
		os.exit(2)
	end
	local lines = {}
	for line in f:lines() do
		lines[#lines + 1] = line
	end
	f:close()
	return lines
end

-- Every "QUOTED_NAME" in a file (Ketho's Data/Event.lua and ScriptType.lua are lists of literals).
local function literals(path, into)
	for _, line in ipairs(readLines(path)) do
		for name in line:gmatch('"([%w_]+)"') do
			into[name] = true
		end
	end
	return into
end

-- Every `LiteralName = "EVENT"` in Blizzard's documentation tables.
local function blizzardEvents(dir)
	local events, count = {}, 0
	local p = assert(io.popen(("ls %q"):format(dir)))
	for file in p:lines() do
		if file:find("%.lua$") then
			for _, line in ipairs(readLines(dir .. "/" .. file)) do
				local name = line:match('LiteralName%s*=%s*"([%w_]+)"')
				if name then
					events[name] = true
					count = count + 1
				end
			end
		end
	end
	p:close()
	if count == 0 then
		io.stderr:write(("check_wow_names: no events found in %s\n"):format(dir))
		os.exit(2)
	end
	return events
end

local events = blizzardEvents(blizzardDocs)
local retailOnly = literals(core .. "/Data/Event.lua", {})
local scripts = literals(core .. "/Widget/UIType/ScriptType.lua", {})

local function distance(a, b) -- Levenshtein, for "did you mean"
	local prev = {}
	for j = 0, #b do
		prev[j] = j
	end
	for i = 1, #a do
		local cur = { [0] = i }
		for j = 1, #b do
			local cost = a:sub(i, i) == b:sub(j, j) and 0 or 1
			cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
		end
		prev = cur
	end
	return prev[#b]
end
local function suggest(name, known)
	local best, bestD = nil, 3
	for k in pairs(known) do
		local d = distance(name, k)
		if d < bestD then
			best, bestD = k, d
		end
	end
	return best and (" (did you mean %q?)"):format(best) or ""
end

local function eventProblem(name)
	if events[name] then
		return nil
	end
	if retailOnly[name] then
		return ("event %q is not in WoW Forever's API docs (Ketho's Retail annotations list it)"):format(name)
	end
	return ("unknown event %q%s"):format(name, suggest(name, events))
end
local function scriptProblem(name)
	if scripts[name] then
		return nil
	end
	return ("unknown script handler %q%s"):format(name, suggest(name, scripts))
end

local checks = {
	{ "Register[%a]*Event%s*%(%s*[\"']([%w_]+)[\"']", eventProblem },
	{ "UnregisterEvent%s*%(%s*[\"']([%w_]+)[\"']", eventProblem },
	{ "event%s*==%s*[\"']([%w_]+)[\"']", eventProblem },
	{ "[\"']([%w_]+)[\"']%s*==%s*event", eventProblem },
	{ "ns%.On%s*%(%s*[\"']([%w_]+)[\"']", eventProblem }, -- Core/Events.lua's dispatcher
	{ "SetScript%s*%(%s*[\"']([%w_]+)[\"']", scriptProblem },
	{ "HookScript%s*%(%s*[\"']([%w_]+)[\"']", scriptProblem },
}

local problems = 0
for i = 3, #arg do
	for n, line in ipairs(readLines(arg[i])) do
		for _, c in ipairs(checks) do
			for name in line:gmatch(c[1]) do
				local msg = c[2](name)
				if msg then
					problems = problems + 1
					print(("%s:%d: %s"):format(arg[i], n, msg))
				end
			end
		end
	end
end
os.exit(problems == 0 and 0 or 1)
