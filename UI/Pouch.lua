-- The Ear Pouch window: Blizzard's frame template, a tab strip, and page buttons
-- for whichever tab is showing. The tabs (EarsTab, LedgerTab, RivalsTab)
-- register with Pouch.AddTab. Built on first open; showing and hiding it is
-- allowed in combat, and Escape closes it.
local addonName, ns = ...

local Errors = ns.Errors

local Pouch = {}
ns.Pouch = Pouch

-- The window is sized for a grid of ear slots; the other tabs lay out inside it.
Pouch.COLUMNS, Pouch.ROWS = 8, 5
Pouch.PER_PAGE = Pouch.COLUMNS * Pouch.ROWS
Pouch.SLOT, Pouch.GAP, Pouch.PAD = 36, 4, 12
Pouch.GRID_TOP = 44 -- below the title bar and a line of text
Pouch.WIDTH = Pouch.PAD * 2 + Pouch.COLUMNS * Pouch.SLOT + (Pouch.COLUMNS - 1) * Pouch.GAP
Pouch.HEIGHT = Pouch.GRID_TOP + Pouch.ROWS * (Pouch.SLOT + Pouch.GAP) + 34

local FRAME_NAME = addonName .. "Pouch"
local PAD = Pouch.PAD

---@class EarCollector.PouchFrame : Frame
---@field TitleText FontString
---@field CloseButton Button

---@class EarCollector.PouchTab
---@field title string
---@field build fun(panel: Frame) creates the tab's widgets on `panel`, once
---@field refresh fun() redraws the tab while it is showing
---@field pages (fun(): integer, integer)? current page and page count, for a paged tab
---@field setPage fun(n: integer)? turns to page n (the tab clamps it when it refreshes)
---@field onHide fun()? runs when the window closes
---@field panel Frame?
---@field button Button?
---@field broken boolean? set when build failed: the tab is skipped

local frame ---@type EarCollector.PouchFrame?
local pageText ---@type FontString
local prevButton, nextButton ---@type Button, Button
local openedWithBags = false
local buildFailed = false -- the pouch stays closed until /reload
local tabs = {} ---@type EarCollector.PouchTab[]
local activeIndex = 1

local function hideTooltip()
	GameTooltip:Hide()
end

--- Play one of Blizzard's interface sounds by its SOUNDKIT name, if the client has it.
---@param name string
function Pouch.PlaySound(name)
	if SOUNDKIT and SOUNDKIT[name] then
		PlaySound(SOUNDKIT[name], "SFX")
	end
end
local playSound = Pouch.PlaySound

local function savePosition()
	if frame and ns.db then
		local point, _, relativePoint, x, y = frame:GetPoint(1)
		ns.db.ui.pouch = { point = point, relativePoint = relativePoint, x = x, y = y }
	end
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

