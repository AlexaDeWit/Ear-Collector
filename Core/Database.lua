-- SavedVariables: create, upgrade, repair and fill defaults. Pure functions plus
-- one ADDON_LOADED handler, so specs can exercise migrations directly.
-- Saved data can be hand-edited, truncated by a crash or written by an older
-- version, so Migrate never assumes a field has the right type.
local addonName, ns = ...

local Database = {}
ns.Database = Database

Database.SCHEMA = 1

Database.DEFAULT_SETTINGS = {
	campWindow = 600, -- seconds; repeat kills of the same player inside it don't drop a new ear
	includeFreeForAll = true, -- free-for-all areas count as open world
	includeBattlefields = false, -- zone-wide battles (pvpType "combat") don't count by default
	announce = true, -- print a chat line when you collect an ear
	debug = false, -- print and log every PARTY_KILL decision (see /ears debug)
}

Database.DEBUG_LOG_SIZE = 100

local function tableOrNew(value)
	return type(value) == "table" and value or {}
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
			kept[#kept + 1] = ear
		end
	end
	return kept
end

--- Return a database table in the current schema, keeping everything usable already saved.
---@param saved any the SavedVariables value from disk, if any
---@return table
function Database.Migrate(saved)
	local db = tableOrNew(saved)
	if type(db.schema) ~= "number" then
		db.schema = Database.SCHEMA
	end
	db.ears = repairEars(tableOrNew(db.ears))
	db.stats = tableOrNew(db.stats)
	if type(db.stats.hiddenKills) ~= "number" then
		db.stats.hiddenKills = 0
	end
	if type(db.stats.unnamedHonorKills) ~= "number" then
		db.stats.unnamedHonorKills = 0
	end
	db.settings = tableOrNew(db.settings)
	for key, value in pairs(Database.DEFAULT_SETTINGS) do
		if type(db.settings[key]) ~= type(value) then
			db.settings[key] = value
		end
	end
	db.debugLog = tableOrNew(db.debugLog)
	db.errors = tableOrNew(db.errors)
	return db
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
	EarCollectorDB = Database.Migrate(EarCollectorDB)
	ns.db = EarCollectorDB
	ns.Errors.Flush()
end)
