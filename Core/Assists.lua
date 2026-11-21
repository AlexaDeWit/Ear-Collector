-- Assists: kills where someone outside your group landed the killing blow but
-- you earned honorable-kill credit. Forever gives addons no damage data, so the
-- evidence is timing: an honorable kill (HK) credit arriving within WINDOW
-- seconds of an enemy player's death.
--
-- Credits and the deaths within WINDOW of them form groups, resolved together.
-- Rules, in order, for each group:
--   1. Credits next to kills your group already collected are used up by them
--      (no double ear).
--   2. If enough credits remain for every other death, each is an assist.
--   3. If more players died than credits remain, name nobody: the credits are
--      counted as unnamed rather than guessed.
-- Pure logic over a session tracker; Detectors/HonorKill.lua feeds it.
local _, ns = ...

local Assists = {}
ns.Assists = Assists

Assists.WINDOW = 2.5 -- seconds between a death and its honorable-kill credit
Assists.KEEP = 15 -- seconds a death or group kill stays available for matching

---@class EarCollector.AssistTracker
---@field deaths { guid: string, t: number, kill: EarCollector.Kill, used: boolean? }[]
---@field groupKills { guid: string, t: number, used: boolean? }[]
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
function Assists.NoteGroupKill(tracker, guid, t)
	tracker.groupKills = prune(tracker.groupKills, t)
	tracker.groupKills[#tracker.groupKills + 1] = { guid = guid, t = t }
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

--- Match settled credits to deaths.
---
--- Each credit is linked to every death and group kill within WINDOW of it, and
--- each connected group is resolved as a whole, once nothing in it is newer than
--- WINDOW (so late events have arrived). Resolving one credit at a time loses
--- assists: two enemies dying a second apart, each followed by a credit, would
--- leave both credits seeing two candidates. As a group it is two credits for
--- two deaths, so both are assists.
---@param tracker EarCollector.AssistTracker
---@param now number GetTime()
---@return EarCollector.Kill[] assists victims to collect as assist ears
---@return integer unnamed credits that couldn't be tied to one victim
---@return integer pending credits not settled yet
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

	local assists, unnamed, waiting = {}, 0, {}
	for _, group in ipairs(order) do
		if #group.credits > 0 then
			if now - group.newest < Assists.WINDOW then
				for _, credit in ipairs(group.credits) do
					waiting[#waiting + 1] = credit
				end
			else
				local remaining = 0
				for _, credit in ipairs(group.credits) do
					remaining = remaining + credit.n
				end
				-- Rule 1: kills your group collected use up their credits.
				local ours = {}
				for _, g in ipairs(group.groupKills) do
					g.used = true
					if not ours[g.guid] then
						ours[g.guid] = true
						remaining = remaining - 1
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
				-- fewer names nobody.
				if #others > 0 and #others <= remaining then
					for _, d in ipairs(others) do
						assists[#assists + 1] = d.kill
					end
					remaining = remaining - #others
				end
				unnamed = unnamed + remaining
			end
		end
	end
	tracker.credits = waiting
	tracker.deaths = prune(tracker.deaths, now)
	tracker.groupKills = prune(tracker.groupKills, now)
	return assists, unnamed, #waiting
end

ns.assistTracker = Assists.New()
