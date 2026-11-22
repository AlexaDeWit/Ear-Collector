-- Rivals: everyone you have taken ears from or died to, keyed by GUID, for the
-- pouch's Rivals tab. Pure logic over the ear and death lists.
local _, ns = ...

local Rivals = {}
ns.Rivals = Rivals

Rivals.PREY = 3 -- kills of one player, who has never killed you, that mark them as prey
Rivals.NEMESIS = 2 -- deaths to one player, more than your kills of them, that mark a nemesis

---@class EarCollector.Rival
---@field guid string
---@field name string from their latest ear, or their latest kill of you if you have no ears
---@field latest table their latest ear, or latest death record (for class, race, the tooltip)
---@field ears integer
---@field kills integer ears plus repeat kills inside the camping window
---@field killedYou integer
---@field debt integer deaths to them since you last killed them
---@field firstAt number first encounter, either way
---@field lastAt number? the last time you killed them
---@field lastDeathAt number? the last time they killed you
---@field lastSeen number the later of the two
---@field prey boolean
---@field nemesis boolean
---@field owed boolean vengeance owed: their next ear is Legendary

local function newRow(guid, record)
	return { guid = guid, ears = 0, kills = 0, killedYou = 0, debt = 0, firstAt = record.at, latest = record }
end

--- One row per player you have ears from or died to: most encounters (kills
--- plus deaths) first, then the most recent.
---@param ears table[]
---@param deaths table[]?
---@return EarCollector.Rival[]
function Rivals.List(ears, deaths)
	local byGuid, rows = {}, {}
	for _, ear in ipairs(ears) do
		local last = type(ear.lastAt) == "number" and ear.lastAt or ear.at
		local row = byGuid[ear.guid]
		if not row then
			row = newRow(ear.guid, ear)
			byGuid[ear.guid] = row
			rows[#rows + 1] = row
		end
		row.ears = row.ears + 1
		row.kills = row.kills + 1 + (type(ear.camped) == "number" and ear.camped or 0)
		row.firstAt = math.min(row.firstAt, ear.at)
		if not row.lastAt or last >= row.lastAt then
			row.lastAt = last
			row.latest = ear
		end
	end
	for _, death in ipairs(deaths or {}) do
		local row = byGuid[death.guid]
		if not row then
			row = newRow(death.guid, death)
			byGuid[death.guid] = row
			rows[#rows + 1] = row
		end
		row.killedYou = row.killedYou + 1
		row.firstAt = math.min(row.firstAt, death.at)
		if not row.lastDeathAt or death.at >= row.lastDeathAt then
			row.lastDeathAt = death.at
			if row.ears == 0 then
				row.latest = death
			end
		end
		if not row.lastAt or death.at > row.lastAt then
			row.debt = row.debt + 1
		end
	end
	for _, row in ipairs(rows) do
		row.name = row.latest.name
		row.lastSeen = math.max(row.lastAt or row.firstAt, row.lastDeathAt or row.firstAt)
		row.owed = row.debt >= ns.Deaths.VENGEANCE
		row.nemesis = row.killedYou >= Rivals.NEMESIS and row.killedYou > row.kills
		row.prey = row.kills >= Rivals.PREY and row.killedYou == 0
	end
	-- Avenge first: it's the mark you can act on. Then most encounters.
	table.sort(rows, function(a, b)
		if a.owed ~= b.owed then
			return a.owed
		end
		local ae, be = a.kills + a.killedYou, b.kills + b.killedYou
		if ae ~= be then
			return ae > be
		end
		if a.lastSeen ~= b.lastSeen then
			return a.lastSeen > b.lastSeen
		end
		return a.guid < b.guid
	end)
	return rows
end

--- The mark for a rival's row, most pressing first: "Avenge" (vengeance owed),
--- "Nemesis", "Prey", or nil.
---@param rival EarCollector.Rival
---@return string|nil
function Rivals.Mark(rival)
	if rival.owed then
		return "Avenge"
	elseif rival.nemesis then
		return "Nemesis"
	elseif rival.prey then
		return "Prey"
	end
	return nil
end
