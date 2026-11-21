-- The Ear Pouch: a window with a grid of collected ears, newest first.
-- Built lazily on first open, from Lua only. Every script handler runs inside
-- Errors.Wrap. The frame is not protected, so showing and hiding it is allowed
-- in combat. Escape closes it, like Blizzard's windows (see closeOnEscape).
local addonName, ns = ...

local Art, Chat, Errors = ns.Art, ns.Chat, ns.Errors

local Pouch = {}
ns.Pouch = Pouch

Pouch.COLUMNS = 8
Pouch.ROWS = 5
Pouch.PER_PAGE = Pouch.COLUMNS * Pouch.ROWS

local SLOT, GAP, PAD = 36, 4, 12
local GREY = { 0.62, 0.62, 0.62 }
local FRAME_NAME = addonName .. "Pouch"

-- The window's size, from the grid. Other tabs lay out inside it.
Pouch.PAD = PAD
Pouch.WIDTH = PAD * 2 + Pouch.COLUMNS * SLOT + (Pouch.COLUMNS - 1) * GAP
Pouch.HEIGHT = 36 + Pouch.ROWS * (SLOT + GAP) + 34

---@class EarCollector.PouchFrame : Frame
---@field TitleText FontString
---@field CloseButton Button

---@class EarCollector.Slot : Button
---@field icon Texture
---@field edges Texture[]
---@field count FontString
---@field glow Texture
---@field ear table?

local frame ---@type EarCollector.PouchFrame?
local slots = {} ---@type EarCollector.Slot[]
local countText, pageText, emptyText ---@type FontString, FontString, FontString
local prevButton, nextButton ---@type Button, Button
local page = 1
local openedWithBags = false
local focused ---@type table?

-- Ears in display order: newest first.
local function ordered()
	local db, list = ns.db, {}
	if not db then
		return list
	end
	for i = #db.ears, 1, -1 do
		list[#list + 1] = db.ears[i]
	end
	return list
end

local function pageCount(total)
	return math.max(1, math.ceil(total / Pouch.PER_PAGE))
end

---@param ear table
---@return string
local function className(ear)
	local token = ear.class
	return ear.className or (token and LOCALIZED_CLASS_NAMES_MALE[token]) or token or "Unknown class"
end

---@param ear table
---@return string
local function classColored(ear)
	local name = className(ear)
	local color = ear.class and C_ClassColor.GetClassColor(ear.class)
	if color then
		return ("|c%s%s|r"):format(color:GenerateHexColor(), name)
	end
	return name
end

--- The tooltip for an ear, as lines: { text, r, g, b } or { left, right, r, g, b }.
--- Pure, so specs can check it without a tooltip widget.
---@param ear table
---@return table[]
function Pouch.TooltipLines(ear)
	local quality = ns.QUALITY[ear.quality] or ns.QUALITY[2]
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
	local level = ear.level and tostring(ear.level) or "??"
	local race = ear.raceName or ear.race or ""
	local atlas = Chat.RaceAtlas(ear.race, ear.sex)
	if atlas then
		race = ("|A:%s:14:14|a %s"):format(atlas, race)
	end
	add((("Level %s %s %s"):format(level, race, classColored(ear)):gsub("  ", " ")))
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
	if not slot.ear then
		return
	end
	GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
	for _, line in ipairs(Pouch.TooltipLines(slot.ear)) do
		if line.left then
			GameTooltip:AddDoubleLine(line.left, line.right, 1, 1, 1, line.r, line.g, line.b)
		else
			GameTooltip:AddLine(line.text, line.r, line.g, line.b, true)
		end
	end
	GameTooltip:Show()
end

local function hideTooltip()
	GameTooltip:Hide()
end

local function savePosition()
	if not frame or not ns.db then
		return
	end
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	ns.db.ui.pouch = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function restorePosition()
	if not frame then
		return
	end
	frame:ClearAllPoints()
	local saved = ns.db and ns.db.ui.pouch
	if
		type(saved) == "table"
		and type(saved.point) == "string"
		and type(saved.relativePoint) == "string"
		and type(saved.x) == "number"
		and type(saved.y) == "number"
	then
		frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
	else
		frame:SetPoint("RIGHT", UIParent, "RIGHT", -420, 40)
	end
end

local function newSlot(parent, index)
	local slot = CreateFrame("Button", nil, parent) --[[@as EarCollector.Slot]]
	slot:SetSize(SLOT, SLOT)
	local column = (index - 1) % Pouch.COLUMNS
	local row = math.floor((index - 1) / Pouch.COLUMNS)
	slot:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + column * (SLOT + GAP), -(36 + row * (SLOT + GAP)))

	local bg = slot:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.55)

	slot.icon = slot:CreateTexture(nil, "ARTWORK")
	slot.icon:SetPoint("TOPLEFT", 2, -2)
	slot.icon:SetPoint("BOTTOMRIGHT", -2, 2)

	-- A quality-colored border from four thin textures: no art assets needed.
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
	if not ear then
		slot.icon:Hide()
		slot.count:SetText("")
		for _, edge in ipairs(slot.edges) do
			edge:Hide()
		end
		slot:SetAlpha(0.6)
		return
	end
	slot:SetAlpha(1)
	slot.icon:SetTexture(Art.EarTexture(ear.race, ear.guid))
	slot.icon:SetDesaturated(ear.quality == 0)
	slot.icon:Show()
	local quality = ns.QUALITY[ear.quality] or ns.QUALITY[2]
	for _, edge in ipairs(slot.edges) do
		edge:SetColorTexture(quality.r, quality.g, quality.b, 1)
		edge:Show()
	end
	slot.count:SetText(ear.camped and ear.camped > 0 and tostring(ear.camped + 1) or "")
