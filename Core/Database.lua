-- Saved data: EarCollectorDB (account: settings, ui, logs) and EarCollectorCharDB
-- (per character: ears, deaths, stats). On load, numbered steps bring each up to
-- the current schema, then a repair fixes damage, because files can be old,
-- hand-edited or truncated. ns.db's fields ARE the saved tables: change them in
-- place, never reassign one. The rules for changing what's saved are in
-- docs/architecture.md, "Saved data".
local addonName, ns = ...

local Database = {}
ns.Database = Database

-- 1: ears account-wide (before v1.0). 2: ears, deaths and stats per character.
-- 3: every ear keeps how it was graded.
Database.SCHEMA = 3

Database.DEFAULT_SETTINGS = {
	campWindow = 600, -- seconds; repeat kills of the same player inside it don't drop a new ear
	includeFreeForAll = true, -- free-for-all areas count as open world
	includeBattlefields = false, -- zone-wide battles (pvpType "combat") don't count by default
	announce = true, -- print a chat line when you collect an ear
	debug = false, -- print and log each kill, honorable kill and death decision (see /ears debug)
	openWithBags = true, -- the pouch opens and closes with your bags
	toast = true, -- show a pop-up when you collect an ear
	toastSound = true, -- and play a loot sound with it
	toastMinQuality = 0, -- the lowest grade that gets a pop-up
}

Database.DEBUG_LOG_SIZE = 300

local function tableOrNew(value)
	return type(value) == "table" and value or {}
end

-- Optional fields and their types. A wrong-typed one (hand-edited, or from a
-- bug) is dropped, so display code that formats them can't throw.
local OPTIONAL = {
	surname = "string",
	realm = "string",
	class = "string",
	className = "string",
	race = "string",
	raceName = "string",
	sex = "number",
	level = "number",
	yourLevel = "number",
	by = "string",
	killer = "string",
	mapID = "number",
	zone = "string",
	subzone = "string",
	spell = "string",
	vengeance = "number",
}

local function dropWrongTypes(record)
	for key, kind in pairs(OPTIONAL) do
		if record[key] ~= nil and type(record[key]) ~= kind then
			record[key] = nil
		end
	end
end

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < 1e9
end

