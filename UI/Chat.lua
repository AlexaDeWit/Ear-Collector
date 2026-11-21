-- Chat output. Everything goes to the player's own chat frame.
local _, ns = ...

local Chat = {}
ns.Chat = Chat

local PREFIX = "|cffc8402f[Ear Collector]|r "

---@param message string
function Chat.Print(message)
	print(PREFIX .. message)
end

--- "Name's Ear" in the ear's quality color.
---@param ear table
---@return string
function Chat.EarName(ear)
	local quality = ns.QUALITY[ear.quality] or ns.QUALITY[2]
	return ("|c%s%s's Ear|r"):format(quality.color, ear.name)
end

---@param ear table
---@param isNew boolean
function Chat.Announce(ear, isNew)
	if isNew then
		local quality = ns.QUALITY[ear.quality] or ns.QUALITY[2]
		Chat.Print(("You collected %s (%s)."):format(Chat.EarName(ear), quality.name))
	else
		Chat.Print(("Camped %s again (kill %d). No new ear."):format(ear.name, ear.camped + 1))
	end
end
