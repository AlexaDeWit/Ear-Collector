-- Loot toast: a small pop-up when you collect an ear, with the ear art, the
-- victim's name in its grade colour, who landed the blow, and a loot sound.
-- Left-click opens the pouch on that ear; right-click dismisses; hovering pauses
-- it and shows the ear's tooltip.
--
-- Our own frames, anchored to UIParent: Blizzard's alert system isn't touched,
-- so nothing is tainted. Fading uses animation groups (no OnUpdate), and every
-- script runs inside Errors.Wrap.
local _, ns = ...

local Art, Errors = ns.Art, ns.Errors

local Toast = {}
ns.Toast = Toast

Toast.MAX = 3 -- toasts on screen at once; the oldest makes way for a new one
Toast.HOLD = 4 -- seconds on screen before fading
Toast.FADE = 0.6
Toast.WIDTH, Toast.HEIGHT, Toast.GAP = 300, 54, 6
Toast.TOP = -150 -- offset of the first toast from the top of the screen

-- Blizzard's loot-toast sounds (SoundKitConstants), by ear grade.
local SOUND_BY_QUALITY = {
	[0] = "UI_RAID_LOOT_TOAST_LESSER_ITEM_WON",
	[1] = "UI_RAID_LOOT_TOAST_LESSER_ITEM_WON",
	[2] = "UI_RAID_LOOT_TOAST_LESSER_ITEM_WON",
	[3] = "UI_EPICLOOT_TOAST",
	[4] = "UI_EPICLOOT_TOAST",
	[5] = "UI_LEGENDARY_LOOT_TOAST",
}

---@class EarCollector.Toast : Button
---@field icon Texture
---@field edges Texture[]
---@field label FontString
---@field title FontString
---@field detail FontString
---@field appear AnimationGroup
---@field leave AnimationGroup
---@field fadeOut Alpha
---@field ear table?

local pool = {} ---@type EarCollector.Toast[]
local active = {} ---@type EarCollector.Toast[] newest first

local function layout()
	for i, toast in ipairs(active) do
		toast:ClearAllPoints()
		toast:SetPoint("TOP", UIParent, "TOP", 0, Toast.TOP - (i - 1) * (Toast.HEIGHT + Toast.GAP))
	end
end

