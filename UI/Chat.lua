-- Chat output. Everything goes to the player's own chat frame.
local _, ns = ...

local Chat = {}
ns.Chat = Chat

local PREFIX = "|cffc8402f[Ear Collector]|r "

-- Blizzard's race icons are atlases named raceicon-<race>-<gender>
-- (Blizzard_SharedXML's GetRaceAtlas); a few race tokens use a shorter name.
local ATLAS_RACE = { scourge = "undead" }

---@param message string
function Chat.Print(message)
	print(PREFIX .. message)
end

--- The atlas name for the victim's race icon, or nil when the client has none
--- (for example a race added after the icons were made).
---@param race string? English race token from GetPlayerInfoByGUID, e.g. "Scourge"
---@param sex number? 2 male, 3 female
---@return string|nil
function Chat.RaceAtlas(race, sex)
	if type(race) ~= "string" then
		return nil
	end
	local key = race:lower()
	local atlas = ("raceicon-%s-%s"):format(ATLAS_RACE[key] or key, sex == 3 and "female" or "male")
	if not C_Texture.GetAtlasInfo(atlas) then
		return nil
	end
	return atlas
end

--- "Name's Ear" in the ear's quality color, after the victim's race icon when there is one.
---@param ear table
---@return string
function Chat.EarName(ear)
	local quality = ns.QUALITY[ear.quality] or ns.QUALITY[2]
	local atlas = Chat.RaceAtlas(ear.race, ear.sex)
	local icon = atlas and ("|A:%s:14:14|a "):format(atlas) or ""
	return ("%s|c%s%s's Ear|r"):format(icon, quality.color, ear.name)
end

---@param ear table
---@param isNew boolean
function Chat.Announce(ear, isNew)
	if isNew then
		local quality = ns.QUALITY[ear.quality] or ns.QUALITY[2]
		local by = ""
		if ear.by == "group" then
			by = ear.killer and (" Killing blow: %s."):format(ear.killer) or " Killing blow: your group."
		elseif ear.by == "assist" then
			by = " Assist."
		end
		Chat.Print(("You collected %s (%s).%s"):format(Chat.EarName(ear), quality.name, by))
	else
		Chat.Print(("Camped %s again (kill %d). No new ear."):format(ear.name, ear.camped + 1))
	end
end