--- Add a tab. Tabs are built with the window, so call this while the addon loads.
---@param tab EarCollector.PouchTab
---@return boolean added
function Pouch.AddTab(tab)
	if frame then
		return false
	end
	tabs[#tabs + 1] = tab
	return true
end

-- Page buttons for the showing tab; a tab without pages hides them.
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

local function pageButton(direction, point, x)
	local button = CreateFrame("Button", nil, frame)
	button:SetSize(26, 26)
	button:SetPoint(point, frame, point, x, 6)
	local name = direction < 0 and "Prev" or "Next"
	button:SetNormalTexture(("Interface\\Buttons\\UI-SpellbookIcon-%sPage-Up"):format(name))
	button:SetPushedTexture(("Interface\\Buttons\\UI-SpellbookIcon-%sPage-Down"):format(name))
	button:SetDisabledTexture(("Interface\\Buttons\\UI-SpellbookIcon-%sPage-Disabled"):format(name))
	button:SetScript(
		"OnClick",
		Errors.Wrap("pouch paging", function()
			playSound("IG_ABILITY_PAGE_TURN")
			Pouch.SetPage((Pouch.GetPage()) + direction)
		end)
	)
	return button
end

local function build()
	local f = CreateFrame("Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
	---@cast f EarCollector.PouchFrame
	frame = f
	-- New frames start shown: hide before OnHide exists so building runs no close handler.
	f:Hide()
	f:SetSize(Pouch.WIDTH, Pouch.HEIGHT)
	f:SetFrameStrata("MEDIUM") -- like Blizzard's panels, raised above them when clicked
	f:SetToplevel(true)
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
			if not openedWithBags then
				playSound("IG_BACKPACK_CLOSE") -- the bags play their own
			end
			openedWithBags = false
			hideTooltip()
			for _, tab in ipairs(tabs) do
				if tab.onHide then
					tab.onHide()
				end
			end
		end)
	)
	f.TitleText:SetText("Ear Pouch")

	-- A panel per tab, the size of the window, with Blizzard's tab buttons under it.
	for i, tab in ipairs(tabs) do
		local panel = CreateFrame("Frame", nil, f)
		panel:SetAllPoints()
		panel:SetShown(i == activeIndex)
		tab.panel = panel
		tab.broken = not Errors.Call("pouch " .. tab.title, tab.build, panel)
		local button = CreateFrame("Button", nil, f, "PanelTabButtonTemplate") --[[@as Button]]
		button:SetID(i)
		button:SetText(tab.title)
		button:SetScript(
			"OnClick",
			Errors.Wrap("pouch tabs", function()
				hideTooltip()
				playSound("IG_CHARACTER_INFO_TAB")
				Pouch.SelectTab(i)
			end)
		)
		tab.button = button
	end
	tabs[1].button:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 11, 2)
	PanelTemplates_SetNumTabs(f, #tabs)
	PanelTemplates_SetTab(f, activeIndex)

	prevButton = pageButton(-1, "BOTTOMLEFT", PAD - 4)
	nextButton = pageButton(1, "BOTTOMRIGHT", -(PAD - 4))
	pageText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	pageText:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)

	restorePosition()
	-- Escape closes the frames named in UISpecialFrames, a list Blizzard reads
	-- inside securecall, so this entry can't taint Escape (docs/architecture.md).
	if type(UISpecialFrames) == "table" then
		table.insert(UISpecialFrames, FRAME_NAME)
	end
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

--- Show a tab, by index or title. Before the window is built, it's the tab the
--- window opens on.
---@param which integer|string
function Pouch.SelectTab(which)
	for i, tab in ipairs(tabs) do
		if i == which or tab.title == which then
			activeIndex = i
		end
	end
	if frame then
		for i, tab in ipairs(tabs) do
			tab.panel:SetShown(i == activeIndex)
		end
		PanelTemplates_SetTab(frame, activeIndex)
		Pouch.Refresh()
	end
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

--- Show the window. `quiet` skips the opening sound, for when the bags play theirs.
---@param quiet boolean?
function Pouch.Show(quiet)
	if not ns.db or buildFailed then
		return
	end
	-- All or nothing: a half-built window would fail on every refresh.
	if not frame and not Errors.Call("pouch", build) then
		buildFailed = true
		if frame then
			frame:Hide()
		end
		frame = nil
		return
	end
	if frame and not frame:IsShown() then
		frame:Show()
		if not quiet then
			playSound("IG_BACKPACK_OPEN")
		end
	end
	Pouch.Refresh()
end

function Pouch.Hide()
	if frame then
		frame:Hide()
	end
end

--- Open the pouch because you asked for it (so closing the bags leaves it open),
--- optionally on one tab.
---@param tab (integer|string)?
function Pouch.Open(tab)
	if tab then
		Pouch.SelectTab(tab)
	end
	openedWithBags = false
	Pouch.Show()
end

function Pouch.Toggle()
	if Pouch.IsShown() then
		Pouch.Hide()
	else
		Pouch.Open()
	end
end

--- Bags opened: show the pouch beside them, remembering that the bags opened it.
function Pouch.ShowWithBags()
	if not Pouch.IsShown() then
		Pouch.Show(true)
		openedWithBags = Pouch.IsShown()
	end
end

--- Bags closed: close the pouch only if the bags opened it.
function Pouch.HideWithBags()
	if openedWithBags then
		Pouch.Hide()
	end
end

--- The page labels and buttons, for specs.
function Pouch.Widgets()
	return { page = pageText, prev = prevButton, next = nextButton }
end
