-- Assists: kills someone outside your group finished while you took part, shown
-- by honor arriving within WINDOW seconds of the death or, failing that, by the
-- damage meter (FromDamage). Pure logic; docs/architecture.md has the rules.
local _, ns = ...

local Assists = {}
ns.Assists = Assists

Assists.WINDOW = 2.5 -- seconds between a death and its honorable-kill credit
Assists.KEEP = 15 -- seconds a death or group kill stays available for matching
Assists.RECENT = 60 -- seconds after your fight ends that a death still counts as part of it

---@class EarCollector.AssistTracker
---@field deaths { guid: string, t: number, kill: EarCollector.Kill, used: boolean? }[]
---@field groupKills { guid: string, t: number, honorless: boolean?, used: boolean? }[]
---@field credits { n: integer, t: number }[]

---@return EarCollector.AssistTracker
function Assists.New()
	return { deaths = {}, groupKills = {}, credits = {} }
end

local function prune(list, now)
	local kept = {}
	for _, item in ipairs(list) do
		if now - item.t <= Assists.KEEP then
			kept[#kept + 1] = item
		end
	end
	return kept
end

--- An enemy player died in the open world (UNIT_DIED, or a PARTY_KILL by someone outside the group).
---@param tracker EarCollector.AssistTracker
---@param death { guid: string, t: number, kill: EarCollector.Kill }
function Assists.NoteDeath(tracker, death)
	tracker.deaths = prune(tracker.deaths, death.t)
	for _, d in ipairs(tracker.deaths) do
		if d.guid == death.guid and math.abs(d.t - death.t) <= Assists.WINDOW then
			return -- the same death reported twice (UNIT_DIED and PARTY_KILL)
		end
	end
	tracker.deaths[#tracker.deaths + 1] = { guid = death.guid, t = death.t, kill = death.kill }
end

--- Your group killed this player and an ear was collected; its credit is not an assist.
---@param tracker EarCollector.AssistTracker
---@param guid string
---@param t number GetTime()
---@param honorless boolean? the victim was grey to you, so the kill gave no credit to use up
function Assists.NoteGroupKill(tracker, guid, t, honorless)
	tracker.groupKills = prune(tracker.groupKills, t)
	tracker.groupKills[#tracker.groupKills + 1] = { guid = guid, t = t, honorless = honorless }
end

--- Your honorable-kill count went up by `n` at time `t`.
---@param tracker EarCollector.AssistTracker
---@param n integer
---@param t number GetTime()
function Assists.NoteHonor(tracker, n, t)
	tracker.credits[#tracker.credits + 1] = { n = n, t = t }
end

-- Union-find over item indices, for grouping credits with the deaths near them.
local function find(parent, i)
	while parent[i] ~= i do
		parent[i] = parent[parent[i]]
		i = parent[i]
	end
	return i
end

--- Match settled credits to deaths. Credits and the deaths within WINDOW of them
--- form groups, each resolved whole once nothing in it is newer than WINDOW: one
--- credit at a time would see two candidates when two enemies die close together.
---@param tracker EarCollector.AssistTracker
---@param now number GetTime()
---@return EarCollector.Kill[] assists victims to collect as assist ears
---@return integer unnamed credits that couldn't be tied to one victim
---@return integer pending credits not settled yet
---@return { guid: string, t: number, kill: EarCollector.Kill }[] unclaimed settled deaths no credit named
---@return integer settling deaths not settled yet
function Assists.Resolve(tracker, now)
	local nodes, parent = {}, {}
	for _, credit in ipairs(tracker.credits) do
		nodes[#nodes + 1] = { kind = "credit", item = credit }
	end
	local firstVictim = #nodes + 1
	for _, g in ipairs(tracker.groupKills) do
		if not g.used then
			nodes[#nodes + 1] = { kind = "group", item = g }
		end
	end
	for _, d in ipairs(tracker.deaths) do
		if not d.used then
			nodes[#nodes + 1] = { kind = "death", item = d }
		end
	end
	for i = 1, #nodes do
		parent[i] = i
	end
	for i = 1, firstVictim - 1 do
		for j = firstVictim, #nodes do
			if math.abs(nodes[i].item.t - nodes[j].item.t) <= Assists.WINDOW then
				parent[find(parent, i)] = find(parent, j)
			end
		end
	end

	local groups, order = {}, {}
	for i, node in ipairs(nodes) do
		local root = find(parent, i)
		local group = groups[root]
		if not group then
			group = { credits = {}, groupKills = {}, deaths = {}, newest = node.item.t }
			groups[root] = group
			order[#order + 1] = group
		end
		group.newest = math.max(group.newest, node.item.t)
		local list = node.kind == "credit" and group.credits
			or node.kind == "group" and group.groupKills
			or group.deaths
		list[#list + 1] = node.item
	end

	-- A group kill fires UNIT_DIED too: that death is the group's ear, never an
	-- unclaimed one, whether or not a credit links them.
	local function groupKilled(d)
		for _, g in ipairs(tracker.groupKills) do
			if g.guid == d.guid and math.abs(g.t - d.t) <= Assists.WINDOW then
				return true
			end
		end
		return false
	end

	local assists, unnamed, waiting, unclaimed, settling = {}, 0, {}, {}, 0
	for _, group in ipairs(order) do
		if now - group.newest < Assists.WINDOW then
			for _, credit in ipairs(group.credits) do
				waiting[#waiting + 1] = credit
			end
			settling = settling + #group.deaths
		else
			local remaining = 0
			for _, credit in ipairs(group.credits) do
				remaining = remaining + credit.n
			end
			-- Rule 1: kills your group collected use up their credits, except
			-- kills of grey victims, which gave none.
			local ours = {}
			for _, g in ipairs(group.groupKills) do
				g.used = true
				if not ours[g.guid] then
					ours[g.guid] = true
					if not g.honorless then
						remaining = remaining - 1
					end
				end
			end
			remaining = math.max(remaining, 0)
			local others = {}
			for _, d in ipairs(group.deaths) do
				d.used = true
				if not ours[d.guid] then
					others[#others + 1] = d
				end
			end
			-- Rules 2 and 3: enough credits for every death names them all;
			-- fewer names nobody, and the damage meter gets a say.
			if #others > 0 and #others <= remaining then
				for _, d in ipairs(others) do
					assists[#assists + 1] = d.kill
				end
				remaining = remaining - #others
			else
				for _, d in ipairs(others) do
					if not groupKilled(d) then
						unclaimed[#unclaimed + 1] = d
					end
				end
			end
			unnamed = unnamed + remaining
		end
	end
	tracker.credits = waiting
	tracker.deaths = prune(tracker.deaths, now)
	tracker.groupKills = prune(tracker.groupKills, now)
	return assists, unnamed, #waiting, unclaimed, settling
end

--- Unclaimed deaths the damage meter ties to you: you or your group damaged the
--- player, and they died during the death's own fight or within RECENT after it.
---@param deaths { guid: string, t: number, kill: EarCollector.Kill, fight: table? }[] unclaimed deaths
---@param damaged table<string, any> enemy players on the meter, by GUID
---@param fight { start: number, finish: number? }|nil the fight for deaths without one, GetTime()
---@return EarCollector.Kill[] assists
---@return { guid: string, reason: string }[] rejected
function Assists.FromDamage(deaths, damaged, fight)
	local assists, rejected = {}, {}
	for _, d in ipairs(deaths) do
		local reason
		local f = d.fight or fight
		if not f then
			reason = "no fight on record"
		elseif d.t < f.start - Assists.WINDOW or (f.finish and d.t > f.finish + Assists.RECENT) then
			reason = "not during or just after your last fight"
		elseif damaged[d.guid] == nil then
			reason = "not on the damage meter"
		end
		if reason then
			rejected[#rejected + 1] = { guid = d.guid, reason = reason }
		else
			assists[#assists + 1] = d.kill
		end
	end
	return assists, rejected
end

ns.assistTracker = Assists.New()
