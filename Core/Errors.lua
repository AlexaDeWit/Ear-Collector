-- Error containment: every entry point runs through Errors.Call, which keeps an
-- error inside the addon, logs it (bounded) for /ears errors, tells the player
-- once, and switches a handler off after MAX_PER_HANDLER errors until /reload.
-- With /ears debug on, errors also reach the game's handler, for BugSack.
local _, ns = ...

local Errors = {}
ns.Errors = Errors

Errors.MAX_PER_HANDLER = 3
Errors.LOG_SIZE = 20

local counts = {} -- handler name -> errors this session
local disabled = {} -- handler name -> true once switched off
local pending = {} -- errors raised before SavedVariables loaded
local warned = false

local function say(message)
	print("|cffc8402f[Ear Collector]|r " .. message)
end

local function capture(err)
	-- debugstack is WoW's stack-trace helper; the specs' plain Lua has none.
	local stack = debugstack and debugstack(2, 8, 0) or nil
	return { message = tostring(err), stack = stack }
end

local function store(entry)
	local db = ns.db
	if not db or type(db.errors) ~= "table" then
		pending[#pending + 1] = entry
		return
	end
	db.errors[#db.errors + 1] = entry
	while #db.errors > Errors.LOG_SIZE do
		table.remove(db.errors, 1)
	end
end

--- Record an error from `name` and decide whether to switch it off.
---@param name string the entry point that failed, e.g. "PARTY_KILL" or "/ears"
---@param failure { message: string, stack: string? }
function Errors.Report(name, failure)
	counts[name] = (counts[name] or 0) + 1
	store({
		at = GetServerTime(),
		where = name,
		message = failure.message,
		stack = failure.stack,
		version = ns.version,
	})
	if ns.db and ns.db.settings and ns.db.settings.debug then
		local handler = geterrorhandler and geterrorhandler()
		if handler then
			pcall(handler, failure.message)
		end
	end
	if counts[name] >= Errors.MAX_PER_HANDLER and not disabled[name] then
		disabled[name] = true
		say(("Turned off %s after repeated errors. /reload to try again; /ears errors for details."):format(name))
	elseif not warned then
		say("Hit an error and kept going. /ears errors for details.")
	end
	warned = true
end

--- Run fn(...) so that no error escapes. Returns true plus fn's results, or false.
---@param name string
---@param fn function
---@return boolean ok
function Errors.Call(name, fn, ...)
	if disabled[name] then
		return false
	end
	local n, args = select("#", ...), { ... }
	local results = { xpcall(function()
		return fn(unpack(args, 1, n))
	end, capture) }
	if not results[1] then
		-- The safety net must not throw either: if reporting fails, stay quiet.
		pcall(Errors.Report, name, results[2])
		return false
	end
	return unpack(results)
end

--- fn wrapped with Errors.Call, for slash commands and other callbacks the game invokes.
---@param name string
---@param fn function
---@return function
function Errors.Wrap(name, fn)
	return function(...)
		return Errors.Call(name, fn, ...)
	end
end

--- Move errors raised before SavedVariables loaded into the database.
function Errors.Flush()
	local queued = pending
	pending = {}
	for _, entry in ipairs(queued) do
		store(entry)
	end
end

---@param name string
---@return boolean
function Errors.IsDisabled(name)
	return disabled[name] == true
end

--- Errors this session, per entry point.
---@return table<string, integer>
function Errors.SessionCounts()
	return counts
end