--- Take a toast off the screen and back to the pool. Safe to call twice: a
--- hovered toast that is clicked gets OnLeave as it hides, and the fade that
--- replays would release it again, putting it in the pool twice.
---@param toast EarCollector.Toast
local function release(toast)
	local index
	for i, t in ipairs(active) do
		if t == toast then
			index = i
			break
		end
	end
	if not index then
		return
	end
	table.remove(active, index)
	toast.appear:Stop()
	toast.leave:Stop()
	toast:Hide()
	if GameTooltip:IsOwned(toast) then
		GameTooltip:Hide()
	end
	toast.ear = nil
	pool[#pool + 1] = toast
	layout()
end

--- One line under the name: level, race and class, then who landed the blow.
---@param ear table
---@return string
function Toast.Detail(ear)
	local parts, who = {}, {}
	for _, part in ipairs({
		ear.level and ("Level %d"):format(ear.level) or false,
		ear.raceName or ear.race or false,
		ear.className or false,
	}) do
		if part then
			who[#who + 1] = part
		end
	end
	if #who > 0 then
		parts[#parts + 1] = table.concat(who, " ")
	end
	if ear.by == "group" then
		parts[#parts + 1] = ("Killing blow: %s"):format(ear.killer or "your group")
	elseif ear.by == "assist" then
		parts[#parts + 1] = "Assist"
	end
	if ear.vengeance then
		parts[#parts + 1] = ("Avenged %d deaths"):format(ear.vengeance)
	end
	return table.concat(parts, " · ")
end

local function showTooltip(toast)
	if not toast.ear then
		return
	end
	ns.Chat.ShowTooltip(toast, "ANCHOR_BOTTOM", ns.EarsTab.TooltipLines(toast.ear))
end

---@return EarCollector.Toast
local function build()
	local toast = CreateFrame("Button", nil, UIParent) --[[@as EarCollector.Toast]]
	toast:SetSize(Toast.WIDTH, Toast.HEIGHT)
	toast:SetFrameStrata("HIGH")
	toast:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	local bg = toast:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.06, 0.05, 0.04, 0.9)
	local border = toast:CreateTexture(nil, "BORDER")
	border:SetPoint("TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", 1, -1)
	border:SetColorTexture(0.6, 0.48, 0.27, 0.9)

	local iconBg = toast:CreateTexture(nil, "ARTWORK")
	iconBg:SetSize(44, 44)
	iconBg:SetPoint("LEFT", 5, 0)
	iconBg:SetColorTexture(0, 0, 0, 0.7)
	toast.icon = toast:CreateTexture(nil, "OVERLAY")
	toast.icon:SetPoint("TOPLEFT", iconBg, "TOPLEFT", 2, -2)
	toast.icon:SetPoint("BOTTOMRIGHT", iconBg, "BOTTOMRIGHT", -2, 2)
	toast.edges = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local edge = toast:CreateTexture(nil, "OVERLAY")
		if side == "TOP" or side == "BOTTOM" then
			edge:SetPoint(side .. "LEFT", iconBg, side .. "LEFT")
			edge:SetPoint(side .. "RIGHT", iconBg, side .. "RIGHT")
			edge:SetHeight(2)
		else
			edge:SetPoint("TOP" .. side, iconBg, "TOP" .. side)
			edge:SetPoint("BOTTOM" .. side, iconBg, "BOTTOM" .. side)
			edge:SetWidth(2)
		end
		toast.edges[#toast.edges + 1] = edge
	end

	toast.label = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	toast.label:SetPoint("TOPLEFT", iconBg, "TOPRIGHT", 9, -1)
	toast.title = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	toast.title:SetPoint("LEFT", iconBg, "RIGHT", 9, 0)
	toast.title:SetPoint("RIGHT", toast, "RIGHT", -8, 0)
	toast.title:SetJustifyH("LEFT")
	toast.detail = toast:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	toast.detail:SetPoint("BOTTOMLEFT", iconBg, "BOTTOMRIGHT", 9, 1)
	toast.detail:SetPoint("RIGHT", toast, "RIGHT", -8, 0)
	toast.detail:SetJustifyH("LEFT")

	toast.appear = toast:CreateAnimationGroup()
	local fadeIn = toast.appear:CreateAnimation("Alpha") --[[@as Alpha]]
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(0.2)

	toast.leave = toast:CreateAnimationGroup()
	toast.fadeOut = toast.leave:CreateAnimation("Alpha") --[[@as Alpha]]
	toast.fadeOut:SetFromAlpha(1)
	toast.fadeOut:SetToAlpha(0)
	toast.fadeOut:SetDuration(Toast.FADE)
	toast.leave:SetScript(
		"OnFinished",
		Errors.Wrap("toast", function()
			release(toast)
		end)
	)

	toast:SetScript(
		"OnEnter",
		Errors.Wrap("toast", function()
			toast.leave:Stop()
			toast:SetAlpha(1)
			showTooltip(toast)
		end)
	)
	toast:SetScript(
		"OnLeave",
		Errors.Wrap("toast", function()
			if GameTooltip:IsOwned(toast) then
				GameTooltip:Hide()
			end
			if not toast.ear then
				return -- already released (OnLeave as it hides after a click)
			end
			toast.fadeOut:SetStartDelay(1.5)
			toast.leave:Play()
		end)
	)
	toast:SetScript(
		"OnClick",
		Errors.Wrap("toast", function(_, button)
			local ear = toast.ear
			release(toast)
			if button ~= "RightButton" and ear then
				ns.EarsTab.Focus(ear.guid, ear.at)
			end
		end)
	)
	return toast
end

--- Pop up a toast for a newly collected ear.
---@param ear table
function Toast.Show(ear)
	local db = ns.db
	if not db or not db.settings.toast then
		return
	end
	if #active >= Toast.MAX then
		release(active[#active])
	end
	local toast = table.remove(pool) or build()
	toast.ear = ear

	local quality = ns.Quality(ear.quality)
	toast.icon:SetTexture(Art.EarTexture(ear.race, ear.guid))
	toast.icon:SetDesaturated(ear.quality == 0)
	for _, edge in ipairs(toast.edges) do
		edge:SetColorTexture(quality.r, quality.g, quality.b, 1)
	end
	local label = ear.by == "assist" and "Assist collected" or "You collected"
	toast.label:SetText(ear.vengeance and "Vengeance!" or label)
	toast.title:SetText(("|c%s%s's Ear|r"):format(quality.color, ear.name))
	toast.detail:SetText(Toast.Detail(ear))

	table.insert(active, 1, toast)
	layout()
	toast:SetAlpha(1)
	toast:Show()
	toast.appear:Play()
	toast.fadeOut:SetStartDelay(Toast.HOLD)
	toast.leave:Play()

	local sound = SOUND_BY_QUALITY[ear.quality] or SOUND_BY_QUALITY[2]
	if db.settings.toastSound and SOUNDKIT and SOUNDKIT[sound] then
		PlaySound(SOUNDKIT[sound], "SFX")
	end
end

--- Toasts on screen, newest first (for specs).
---@return EarCollector.Toast[]
function Toast.Active()
	return active
end
