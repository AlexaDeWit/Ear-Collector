-- Moving the pop-ups: a stand-in pop-up you drag where they should appear,
-- then right-click. Opened from the options or /ears popup move.
local _, ns = ...

local Errors, Toast = ns.Errors, ns.Toast

local mover ---@type Button?

local function build()
	local frame = CreateFrame("Button", nil, UIParent)
	frame:SetSize(Toast.WIDTH, Toast.HEIGHT)
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:RegisterForClicks("RightButtonUp")
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.1, 0.3, 0.6, 0.7)
	local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("CENTER")
	text:SetText("Ear Collector pop-ups\nDrag to move. Right-click when done.")
	frame:SetScript(
		"OnDragStart",
		Errors.Wrap("toast move", function()
			frame:StartMoving()
		end)
	)
	frame:SetScript(
		"OnDragStop",
		Errors.Wrap("toast move", function()
			frame:StopMovingOrSizing()
			local point, _, relativePoint, x, y = frame:GetPoint(1)
			Toast.SetAnchor(point, relativePoint, x, y)
		end)
	)
	frame:SetScript(
		"OnClick",
		Errors.Wrap("toast move", function()
			frame:Hide()
		end)
	)
	return frame
end

--- Show the stand-in where pop-ups appear now.
function Toast.Move()
	mover = mover or build()
	local a = Toast.Anchor()
	mover:ClearAllPoints()
	mover:SetPoint(a.point, UIParent, a.relativePoint, a.x, a.y)
	mover:Show()
end

--- The stand-in Toast.Move shows (for specs).
function Toast.Mover()
	return mover
end
