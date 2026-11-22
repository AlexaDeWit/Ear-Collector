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

--- The race icon as inline markup with a trailing space, or "" when the client
--- has no icon for the race.
---@param race string?
---@param sex number?
---@return string
function Chat.RaceIcon(race, sex)
	local atlas = Chat.RaceAtlas(race, sex)
	return atlas and ("|A:%s:14:14|a "):format(atlas) or ""
end

--- A class's colour as "ffRRGGBB", or nil for an unknown or missing class.
---@param token any English class token, e.g. "WARRIOR"
---@return string|nil
function Chat.ClassHex(token)
	local color = type(token) == "string" and C_ClassColor.GetClassColor(token)
	local hex = color and color:GenerateHexColor()
	if type(hex) == "string" and hex:find("^%x%x%x%x%x%x%x%x$") then
		return hex
	end
	return nil
end

--- `text` in a class's colour, or plain for an unknown class.
---@param text string
---@param class any English class token, e.g. "WARRIOR"
---@return string
function Chat.InClassColour(text, class)
	local hex = Chat.ClassHex(class)
	return hex and ("|c%s%s|r"):format(hex, text) or text
end

--- Show tooltip lines ({ text, r, g, b } or { left, right, r, g, b }) on `owner`.
---@param owner Frame
---@param anchor string e.g. "ANCHOR_RIGHT"
---@param lines table[]
function Chat.ShowTooltip(owner, anchor, lines)
	GameTooltip:SetOwner(owner, anchor)
	for _, line in ipairs(lines) do
		if line.left then
			GameTooltip:AddDoubleLine(
				line.left,
				line.right,
				line.lr or 1,
				line.lg or 1,
				line.lb or 1,
				line.r,
				line.g,
				line.b
			)
		else
			GameTooltip:AddLine(line.text, line.r, line.g, line.b, true)
		end
	end
	GameTooltip:Show()
end

--- "Name's Ear" in the ear's quality colour, after the victim's race icon when there is one.
---@param ear table
---@return string
function Chat.EarName(ear)
	local quality = ns.Quality(ear.quality)
	local icon = Chat.RaceIcon(ear.race, ear.sex)
	return ("%s|c%s%s's Ear|r"):format(icon, quality.color, ear.name)
end

--- A clickable "[Name's Ear]" that opens the pouch on this ear.
---@param ear table
---@return string
function Chat.EarLink(ear)
	local quality = ns.Quality(ear.quality)
	local icon = Chat.RaceIcon(ear.race, ear.sex)
	return ("%s|c%s|H%s%s:%d|h[%s's Ear]|h|r"):format(icon, quality.color, LINK_PREFIX, ear.guid, ear.at, ear.name)
end

--- "1 ear", "3 ears": a count with its noun.
---@param n integer
---@param singular string
---@param plural string? defaults to singular .. "s"
function Chat.Count(n, singular, plural)
	return ("%d %s"):format(n, n == 1 and singular or plural or singular .. "s")
end

--- "22 ears (6 assists)", or just "1 ear" without assists.
---@param ears integer
---@param assists integer
function Chat.EarCount(ears, assists)
	local text = Chat.Count(ears, "ear")
	return assists > 0 and ("%s (%s)"):format(text, Chat.Count(assists, "assist")) or text
end

--- A date without leading zeros: "Nov 1", or with `style` "time" ("Nov 1 14:05"),
--- "year" ("Nov 1, 2026") or "full" ("Nov 1, 2026 14:05").
---@param t number
---@param style ("time"|"year"|"full")?
---@return string
function Chat.Date(t, style)
	local day = ("%s %d"):format(date("%b", t), tonumber(date("%d", t)))
	if style == "time" then
		return day .. " " .. date("%H:%M", t)
	elseif style == "year" then
		return day .. ", " .. date("%Y", t)
	elseif style == "full" then
		return day .. ", " .. date("%Y %H:%M", t)
	end
	return day
end

--- "ffRRGGBB" as r, g, b from 0 to 1.
---@param hex string
---@return number r, number g, number b
function Chat.RGB(hex)
	return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
end

--- A class's localized name in its class colour.
---@param class string? English token, e.g. "WARRIOR"
---@param className string? the localized name, when known
---@return string
function Chat.ClassName(class, className)
	local name = className or (class and LOCALIZED_CLASS_NAMES_MALE[class]) or class or "Unknown class"
	return Chat.InClassColour(name, class)
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