end

--- Let Escape close the pouch, the way it closes Blizzard's windows.
---
--- On Forever, Escape runs ToggleGameMenu (Blizzard_GameMenuEsc). It offers the
--- key to registered handlers in priority order (dialogs, menus, casting, the
--- game menu, ...) and opens the game menu only if none of them took it. One
--- handler is CloseAllWindows, which closes the bags, then hides every shown
--- frame named in UISpecialFrames. It reads that list inside securecall, because
--- addons add to it: their entries can't taint the rest of Escape. So pressing
--- Escape with the pouch open closes it without also opening the game menu. The
--- pouch isn't a protected frame, so this works in combat too.
---
--- Rejected, after reading Forever's UI source:
--- - RegisterGameMenuEscHandler: only Blizzard's code calls it. A call from an
---   addon would write and re-sort Blizzard's handler list while tainted, so every
---   Escape would run tainted and SpellStopCasting / ClearTarget would be blocked.
--- - OnKeyDown with SetPropagateKeyboardInput: that method is restricted in
---   combat, so the pouch would either swallow every key or let Escape through.
--- - A hooksecurefunc post-hook on ToggleGameMenu: it can't claim the key, so
---   the game menu would open as well.
---
--- Called once, from build. Without the list (a future client), the close
--- button still works.
---@param name string the frame's global name
local function closeOnEscape(name)
	if type(UISpecialFrames) == "table" then
		table.insert(UISpecialFrames, name)
	end
end

-- Ears tab: the grid of ears, newest first.
local function buildEars(panel)
	countText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -30)
	countText:SetJustifyH("RIGHT")

	for i = 1, Pouch.PER_PAGE do
		slots[i] = newSlot(panel, i)
	end

	emptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	emptyText:SetPoint("CENTER", panel, "CENTER", 0, 0)
	emptyText:SetWidth(Pouch.WIDTH - 2 * PAD - 20)
	emptyText:SetText("No ears yet. Kill an enemy player in the open world, with your group or on your own.")
end

