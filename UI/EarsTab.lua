-- The pouch's Ears tab: a grid of your ears, newest first, with a tooltip for each.
local _, ns = ...

local Art, Chat, Errors, Pouch = ns.Art, ns.Chat, ns.Errors, ns.Pouch

local EarsTab = {}
ns.EarsTab = EarsTab

local GREY = { 0.62, 0.62, 0.62 }

---@class EarCollector.Slot : Button
---@field icon Texture
---@field edges Texture[]
---@field count FontString
---@field glow Texture
---@field ear table?

local slots = {} ---@type EarCollector.Slot[]
local countText, emptyText ---@type FontString, FontString
local page = 1
local focused ---@type table?

local function newestFirst()
	local list, ears = {}, ns.db and ns.db.ears or {}
	for i = #ears, 1, -1 do
		list[#list + 1] = ears[i]
	end
	return list
end

local function pageCount(total)
	return math.max(1, math.ceil(total / Pouch.PER_PAGE))
end

local function classColored(ear)
	local name = ear.className or (ear.class and LOCALIZED_CLASS_NAMES_MALE[ear.class]) or ear.class or "Unknown class"
	local hex = Chat.ClassHex(ear.class)
	return hex and ("|c%s%s|r"):format(hex, name) or name
end

--- An ear's tooltip, as lines: { text, r, g, b } or { left, right, r, g, b }.
---@param ear table
---@return table[]
function EarsTab.TooltipLines(ear)
	local quality = ns.Quality(ear.quality)
	local lines = {}
	local function add(text, color)
		color = color or { 1, 1, 1 }
		lines[#lines + 1] = { text = text, r = color[1], g = color[2], b = color[3] }
	end
	add(("%s's Ear"):format(ear.name), { quality.r, quality.g, quality.b })
	lines[#lines + 1] = { left = "Trophy", right = quality.name, r = quality.r, g = quality.g, b = quality.b }
	if ear.surname then
		add(("%s %s"):format(ear.name, ear.surname), GREY)
	end
	local race = Chat.RaceIcon(ear.race, ear.sex) .. (ear.raceName or ear.race or "")
	add((("Level %s %s %s"):format(ear.level or "??", race, classColored(ear)):gsub("  ", " ")))
	add(" ")
	if ear.subzone then
		add(("Taken at %s"):format(ear.subzone))
		if ear.zone then
			add(ear.zone, GREY)
		end
	elseif ear.zone then
		add(("Taken in %s"):format(ear.zone))
	end
	if ear.by == "group" then
		add(("Killing blow: %s (your group)"):format(ear.killer or "a groupmate"))
	elseif ear.by == "assist" then
		add("Assist: honor credit, killing blow from outside your group", { 0.17, 0.85, 0.17 })
	else
		add("Killing blow: you")
	end
	if ear.vengeance then
		local legendary = ns.QUALITY[5]
		add(
			("Vengeance: they had killed you %d times since you last took their ear"):format(ear.vengeance),
			{ legendary.r, legendary.g, legendary.b }
		)
	end
	if ear.yourLevel then
		add(("You were level %d"):format(ear.yourLevel), GREY)
	end
	if ear.camped and ear.camped > 0 then
		add(("Camped: %d more kill%s within the window"):format(ear.camped, ear.camped > 1 and "s" or ""), GREY)
	end
	add(date("%b %d, %Y %H:%M", ear.at), GREY)
	return lines
end

local function showTooltip(slot)
	if slot.ear then
		Chat.ShowTooltip(slot, "ANCHOR_RIGHT", EarsTab.TooltipLines(slot.ear))
	end
end

local function hideTooltip()
	GameTooltip:Hide()
end

local function newSlot(parent, index)
	local slot = CreateFrame("Button", nil, parent) --[[@as EarCollector.Slot]]
	local step = Pouch.SLOT + Pouch.GAP
	local column, row = (index - 1) % Pouch.COLUMNS, math.floor((index - 1) / Pouch.COLUMNS)
	slot:SetSize(Pouch.SLOT, Pouch.SLOT)
	slot:SetPoint("TOPLEFT", parent, "TOPLEFT", Pouch.PAD + column * step, -(36 + row * step))

	local bg = slot:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.55)

	slot.icon = slot:CreateTexture(nil, "ARTWORK")
	slot.icon:SetPoint("TOPLEFT", 2, -2)
	slot.icon:SetPoint("BOTTOMRIGHT", -2, 2)

	-- A border in the grade's colour, from four thin textures.
	slot.edges = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local edge = slot:CreateTexture(nil, "OVERLAY")
		if side == "TOP" or side == "BOTTOM" then
			edge:SetPoint(side .. "LEFT")
			edge:SetPoint(side .. "RIGHT")
			edge:SetHeight(2)
		else
			edge:SetPoint("TOP" .. side)
			edge:SetPoint("BOTTOM" .. side)
			edge:SetWidth(2)
		end
		slot.edges[#slot.edges + 1] = edge
	end

	slot.glow = slot:CreateTexture(nil, "HIGHLIGHT")
	slot.glow:SetAllPoints()
	slot.glow:SetColorTexture(1, 0.82, 0.2, 0.25)

	slot.count = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	slot.count:SetPoint("BOTTOMRIGHT", -3, 3)

	slot:SetScript("OnEnter", Errors.Wrap("pouch tooltip", showTooltip))
	slot:SetScript("OnLeave", Errors.Wrap("pouch tooltip", hideTooltip))
	return slot
end

local function fillSlot(slot, ear)
	slot.ear = ear
	slot:SetAlpha(ear and 1 or 0.6)
	slot.icon:SetShown(ear ~= nil)
	slot.count:SetText(ear and (ear.camped or 0) > 0 and tostring(ear.camped + 1) or "")
	local quality = ear and ns.Quality(ear.quality)
	for _, edge in ipairs(slot.edges) do
		edge:SetShown(ear ~= nil)
		if quality then
			edge:SetColorTexture(quality.r, quality.g, quality.b, 1)
		end
	end
	if ear then
		slot.icon:SetTexture(Art.EarTexture(ear.race, ear.guid))
		slot.icon:SetDesaturated(ear.quality == 0)
	end
	if focused and ear == focused then
		slot:LockHighlight()
	else
		slot:UnlockHighlight()
	end
end

local function build(panel)
	countText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -Pouch.PAD, -30)
	countText:SetJustifyH("RIGHT")
	for i = 1, Pouch.PER_PAGE do
		slots[i] = newSlot(panel, i)
	end
	emptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	emptyText:SetPoint("CENTER", panel, "CENTER", 0, 0)
	emptyText:SetWidth(Pouch.WIDTH - 2 * Pouch.PAD - 20)
	emptyText:SetText("No ears yet. Kill an enemy player in the open world, with your group or on your own.")
end

local function refresh()
	local ears = newestFirst()
	page = math.min(math.max(page, 1), pageCount(#ears))
	local first = (page - 1) * Pouch.PER_PAGE
	for i, slot in ipairs(slots) do
		fillSlot(slot, ears[first + i])
	end
	countText:SetText(("%d ears, %d assists"):format(#ears, ns.Ears.CountAssists(ears)))
	emptyText:SetShown(#ears == 0)
end

Pouch.AddTab({
	title = "Ears",
	build = build,
	refresh = refresh,
	pages = function()
		return page, pageCount(ns.db and #ns.db.ears or 0)
	end,
	setPage = function(n)
		page = n
	end,
	onHide = function()
		focused = nil
	end,
})

--- Open the pouch on one ear: this tab, turned to its page, with the ear
--- highlighted and its tooltip showing.
---@param guid string
---@param at number
---@return boolean found
function EarsTab.Focus(guid, at)
	for index, ear in ipairs(newestFirst()) do
		if ear.guid == guid and ear.at == at then
			Pouch.Open("Ears")
			focused = ear
			page = math.floor((index - 1) / Pouch.PER_PAGE) + 1
			Pouch.Refresh()
			local slot = slots[(index - 1) % Pouch.PER_PAGE + 1]
			if slot then
				showTooltip(slot)
			end
			return true
		end
	end
	return false
end

--- The slots and labels, for specs.
function EarsTab.Widgets()
	return { slots = slots, count = countText, empty = emptyText }
end
