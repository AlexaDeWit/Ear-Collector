-- The grade buttons at the top of the Ears tab: one per grade, to hide or show
-- its ears. A hidden grade's button is dimmed and crossed out. The choice is
-- saved per character in db.hiddenGrades.
local _, ns = ...

local Chat, Errors, Pouch = ns.Chat, ns.Errors, ns.Pouch

local GradeFilter = {}
ns.GradeFilter = GradeFilter

GradeFilter.SIZE, GradeFilter.GAP = 14, 3
local SIZE = GradeFilter.SIZE

---@class EarCollector.GradeButton : Button
---@field grade integer
---@field edge Texture
---@field swatch Texture
---@field slash Texture

local buttons = {} ---@type EarCollector.GradeButton[]
local counts = {} ---@type table<integer, integer> ears of each grade, hidden or not

local function isHidden(grade)
	return ns.db ~= nil and ns.db.hiddenGrades[grade] == true
end

local function showTooltip(button)
	local quality, hidden = ns.Quality(button.grade), isHidden(button.grade)
	local count = Chat.Count(counts[button.grade] or 0, "ear")
	Chat.ShowTooltip(button, "ANCHOR_TOP", {
		{ text = quality.name, r = quality.r, g = quality.g, b = quality.b },
		{ text = ("%s, %s"):format(count, hidden and "hidden" or "shown"), r = 1, g = 1, b = 1 },
		{ text = hidden and "Click to show them." or "Click to hide them.", r = 0.62, g = 0.62, b = 0.62 },
	})
end

local function toggle(button)
	local db = ns.db
	if not db then
		return
	end
	local hide = not isHidden(button.grade)
	db.hiddenGrades[button.grade] = hide or nil
	Pouch.PlaySound(hide and "IG_MAINMENU_OPTION_CHECKBOX_OFF" or "IG_MAINMENU_OPTION_CHECKBOX_ON")
	Pouch.Refresh()
	showTooltip(button)
end

local function newButton(panel, grade, x, y)
	local quality = ns.Quality(grade)
	local button = CreateFrame("Button", nil, panel) --[[@as EarCollector.GradeButton]]
	button.grade = grade
	button:SetSize(SIZE, SIZE)
	button:SetPoint("TOPLEFT", panel, "TOPLEFT", x + grade * (SIZE + GradeFilter.GAP), y)

	-- A square in the grade colour, a dark ring, and a smaller square inside.
	button.edge = button:CreateTexture(nil, "BACKGROUND")
	button.edge:SetAllPoints()
	button.edge:SetColorTexture(quality.r, quality.g, quality.b, 1)
	local ring = button:CreateTexture(nil, "BORDER")
	ring:SetPoint("TOPLEFT", 2, -2)
	ring:SetPoint("BOTTOMRIGHT", -2, 2)
	ring:SetColorTexture(0.04, 0.04, 0.03, 1)
	button.swatch = button:CreateTexture(nil, "ARTWORK")
	button.swatch:SetPoint("TOPLEFT", 4, -4)
	button.swatch:SetPoint("BOTTOMRIGHT", -4, 4)
	button.swatch:SetColorTexture(quality.r, quality.g, quality.b, 1)

	button.slash = button:CreateTexture(nil, "OVERLAY")
	button.slash:SetSize(SIZE + 4, 2)
	button.slash:SetPoint("CENTER")
	button.slash:SetColorTexture(1, 0.29, 0.23, 1)
	button.slash:SetRotation(math.rad(45))

	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.25)

	button:SetScript(
		"OnClick",
		Errors.Wrap("pouch filter", function()
			toggle(button)
		end)
	)
	button:SetScript(
		"OnEnter",
		Errors.Wrap("pouch filter", function()
			showTooltip(button)
		end)
	)
	button:SetScript(
		"OnLeave",
		Errors.Wrap("pouch filter", function()
			GameTooltip:Hide()
		end)
	)
	return button
end

--- Create the buttons in a row, Poor to Legendary, from (x, y) on `panel`.
---@param panel Frame
---@param x number
---@param y number
function GradeFilter.Build(panel, x, y)
	for grade = 0, #ns.QUALITY do
		buttons[#buttons + 1] = newButton(panel, grade, x, y)
	end
end

--- Redraw the buttons for `ears`: every ear, hidden or not.
---@param ears table[]
function GradeFilter.Update(ears)
	counts = {}
	for _, ear in ipairs(ears) do
		counts[ear.quality] = (counts[ear.quality] or 0) + 1
	end
	for _, button in ipairs(buttons) do
		local hidden = isHidden(button.grade)
		button.edge:SetAlpha(hidden and 0.35 or 1)
		button.swatch:SetAlpha(hidden and 0.35 or 1)
		button.slash:SetShown(hidden)
	end
end

--- The buttons, Poor first (for specs).
---@return EarCollector.GradeButton[]
function GradeFilter.Buttons()
	return buttons
end
