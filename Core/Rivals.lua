-- Rivals: everyone you have taken ears from, for the pouch's Rivals tab. Pure:
-- it takes the ear list, so specs call it directly. Players are keyed by GUID,
-- never by name (Forever names aren't unique without the surname).
local _, ns = ...

local Rivals = {}
ns.Rivals = Rivals

Rivals.PREY = 3 -- kills of one player that mark them as your prey

---@class EarCollector.Rival
---@field guid string
---@field name string from their latest ear
---@field latest table their latest ear (for name, class, race and the tooltip)
---@field ears integer
---@field kills integer ears plus repeat kills inside the camping window
---@field firstAt number
---@field lastAt number the last time you killed them
---@field prey boolean

--- One row per player you have ears from: most kills first, then most recent.
---@param ears table[]
---@return EarCollector.Rival[]
function Rivals.List(ears)
	local byGuid, rows = {}, {}
	for _, ear in ipairs(ears) do
		local last = type(ear.lastAt) == "number" and ear.lastAt or ear.at
		local row = byGuid[ear.guid]
		if not row then
			row = { guid = ear.guid, ears = 0, kills = 0, firstAt = ear.at, lastAt = last, latest = ear }
			byGuid[ear.guid] = row
			rows[#rows + 1] = row
		end
		row.ears = row.ears + 1
		row.kills = row.kills + 1 + (type(ear.camped) == "number" and ear.camped or 0)
		row.firstAt = math.min(row.firstAt, ear.at)
		if last >= row.lastAt then
			row.lastAt = last
			row.latest = ear
		end
	end
	for _, row in ipairs(rows) do
		row.name = row.latest.name
		row.prey = row.kills >= Rivals.PREY
	end
	table.sort(rows, function(a, b)
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		if a.lastAt ~= b.lastAt then
			return a.lastAt > b.lastAt
		end
		return a.guid < b.guid
	end)
	return rows
end
