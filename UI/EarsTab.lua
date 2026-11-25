-- The pouch's Ears tab: a grid of your ears, newest first, with a tooltip for
-- each, less any grades hidden with the grade buttons (UI/GradeFilter.lua).
local _, ns = ...

local Art, Chat, Errors, GradeFilter, Pouch = ns.Art, ns.Chat, ns.Errors, ns.GradeFilter, ns.Pouch

local EarsTab = {}
ns.EarsTab = EarsTab

local GREY = { 0.62, 0.62, 0.62 }
-- Blizzard's own bag-slot art (Blizzard_ItemButton, ContainerFrame.lua).
local BORDER = "Interface\\Common\\WhiteIconFrame"
local HIGHLIGHT = "Interface\\Buttons\\ButtonHilight-Square"
local NEW_GLOW = "bags-glow-white"

---@class EarCollector.Slot : Button
---@field icon Texture
---@field border Texture tinted by grade, shown from Uncommon up, as bags show it
---@field dot Texture the victim's class colour
---@field new Texture glows on an ear collected since the pouch last closed
---@field count FontString
---@field ear table?

local slots = {} ---@type EarCollector.Slot[]
local countText ---@type FontString
local emptyFrame ---@type Frame
local emptyHeading, emptyLine ---@type FontString, FontString
local page = 1
local focused ---@type table?
local newSince = GetServerTime() -- ears after this glow until hovered
local seen = {} ---@type table<table, true> ears hovered since the pouch opened

local function isNew(ear)
	return ear.at > newSince and not seen[ear]
end

