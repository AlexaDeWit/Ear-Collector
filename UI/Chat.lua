-- Chat output. Everything goes to the player's own chat frame.
local addonName, ns = ...

local Chat = {}
ns.Chat = Chat

local PREFIX = "|cffc8402f[Ear Collector]|r "

-- Blizzard's race icons are atlases named raceicon-<race>-<gender>
-- (Blizzard_SharedXML's GetRaceAtlas); a few race tokens use a shorter name.
local ATLAS_RACE = { scourge = "undead" }

-- Ear links: |Haddon:EarCollector:ear:<victim GUID>:<time>|h. Clicking one fires
-- EventRegistry "SetItemRef" (Blizzard's handler for "addon" links); UI/Access.lua
-- listens and opens the pouch on that ear. Player GUIDs contain no ":".
local LINK_PREFIX = "addon:" .. addonName .. ":ear:"

---@param message string
function Chat.Print(message)
	print(PREFIX .. message)
end

--- The atlas name for a race icon, or nil when the client has none
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

--- A clickable "[Name's Ear]" that opens the pouch on this ear.
---@param ear table
---@return string
function Chat.EarLink(ear)
	local quality = ns.QUALITY[ear.quality] or ns.QUALITY[2]
	local atlas = Chat.RaceAtlas(ear.race, ear.sex)
	local icon = atlas and ("|A:%s:14:14|a "):format(atlas) or ""
	return ("%s|c%s|H%s%s:%d|h[%s's Ear]|h|r"):format(icon, quality.color, LINK_PREFIX, ear.guid, ear.at, ear.name)
end

--- The ear an ear link points at.
---@param link any the link payload passed to SetItemRef, e.g. "addon:EarCollector:ear:Player-1-A:1795293660"
---@return string|nil guid
---@return number|nil at
function Chat.ParseEarLink(link)
	if type(link) ~= "string" or link:sub(1, #LINK_PREFIX) ~= LINK_PREFIX then
		return nil, nil
	end
	local guid, at = link:sub(#LINK_PREFIX + 1):match("^([^:]+):(%d+)$")
	return guid, tonumber(at)
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
		if ear.vengeance then
			Chat.Print(
				("Vengeance! You collected %s (%s). They had killed you %d times.%s"):format(
					Chat.EarLink(ear),
					quality.name,
					ear.vengeance,
					by
				)
			)
			return
		end
		Chat.Print(("You collected %s (%s).%s"):format(Chat.EarLink(ear), quality.name, by))
	else
		Chat.Print(("Camped %s again (kill %d). No new ear."):format(ear.name, ear.camped + 1))
	end
end

--- "Grimbash killed you." plus the vengeance tally.
---@param death table
---@param debt integer deaths to them since you last killed them, this one included
function Chat.AnnounceDeath(death, debt)
	local atlas = Chat.RaceAtlas(death.race, death.sex)
	local icon = atlas and ("|A:%s:14:14|a "):format(atlas) or ""
	local color = death.class and C_ClassColor.GetClassColor(death.class)
	local hex = color and color:GenerateHexColor() or "ffffffff"
	local who = ("%s|c%s%s|r"):format(icon, hex, death.name)
	if debt >= ns.Deaths.VENGEANCE then
		local legendary = ns.QUALITY[5]
		Chat.Print(
			("%s killed you (%d times since you last killed them). |c%sVengeance owed:|r their next ear is Legendary."):format(
				who,
				debt,
				legendary.color
			)
		)
	elseif debt > 1 then
		Chat.Print(("%s killed you (%d times since you last killed them)."):format(who, debt))
	else
		Chat.Print(("%s killed you."):format(who))
	end
end
