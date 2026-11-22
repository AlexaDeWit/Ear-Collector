-- Saved data: EarCollectorDB (account: settings, ui, logs) and EarCollectorCharDB
-- (per character: ears, deaths, stats), repaired on load because they can be
-- old, hand-edited or truncated. ns.db's fields ARE the saved tables: change them
-- in place, never reassign one.
local addonName, ns = ...

local Database = {}
ns.Database = Database

Database.SCHEMA = 2 -- 2: ears, deaths and stats moved to EarCollectorCharDB

Database.DEFAULT_SETTINGS = {
	campWindow = 600, -- seconds; repeat kills of the same player inside it don't drop a new ear
	includeFreeForAll = true, -- free-for-all areas count as open world
	includeBattlefields = false, -- zone-wide battles (pvpType "combat") don't count by default
	announce = true, -- print a chat line when you collect an ear
	debug = false, -- print and log each kill, honorable kill and death decision (see /ears debug)
	openWithBags = true, -- the pouch opens and closes with your bags
	toast = true, -- pop up a toast when you collect an ear
	toastSound = true, -- and play a loot sound with it
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

--- The account-wide saved data (EarCollectorDB) in the current schema, keeping
--- everything usable already saved.
---@param saved any the SavedVariables value from disk, if any
---@return table
function Database.MigrateAccount(saved)
	local db = tableOrNew(saved)
	db.schema = Database.SCHEMA
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
	local db = tableOrNew(saved)
	db.schema = Database.SCHEMA
	db.ears = repairEars(tableOrNew(db.ears))
	db.deaths = repairDeaths(tableOrNew(db.deaths))
	db.stats = tableOrNew(db.stats)
	if type(db.stats.hiddenKills) ~= "number" then
		db.stats.hiddenKills = 0
	end
	if type(db.stats.unnamedHonorKills) ~= "number" then
		db.stats.unnamedHonorKills = 0
	end
	return db
end

--- Schema 1 saved ears account-wide: move them to the first character that loads
--- with none of its own. Nothing is dropped. Runs before the Migrate functions.
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
end)
