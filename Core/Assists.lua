-- Assists: kills where someone outside your group landed the killing blow but
-- you earned honorable-kill credit. Forever gives addons no damage data, so the
-- evidence is timing: an honorable kill (HK) credit arriving within WINDOW
-- seconds of an enemy player's death.
--
-- Rules, in order, for each batch of credits:
--   1. A credit next to a kill your group already collected is used up by it
--      (no double ear).
--   2. Remaining credits go to the remaining deaths inside the window.
--   3. If more players died than credits remain, name nobody: the credit is
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

local function near(item, t)
	return not item.used and math.abs(item.t - t) <= Assists.WINDOW
end

--- Match settled credits (older than WINDOW, so late events have arrived) to deaths.
---@param tracker EarCollector.AssistTracker
---@param now number GetTime()
---@return EarCollector.Kill[] assists victims to collect as assist ears
---@return integer unnamed credits that couldn't be tied to one victim
---@return integer pending credits not settled yet
function Assists.Resolve(tracker, now)
	local assists, unnamed, waiting = {}, 0, {}
	for _, credit in ipairs(tracker.credits) do
		if now - credit.t < Assists.WINDOW then
			waiting[#waiting + 1] = credit
		else
			local remaining = credit.n
			local ours = {}
			for _, g in ipairs(tracker.groupKills) do
				if remaining > 0 and near(g, credit.t) then
					g.used = true
					ours[g.guid] = true
					remaining = remaining - 1
				end
			end
			local candidates = {}
			for _, d in ipairs(tracker.deaths) do
				if near(d, credit.t) then
					if ours[d.guid] then
						d.used = true
					else
						candidates[#candidates + 1] = d
					end
				end
			end
			if remaining > 0 then
				if #candidates > 0 and #candidates <= remaining then
					for _, d in ipairs(candidates) do
						d.used = true
						assists[#assists + 1] = d.kill
					end
					remaining = remaining - #candidates
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
