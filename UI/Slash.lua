-- /ears and /earcollector.
local _, ns = ...

local Chat, Ears, Errors = ns.Chat, ns.Ears, ns.Errors

local WEEK = 7 * 24 * 60 * 60

local function where(ear)
	if ear.subzone and ear.zone then
		return ("%s, %s"):format(ear.subzone, ear.zone)
	end
	return ear.zone or "unknown place"
end

local function describeEar(ear)
	local level = ear.level and ("level %d "):format(ear.level) or ""
	local camped = ear.camped > 0 and (" x%d"):format(ear.camped + 1) or ""
	return ("%s%s: %s%s, %s, %s"):format(
		Chat.EarName(ear),
		camped,
		level,
		ear.class or "unknown class",
		where(ear),
		date("%b %d %H:%M", ear.at)
	)
end

---@type table<string, fun(db: table, args: string)>
local commands = {}

function commands.summary(db)
	local total = #db.ears
	if total == 0 then
		Chat.Print("No ears yet. Kill an enemy player in the open world to collect one.")
		return
	end
	local week = Ears.CountSince(db, GetServerTime() - WEEK)
	Chat.Print(("%d ears collected, %d in the last 7 days."):format(total, week))
	Chat.Print("Latest: " .. describeEar(db.ears[total]))
end

function commands.recent(db, args)
	local n = math.min(tonumber(args) or 5, 50)
	local list = Ears.Recent(db, n)
	if #list == 0 then
		Chat.Print("No ears yet.")
		return
	end
	for _, ear in ipairs(list) do
		Chat.Print(describeEar(ear))
	end
end

function commands.debug(db)
	db.settings.debug = not db.settings.debug
	Chat.Print(
		db.settings.debug and "Debug on: every PARTY_KILL is printed and kept in EarCollectorDB.debugLog."
			or "Debug off."
	)
end

function commands.errors(db, args)
	if args == "clear" then
		db.errors = {}
		Chat.Print("Error log cleared.")
		return
	end
	if #db.errors == 0 then
		Chat.Print("No errors recorded.")
		return
	end
	Chat.Print(("%d error(s) recorded (newest last). Please include these in bug reports:"):format(#db.errors))
	for i = math.max(1, #db.errors - 4), #db.errors do
		local e = db.errors[i]
		Chat.Print(("%s in %s (%s): %s"):format(date("%b %d %H:%M", e.at), e.where, e.version, e.message))
	end
	Chat.Print("/ears errors clear empties the log.")
end

function commands.help()
	Chat.Print(("version %s"):format(ns.version))
	Chat.Print("/ears: totals and your latest ear")
	Chat.Print("/ears recent [n]: your newest ears (default 5)")
	Chat.Print("/ears debug: print every killing blow the addon sees, and why it did or didn't count")
	Chat.Print("/ears errors: errors the addon caught (it keeps running); /ears errors clear")
end

SLASH_EARCOLLECTOR1 = "/ears"
SLASH_EARCOLLECTOR2 = "/earcollector"
SlashCmdList.EARCOLLECTOR = Errors.Wrap("/ears", function(message)
	local db = ns.db
	if not db then
		return
	end
	local command, args = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
	command = command:lower()
	local handler = commands[command == "" and "summary" or command] or commands.help
	handler(db, args)
end)