-- An ear's saved grading (Appraisal.Record and FightFacts' facts): known fields
-- of the wrong type are dropped. Fields and band names it doesn't know are kept,
-- because a newer version may have saved them.
local FIGHT_NUMBERS = {
	"enemies",
	"allies",
	"secs",
	"taken",
	"sideTaken",
	"healed",
	"toughness",
	"size",
	"disrupts",
	"allyDeaths",
	"debt",
	"earlier",
	"score",
	"fightScore",
}
local function repairFight(fight)
	if type(fight) ~= "table" then
		return nil
	end
	fight.read = fight.read == true
	fight.died = fight.died == true or nil
	for _, key in ipairs(FIGHT_NUMBERS) do
		if not finite(fight[key]) then
			fight[key] = nil
		end
	end
	local why = {}
	for _, band in ipairs(type(fight.why) == "table" and fight.why or {}) do
		if type(band) == "string" then
			why[#why + 1] = band
		end
	end
	fight.why = why
	if fight.points ~= nil then
		local points = {}
		for band, value in pairs(type(fight.points) == "table" and fight.points or {}) do
			if type(band) == "string" and finite(value) then
				points[band] = value
			end
		end
		fight.points = points
	end
	if type(fight.rule) ~= "string" then
		fight.rule = nil
	end
	return fight
end

-- Keep only ears with the fields the rest of the addon relies on.
local function repairEars(ears)
	local kept = {}
	for _, ear in ipairs(ears) do
		if type(ear) == "table" and type(ear.guid) == "string" and type(ear.at) == "number" then
			if type(ear.name) ~= "string" then
				ear.name = "Unknown"
			end
			if type(ear.lastAt) ~= "number" then
				ear.lastAt = ear.at
			end
			if type(ear.camped) ~= "number" then
				ear.camped = 0
			end
			if type(ear.quality) ~= "number" or not ns.QUALITY[ear.quality] then
				ear.quality = 2
			end
			ear.pending = nil -- its fight can't be read after a reload: it keeps its grade
			ear.fight = repairFight(ear.fight)
			dropWrongTypes(ear)
			kept[#kept + 1] = ear
		end
	end
	return kept
end

-- Keep only deaths with the fields Rivals and vengeance rely on.
local function repairDeaths(deaths)
	local kept = {}
	for _, death in ipairs(deaths) do
		if type(death) == "table" and type(death.guid) == "string" and type(death.at) == "number" then
			if type(death.name) ~= "string" then
				death.name = "Unknown"
			end
			dropWrongTypes(death)
			kept[#kept + 1] = death
		end
	end
	return kept
end

Database.CHARACTER_KEYS = { "ears", "deaths", "stats" }

-- 3: ears graded by their fight get each band's points and the rule that set the
-- grade. Older ears, graded by the level colour alone (or Vengeance), get the
-- record that grading saves now, when it gives the grade they have.
local function gradingRecords(db)
	local Appraisal = ns.Appraisal
	for _, ear in ipairs(type(db.ears) == "table" and db.ears or {}) do
		local fight = type(ear) == "table" and type(ear.quality) == "number" and ear.fight
		if type(fight) == "table" and fight.points == nil then
			fight.points = {}
			for _, band in ipairs(type(fight.why) == "table" and fight.why or {}) do
				if type(band) == "string" then
					fight.points[band] = Appraisal.Points(band, fight.debt, fight.earlier)
				end
			end
			local owed = type(fight.debt) == "number" and fight.debt >= ns.Deaths.VENGEANCE
			fight.rule = (ear.vengeance or owed) and "vengeance" or ear.quality == 0 and "grey" or nil
		elseif fight == nil then
			local kill = { level = not ear.vengeance and ear.quality or nil, debt = ear.vengeance }
			local result = Appraisal.Appraise(kill)
			if result.quality == ear.quality then
				ear.fight = Appraisal.Record(kill, result)
			end
		end
	end
end

--- The steps that change what's saved, by the schema each brings a table to.
--- Each gets a copy of the table at the schema before it. Rules: docs/architecture.md.
Database.STEPS = {
	account = {},
	character = { [3] = gradingRecords },
}

local function copy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = copy(v)
	end
	return out
end

--- Bring a saved table up to the current schema. The steps it hasn't had run in
--- order on a copy, which replaces it only if every step finishes; otherwise it
--- stays as it was, and the steps run again next load. A table saved by a newer
--- version is left at its schema, with everything in it.
---@param db table
---@param steps table<integer, fun(db: table)>
---@param first integer the schema of a table saved without one
---@return table
local function upgrade(db, steps, first)
	local schema = finite(db.schema) and db.schema or first
	if schema > Database.SCHEMA then
		Database.newer = true
		return db
	end
	local due = false
	for n = schema + 1, Database.SCHEMA do
		due = due or steps[n] ~= nil
	end
	if not due then
		db.schema = Database.SCHEMA
		return db
	end
	local ok, upgraded = ns.Errors.Call("saved data", function()
		local new = copy(db)
		for n = schema + 1, Database.SCHEMA do
			if steps[n] then
				steps[n](new)
			end
		end
		new.schema = Database.SCHEMA
		return new
	end)
	return ok and upgraded or db
end

--- The account-wide saved data (EarCollectorDB) in the current schema, keeping
--- everything usable already saved.
---@param saved any the SavedVariables value from disk, if any
---@return table
function Database.MigrateAccount(saved)
	local db = upgrade(tableOrNew(saved), Database.STEPS.account, 1)
	db.settings = tableOrNew(db.settings)
	for key, value in pairs(Database.DEFAULT_SETTINGS) do
		if type(db.settings[key]) ~= type(value) then
			db.settings[key] = value
		end
	end
	db.ui = tableOrNew(db.ui)
	if db.ui.pouch ~= nil and type(db.ui.pouch) ~= "table" then
		db.ui.pouch = nil
	end
	db.debugLog = tableOrNew(db.debugLog)
	db.errors = tableOrNew(db.errors)
	return db
end

--- This character's saved data (EarCollectorCharDB) in the current schema.
---@param saved any
---@return table
function Database.MigrateCharacter(saved)
	local db = upgrade(tableOrNew(saved), Database.STEPS.character, 2)
	db.ears = repairEars(tableOrNew(db.ears))
	db.deaths = repairDeaths(tableOrNew(db.deaths))
	db.stats = tableOrNew(db.stats)
	if type(db.stats.hiddenKills) ~= "number" then
		db.stats.hiddenKills = 0
	end
	if type(db.stats.unnamedHonorKills) ~= "number" then
		db.stats.unnamedHonorKills = 0
	end
	-- Grades hidden from the Ears tab: true at a grade's number, nothing else.
	db.hiddenGrades = tableOrNew(db.hiddenGrades)
	for grade, value in pairs(db.hiddenGrades) do
		if value ~= true or type(grade) ~= "number" or not ns.QUALITY[grade] then
			db.hiddenGrades[grade] = nil
		end
	end
	return db
end

--- Schema 1 saved ears account-wide: move them to the first character that loads
--- with none of its own. Nothing is dropped. It runs on every load, before the
--- Migrate functions, because the ears wait for such a character.
---@param account table
---@param character table
function Database.MoveShared(account, character)
	for _, key in ipairs(Database.CHARACTER_KEYS) do
		if account[key] ~= nil and character[key] == nil then
			character[key] = account[key]
			account[key] = nil
		end
	end
end

--- ns.db: the saved tables of both, in one table. Change them in place.
---@param account table migrated EarCollectorDB
---@param character table migrated EarCollectorCharDB
---@return table
function Database.View(account, character)
	return {
		settings = account.settings,
		ui = account.ui,
		debugLog = account.debugLog,
		errors = account.errors,
		ears = character.ears,
		deaths = character.deaths,
		stats = character.stats,
		hiddenGrades = character.hiddenGrades,
	}
end

--- Empty a saved list in place (reassigning it would stop it being saved).
---@param list table
function Database.Clear(list)
	for i = #list, 1, -1 do
		list[i] = nil
	end
end

--- Append to the bounded debug log used for in-game diagnosis and test fixtures.
---@param db table
---@param entry table
function Database.LogDebug(db, entry)
	local log = db.debugLog
	log[#log + 1] = entry
	while #log > Database.DEBUG_LOG_SIZE do
		table.remove(log, 1)
	end
end

ns.On("ADDON_LOADED", function(loadedName)
	if loadedName ~= addonName then
		return
	end
	local account = type(EarCollectorDB) == "table" and EarCollectorDB or {}
	local character = type(EarCollectorCharDB) == "table" and EarCollectorCharDB or {}
	Database.MoveShared(account, character)
	EarCollectorDB = Database.MigrateAccount(account)
	EarCollectorCharDB = Database.MigrateCharacter(character)
	ns.db = Database.View(EarCollectorDB, EarCollectorCharDB)
	ns.Errors.Flush()
	if Database.newer then
		ns.Errors.Say("Your ears were saved by a newer version of Ear Collector. This one leaves them as they are.")
	end
end)