local function refreshEars()
	local ears = ordered()
	local pages = pageCount(#ears)
	page = math.min(math.max(page, 1), pages)
	local first = (page - 1) * Pouch.PER_PAGE
	for i, slot in ipairs(slots) do
		fillSlot(slot, ears[first + i])
		if focused and slot.ear == focused then
			slot:LockHighlight()
		else
			slot:UnlockHighlight()
		end
	end
	local assists = 0
	for _, ear in ipairs(ears) do
		if ear.by == "assist" then
			assists = assists + 1
		end
	end
	countText:SetText(("%d ears, %d assists"):format(#ears, assists))
	emptyText:SetShown(#ears == 0)
end

---@class EarCollector.PouchTab
---@field title string
---@field build fun(panel: Frame) creates the tab's widgets on `panel`, once
---@field refresh fun() redraws the tab while it is showing
---@field pages (fun(): integer, integer)? current page and page count, for a paged tab
---@field setPage fun(n: integer)? turns to page n (the tab clamps it when it refreshes)
---@field panel Frame?
---@field button Button?
---@field broken boolean? set when build failed: the tab is skipped

---@type EarCollector.PouchTab[]
local tabs = {
	{
		title = "Ears",
		build = buildEars,
		refresh = refreshEars,
		pages = function()
			return page, pageCount(ns.db and #ns.db.ears or 0)
		end,
		setPage = function(n)
			page = n
		end,
	},
}
local activeIndex = 1

--- Add a tab to the pouch (UI/LedgerTab.lua, UI/RivalsTab.lua). Tabs are built
--- with the window, so call this while the addon loads.
---@param tab EarCollector.PouchTab
---@return boolean added
function Pouch.AddTab(tab)
	if frame then
		return false
	end
	tabs[#tabs + 1] = tab
	return true
end

-- The page buttons belong to the window and page whichever tab is showing;
-- a tab without pages hides them.
local function updatePaging()
	local tab = tabs[activeIndex]
	local current, pages = 1, 1
	local paged = tab.pages ~= nil and not tab.broken
	if paged then
		local ok, p, n = Errors.Call("pouch " .. tab.title, tab.pages)
		if ok and type(p) == "number" and type(n) == "number" then
			current, pages = p, n
		end
	end
	prevButton:SetShown(paged)
	nextButton:SetShown(paged)
	pageText:SetShown(paged)
	pageText:SetText(("Page %d / %d"):format(current, pages))
	prevButton:SetEnabled(current > 1)
	nextButton:SetEnabled(current < pages)
end

local function build()
	local f = CreateFrame("Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
	---@cast f EarCollector.PouchFrame
	frame = f
	-- New frames start shown. Hide before the OnHide script exists, so building
	-- the window doesn't run its close handler (which clears a focused ear).
	f:Hide()
	f:SetSize(Pouch.WIDTH, Pouch.HEIGHT)
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript(
		"OnDragStart",
		Errors.Wrap("pouch move", function()
			f:StartMoving()
		end)
	)
	f:SetScript(
		"OnDragStop",
		Errors.Wrap("pouch move", function()
			f:StopMovingOrSizing()
			savePosition()
		end)
	)
	f:EnableMouseWheel(true)
	f:SetScript(
		"OnMouseWheel",
		Errors.Wrap("pouch paging", function(_, delta)
			Pouch.SetPage((Pouch.GetPage()) - delta)
		end)
	)
	f:SetScript(
		"OnHide",
		Errors.Wrap("pouch close", function()
			openedWithBags = false
			focused = nil
			hideTooltip()
		end)
	)
	f.TitleText:SetText("Ear Pouch")

	-- One panel per tab, the size of the window, and Blizzard's tab buttons under it.
	for i, tab in ipairs(tabs) do
		local panel = CreateFrame("Frame", nil, f)
		panel:SetAllPoints()
		panel:SetShown(i == activeIndex)
		tab.panel = panel
		if not Errors.Call("pouch " .. tab.title, tab.build, panel) then
			tab.broken = true
		end
		local button = CreateFrame("Button", nil, f, "PanelTabButtonTemplate") --[[@as Button]]
		button:SetID(i)
		button:SetText(tab.title)
		button:SetScript(
			"OnClick",
			Errors.Wrap("pouch tabs", function()
				hideTooltip()
				if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
					PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB, "SFX")
				end
				Pouch.SelectTab(i)
			end)
		)
		tab.button = button
	end
	tabs[1].button:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 11, 2)
	PanelTemplates_SetNumTabs(f, #tabs)
	PanelTemplates_SetTab(f, activeIndex)

	prevButton = CreateFrame("Button", nil, f)
	prevButton:SetSize(26, 26)
	prevButton:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD - 4, 6)
	prevButton:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
	prevButton:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
	prevButton:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
	prevButton:SetScript(
		"OnClick",
		Errors.Wrap("pouch paging", function()
			Pouch.SetPage((Pouch.GetPage()) - 1)
		end)
	)

	nextButton = CreateFrame("Button", nil, f)
	nextButton:SetSize(26, 26)
	nextButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PAD - 4), 6)
	nextButton:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
	nextButton:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
	nextButton:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
	nextButton:SetScript(
		"OnClick",
		Errors.Wrap("pouch paging", function()
			Pouch.SetPage((Pouch.GetPage()) + 1)
		end)
	)

	pageText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	pageText:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)

	restorePosition()
	closeOnEscape(FRAME_NAME)
end

--- Redraw the showing tab, if the pouch is open.
function Pouch.Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	local tab = tabs[activeIndex]
	if not tab.broken then
		Errors.Call("pouch " .. tab.title, tab.refresh)
	end
	updatePaging()
end

--- Show a tab, by index or title. Before the window is built, it is the tab the
--- window will open on.
---@param which integer|string
function Pouch.SelectTab(which)
	for i, tab in ipairs(tabs) do
		if i == which or tab.title == which then
			activeIndex = i
		end
	end
	if not frame then
		return
	end
	for i, tab in ipairs(tabs) do
		tab.panel:SetShown(i == activeIndex)
	end
	PanelTemplates_SetTab(frame, activeIndex)
	Pouch.Refresh()
end

---@return string title of the showing tab
function Pouch.ActiveTab()
	return tabs[activeIndex].title
end

---@return string[] titles in tab order
function Pouch.TabTitles()
	local titles = {}
	for i, tab in ipairs(tabs) do
		titles[i] = tab.title
	end
	return titles
end

--- Turn the showing tab to page n.
---@param n integer
function Pouch.SetPage(n)
	local tab = tabs[activeIndex]
	if tab.setPage then
		tab.setPage(n)
	end
	Pouch.Refresh()
end

--- The showing tab's page and page count (1, 1 for a tab without pages).
---@return integer page, integer pages
function Pouch.GetPage()
	local tab = tabs[activeIndex]
	if tab.pages then
		return tab.pages()
	end
	return 1, 1
end

function Pouch.IsShown()
	return frame ~= nil and frame:IsShown()
end

function Pouch.Show()
	if not ns.db then
		return
	end
	if not frame then
		build()
	end
	if frame and not frame:IsShown() then
		frame:Show()
	end
	Pouch.Refresh()
end

function Pouch.Hide()
	if frame then
		frame:Hide()
	end
end

function Pouch.Toggle()
	if Pouch.IsShown() then
		Pouch.Hide()
	else
		openedWithBags = false
		Pouch.Show()
	end
end

--- Bags opened: show the pouch beside them, remembering that the bags opened it.
function Pouch.ShowWithBags()
	if Pouch.IsShown() then
		return
	end
	Pouch.Show()
	openedWithBags = Pouch.IsShown()
end

--- Bags closed: close the pouch only if the bags opened it.
function Pouch.HideWithBags()
	if openedWithBags then
		Pouch.Hide()
	end
end

--- Open the pouch on one ear: the Ears tab, turned to its page, with the ear
--- highlighted and its tooltip showing.
---@param guid string
---@param at number
---@return boolean found
function Pouch.FocusEar(guid, at)
	local ears = ordered()
	for index, ear in ipairs(ears) do
		if ear.guid == guid and ear.at == at then
			focused = ear
			page = math.floor((index - 1) / Pouch.PER_PAGE) + 1
			Pouch.SelectTab(1)
			Pouch.Show()
			local slot = slots[(index - 1) % Pouch.PER_PAGE + 1]
			if slot then
				showTooltip(slot)
			end
			return true
		end
	end
	return false
end

--- The slot widgets, for specs.
---@return EarCollector.Slot[]
function Pouch.Slots()
	return slots
end

--- The labels and page buttons, for specs.
function Pouch.Widgets()
	return { count = countText, page = pageText, empty = emptyText, prev = prevButton, next = nextButton }
end
