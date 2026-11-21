-- The Ledger: totals over your ears, for the pouch's Ledger tab. Pure: it takes
-- the ear list and the time, so specs call it directly. One pass over the ears,
-- run only while the Ledger tab is showing.
local _, ns = ...

local Ledger = {}
ns.Ledger = Ledger

Ledger.TOP_ZONES = 5

-- { key -> count } as a list of { [keyName] = key, count = n }, biggest first,
-- ties in name order so the display is stable.
local function ranked(counts, keyName)
	local list = {}
	for key, count in pairs(counts) do
		list[#list + 1] = { [keyName] = key, count = count }
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a[keyName] < b[keyName]
	end)
	return list
end

---@class EarCollector.LedgerSummary
---@field ears integer
---@field kills integer ears plus repeat kills inside the camping window
---@field assists integer
---@field week integer ears taken in the last 7 days
---@field players integer different players you have ears from
---@field deaths integer your recorded deaths to enemy players
---@field byQuality table<integer, integer> grade -> ears, for every grade in ns.QUALITY
---@field byClass { class: string, name: string?, count: integer }[] biggest first; class "UNKNOWN" when not known
---@field zones { zone: string, count: integer }[] the top Ledger.TOP_ZONES

--- Totals over `ears` (and `deaths`). Tolerates missing optional fields (class, zone, camped).
---@param ears table[]
---@param now number server time in seconds
---@param deaths table[]?
---@return EarCollector.LedgerSummary
function Ledger.Summarize(ears, now, deaths)
	local summary = {
		ears = #ears,
		kills = 0,
		assists = 0,
		week = 0,
		players = 0,
		deaths = deaths and #deaths or 0,
		byQuality = {},
	}
	for grade in pairs(ns.QUALITY) do
		summary.byQuality[grade] = 0
	end
	local classes, classNames, zones, seen = {}, {}, {}, {}
	local weekStart = now - ns.Ears.WEEK
	for _, ear in ipairs(ears) do
		summary.kills = summary.kills + 1 + (type(ear.camped) == "number" and ear.camped or 0)
		if ear.by == "assist" then
			summary.assists = summary.assists + 1
		end
		if ear.at >= weekStart then
			summary.week = summary.week + 1
		end
		local grade = summary.byQuality[ear.quality] and ear.quality or 2
		summary.byQuality[grade] = summary.byQuality[grade] + 1

		local class = type(ear.class) == "string" and ear.class or "UNKNOWN"
		classes[class] = (classes[class] or 0) + 1
		if type(ear.className) == "string" then
			classNames[class] = ear.className
		end
		if type(ear.zone) == "string" then
			zones[ear.zone] = (zones[ear.zone] or 0) + 1
		end
		if not seen[ear.guid] then
			seen[ear.guid] = true
			summary.players = summary.players + 1
		end
	end

	summary.byClass = ranked(classes, "class")
	for _, entry in ipairs(summary.byClass) do
		entry.name = classNames[entry.class]
	end
	local allZones = ranked(zones, "zone")
	summary.zones = {}
	for i = 1, math.min(#allZones, Ledger.TOP_ZONES) do
		summary.zones[i] = allZones[i]
	end
	return summary
end