local function newestFirst()
	local list, ears = {}, ns.db and ns.db.ears or {}
	for i = #ears, 1, -1 do
		list[#list + 1] = ears[i]
	end
	return list
end

local function shownEars()
	return ns.Ears.Filter(newestFirst(), ns.db and ns.db.hiddenGrades)
end

local function pageCount(total)
	return math.max(1, math.ceil(total / Pouch.PER_PAGE))
end

local GOLD = { 1, 0.82, 0 }
local KINDS = { up = { 0.1, 1, 0.1 }, down = { 1, 0.1, 0.1 }, context = GREY, note = GREY }
local EMPTY = { 0.29, 0.3, 0.33 }

-- One to three tinted squares, right-aligned beside a reason: how much it counted.
local function squares(n, colour)
	local out = {}
	for i = 1, 3 do
		local c = i <= n and colour or EMPTY
		local r, g, b = math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)
		out[i] = ("|TInterface\\Buttons\\WHITE8X8:7:7:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(r, g, b)
	end
	return table.concat(out, " ")
end

--- An ear's tooltip, as lines: { text, r, g, b } or { left, right, r, g, b, lr?, lg?, lb? }.
--- Under who they were, "Why it's <grade>" lists what counted; the story closes it.
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
	add((("Level %s %s %s"):format(ear.level or "??", race, Chat.ClassName(ear.class, ear.className)):gsub("  ", " ")))
	local why = ns.FightSummary.Lines(ear)
	if #why > 0 then
		add(" ")
		add(("Why it's |c%s%s|r"):format(quality.color, quality.name), GOLD)
		for _, line in ipairs(why) do
			if line.strength then
				local c = KINDS[line.kind]
				local sign = line.kind == "up" and "+ " or "- "
				lines[#lines + 1] =
					{ left = sign .. line.text, right = squares(line.strength, c), lr = c[1], lg = c[2], lb = c[3] }
			else
				local legendary = ns.QUALITY[5]
				add(line.text, KINDS[line.kind] or { legendary.r, legendary.g, legendary.b })
			end
		end
	end
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
		add("Assist: killing blow from outside your group")
	else
		add("Killing blow: you")
	end
	if ear.yourLevel then
		add(("You were level %d"):format(ear.yourLevel), GREY)
	end
	if ear.camped and ear.camped > 0 then
		local minutes = math.floor((ns.db and ns.db.settings.campWindow or 600) / 60 + 0.5)
		local within = Chat.Count(minutes, "minute")
		local kills = ear.camped == 1 and "kill" or "kills"
		add(("Camped: %d more %s within %s"):format(ear.camped, kills, within), GREY)
	end
	add(Chat.Date(ear.at, "full"), GREY)
	local story = ns.Tales.Story(ear)
	if story then
		add(('"%s"'):format(story), GOLD)
	end
	return lines
end

local function showTooltip(slot)
	if slot.ear then
		Chat.ShowTooltip(slot, "ANCHOR_RIGHT", EarsTab.TooltipLines(slot.ear))
		seen[slot.ear] = true
		slot.new:Hide()
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
	slot:SetPoint("TOPLEFT", parent, "TOPLEFT", Pouch.PAD + column * step, -(Pouch.GRID_TOP + row * step))

	local bg = slot:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.55)

	slot.icon = slot:CreateTexture(nil, "ARTWORK")
	slot.icon:SetPoint("TOPLEFT", 2, -2)
	slot.icon:SetPoint("BOTTOMRIGHT", -2, 2)

	slot.border = slot:CreateTexture(nil, "OVERLAY")
	slot.border:SetAllPoints()
	slot.border:SetTexture(BORDER)

	slot.new = slot:CreateTexture(nil, "OVERLAY", nil, 1)
	slot.new:SetAllPoints()
	slot.new:SetBlendMode("ADD")
	if C_Texture.GetAtlasInfo(NEW_GLOW) then
		slot.new:SetAtlas(NEW_GLOW)
	else
		slot.new:SetColorTexture(1, 1, 1, 0.25)
	end

	slot.dot = slot:CreateTexture(nil, "OVERLAY", nil, 2)
	slot.dot:SetSize(5, 5)
	slot.dot:SetPoint("TOPLEFT", 4, -4)

	local highlight = slot:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetTexture(HIGHLIGHT)
	highlight:SetBlendMode("ADD")

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
	slot.new:SetShown(ear ~= nil and isNew(ear))
	local quality = ear and ns.Quality(ear.quality)
	slot.border:SetShown(ear ~= nil and ear.quality >= 2)
	if quality then
		slot.border:SetVertexColor(quality.r, quality.g, quality.b)
	end
	local hex = ear and Chat.ClassHex(ear.class)
	slot.dot:SetShown(hex ~= nil)
	if hex then
		slot.dot:SetColorTexture(Chat.RGB(hex))
	end
	if ear then
		local poor = ear.quality == 0
		slot.icon:SetTexture(Art.EarTexture(ear.race, ear.guid))
		slot.icon:SetDesaturated(poor) -- and dimmed, so a Poor ear doesn't read as an undead one
		local shade = poor and 0.6 or 1
		slot.icon:SetVertexColor(shade, shade, shade)
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
	GradeFilter.Build(panel, Pouch.PAD, -27)
	for i = 1, Pouch.PER_PAGE do
		slots[i] = newSlot(panel, i)
	end
	-- Above the slots, so it doesn't show through them.
	emptyFrame = CreateFrame("Frame", nil, panel)
	emptyFrame:SetAllPoints()
	emptyFrame:SetFrameLevel(slots[1]:GetFrameLevel() + 5)
	emptyHeading = emptyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	emptyHeading:SetPoint("CENTER", emptyFrame, "CENTER", 0, 10)
	emptyLine = emptyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	emptyLine:SetPoint("TOP", emptyHeading, "BOTTOM", 0, -6)
	emptyLine:SetWidth(Pouch.WIDTH - 2 * Pouch.PAD - 40)
end

local function refresh()
	local all = newestFirst()
	local ears, hidden = ns.Ears.Filter(all, ns.db and ns.db.hiddenGrades)
	page = math.min(math.max(page, 1), pageCount(#ears))
	local first = (page - 1) * Pouch.PER_PAGE
	for i, slot in ipairs(slots) do
		fillSlot(slot, ears[first + i])
	end
	local count = Chat.EarCount(#ears, ns.Ears.CountAssists(ears))
	countText:SetText(hidden > 0 and ("%s, %d hidden"):format(count, hidden) or count)
	GradeFilter.Update(all)
	emptyFrame:SetShown(#ears == 0)
	if #all == 0 then
		emptyHeading:SetText("No ears yet")
		emptyLine:SetText("Kill an enemy player in the open world, with your group or on your own.")
	else
		emptyHeading:SetText("Every ear is hidden")
		emptyLine:SetText("Click a grade button above to show its ears.")
	end
end

Pouch.AddTab({
	title = "Ears",
	build = build,
	refresh = refresh,
	pages = function()
		return page, pageCount(#(shownEars()))
	end,
	setPage = function(n)
		page = n
	end,
	onHide = function()
		focused = nil
		newSince, seen = GetServerTime(), {}
	end,
})

--- Open the pouch on one ear: this tab, turned to its page, with the ear
--- highlighted and its tooltip showing. A hidden grade is shown again.
---@param guid string
---@param at number
---@return boolean found
function EarsTab.Focus(guid, at)
	for _, ear in ipairs(ns.db and ns.db.ears or {}) do
		if ear.guid == guid and ear.at == at then
			ns.db.hiddenGrades[ear.quality] = nil
		end
	end
	for index, ear in ipairs((shownEars())) do
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
	return { slots = slots, count = countText, empty = emptyFrame, emptyHeading = emptyHeading }
end