-- " You took more than a full health bar and died too.": the ear's story, or why
-- there's none when the meter had no record of the fight.
local function story(ear)
	local text = ns.FightSummary.Story(ear)
	if text then
		return " " .. text
	end
	local fight = ear.fight
	return type(fight) == "table" and not fight.read and " No record of the fight." or ""
end

---@param ear table
---@param isNew boolean
---@param waiting boolean? graded when the fight ends
function Chat.Announce(ear, isNew, waiting)
	if isNew and waiting then
		Chat.Print(("You collected %s. Appraising the fight..."):format(Chat.EarLink(ear)))
	elseif isNew then
		local quality = ns.Quality(ear.quality)
		local by = ""
		if ear.by == "group" then
			by = ear.killer and (" Killing blow: %s."):format(ear.killer) or " Killing blow: your group."
		elseif ear.by == "assist" then
			by = " Assist."
		end
		if ear.vengeance then
			Chat.Print(
				("Vengeance! You collected %s (%s).%s%s"):format(Chat.EarLink(ear), quality.name, by, story(ear))
			)
			return
		end
		Chat.Print(("You collected %s (%s).%s%s"):format(Chat.EarLink(ear), quality.name, by, story(ear)))
	else
		local name = Chat.InClassColour(ear.name, ear.class)
		Chat.Print(("Camped %s again (kill %d). No new ear."):format(name, ear.camped + 1))
	end
end

--- The grade of an ear that waited for its fight to end.
---@param ear table
function Chat.AnnounceAppraisal(ear)
	Chat.Print(("Appraised %s: %s.%s"):format(Chat.EarLink(ear), ns.Quality(ear.quality).name, story(ear)))
end

Chat.REVENGE_OWED = "Revenge owed: their next ear is worth more."

-- Grudges (Detectors/Grudges.lua): a player who took your ear since you last
-- took theirs, remembered like an entry in a book of grudges.
Chat.GRUDGE = "You owe them one"

local function grudgeOwed(debt)
	return debt >= ns.Deaths.VENGEANCE and "their next ear is Legendary" or "their next ear is worth more"
end

-- "took your ear three times in a row, last on Nov 18"
local function grudgeHistory(debt, lastAt)
	local times = debt == 1 and "took your ear"
		or debt == 2 and "took your ear twice in a row"
		or ("took your ear %s times in a row"):format(ns.Reasons.Word(debt))
	if not lastAt then
		return times
	end
	return ("%s%s %s"):format(times, debt == 1 and " on" or ", last on", Chat.Date(lastAt))
end

--- "You owe Cedric Vale one. They took your ear three times in a row, last on
--- Nov 18. Their next ear is Legendary."
---@param who table the player's details (ns.VictimDetails)
---@param debt integer deaths you owe them
---@param lastAt number? when you last fought them
function Chat.AnnounceGrudge(who, debt, lastAt)
	local name = Chat.RaceIcon(who.race, who.sex) .. Chat.InClassColour(who.name, who.class)
	Chat.Print(
		("You owe %s one. They %s. %s."):format(name, grudgeHistory(debt, lastAt), ns.Reasons.Capital(grudgeOwed(debt)))
	)
end

--- The grudge on a player's tooltip, as lines like EarsTab.TooltipLines.
---@param debt integer
---@param lastAt number?
---@return table[]
function Chat.GrudgeLines(debt, lastAt)
	local legendary = ns.QUALITY[5]
	return {
		{ text = ("%s: %s"):format(Chat.GRUDGE, grudgeOwed(debt)), r = legendary.r, g = legendary.g, b = legendary.b },
		{ text = ns.Reasons.Capital(grudgeHistory(debt, lastAt)), r = 0.62, g = 0.62, b = 0.62 },
	}
end

--- The pop-up's detail line for a grudge.
---@param debt integer
---@return string
function Chat.GrudgeDetail(debt)
	return ns.Reasons.Capital(grudgeOwed(debt))
end

--- "Grimbash killed you." plus the vengeance tally.
---@param death table
---@param debt integer deaths to them since you last killed them, this one included
function Chat.AnnounceDeath(death, debt)
	local who = Chat.RaceIcon(death.race, death.sex) .. Chat.InClassColour(death.name, death.class)
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
		Chat.Print(("%s killed you (%d times since you last killed them). %s"):format(who, debt, Chat.REVENGE_OWED))
	else
		Chat.Print(("%s killed you. %s"):format(who, Chat.REVENGE_OWED))
	end
end
