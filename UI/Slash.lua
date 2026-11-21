-- /ears and /earcollector.
local _, ns = ...

local Chat, Ears, Errors = ns.Chat, ns.Ears, ns.Errors

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

function commands.pouch()
	ns.Pouch.Toggle()
end

function commands.options()
	ns.Options.Open()
end
commands.config = commands.options
commands.settings = commands.options

function commands.bags(db, args)
	if args == "on" or args == "off" then
		db.settings.openWithBags = args == "on"
	end
	Chat.Print(
		db.settings.openWithBags and "The pouch opens with your bags. /ears bags off to stop."
			or "The pouch doesn't open with your bags. /ears bags on to change."
	)
end

local function toggle(db, key, args, onText, offText)
	if args == "on" or args == "off" then
		db.settings[key] = args == "on"
	end
	Chat.Print(db.settings[key] and onText or offText)
end

function commands.toast(db, args)
	toggle(
		db,
		"toast",
		args,
		"Toasts are on. /ears toast off to stop them.",
		"Toasts are off. /ears toast on to bring them back."
	)
end

function commands.sound(db, args)
	toggle(
		db,
		"toastSound",
		args,
		"Toast sounds are on. /ears sound off to mute them.",
		"Toast sounds are off. /ears sound on to hear them."
	)
end

function commands.stats(db)
	local total = #db.ears
	if total == 0 then
		Chat.Print("No ears yet. Kill an enemy player in the open world to collect one.")
		return
	end
	local week = Ears.CountSince(db, GetServerTime() - Ears.WEEK)
	local assists = Ears.CountAssists(db.ears)
	Chat.Print(("%d ears collected (%d assists), %d in the last 7 days."):format(total, assists, week))
	Chat.Print("Latest: " .. describeEar(db.ears[total]))
	local hidden, unnamed = db.stats.hiddenKills, db.stats.unnamedHonorKills
	if hidden > 0 then
		Chat.Print(("%d kill(s) the game hid from the addon (no ear)."):format(hidden))
	end
	if unnamed > 0 then
		Chat.Print(("%d honorable kill(s) not tied to one victim (no assist ear)."):format(unnamed))
	end
end

function commands.recent(db, args)
	local n = math.max(1, math.min(math.floor(tonumber(args) or 5), 50))
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
	if not db.settings.debug then
		Chat.Print("Debug off.")
		return
	end
	Chat.Print("Debug on: kills, honorable kills and deaths are printed and saved in EarCollectorDB.debugLog.")
	Chat.Print("It stays on, across /reload and logout, until you type /ears debug again.")
end

function commands.errors(db, args)
	if args == "clear" then
		ns.Database.Clear(db.errors)
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
		if type(e) == "table" then -- the saved log may be hand-edited
			local when = type(e.at) == "number" and date("%b %d %H:%M", e.at) or "?"
			Chat.Print(("%s in %s (%s): %s"):format(when, tostring(e.where), tostring(e.version), tostring(e.message)))
		end
	end
	Chat.Print("/ears errors clear empties the log.")
end

function commands.help()
	Chat.Print(("version %s"):format(ns.version))
	Chat.Print("/ears: open or close your Ear Pouch (also: minimap addon drawer, a key binding, your bags)")
	Chat.Print("/ears options: open the options (also: Options > AddOns, or right-click in the minimap drawer)")
	Chat.Print("/ears stats: totals and your latest ear")
	Chat.Print("/ears recent [n]: your newest ears (default 5)")
	Chat.Print("/ears debug: print and save each kill, honorable kill and death, and why it did or didn't count")
	Chat.Print("/ears bags on|off: open the pouch with your bags")
	Chat.Print("/ears toast on|off, /ears sound on|off: the pop-up when you collect an ear, and its sound")
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
	local key = command == "" and "pouch" or command
	local handler = commands[key]
	if not handler or key == "errors" or key == "help" then
		-- Never switched off: /ears errors is how the player reads the error log.
		(handler or commands.help)(db, args)
		return
	end
	-- Each command has its own error name, so one failing command can't switch
	-- off the others.
	Errors.Call("/ears " .. key, handler, db, args)
end)
