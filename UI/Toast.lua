-- The pop-up when you collect an ear (or lose one), in Blizzard's loot-toast
-- art: the ear, its name in the grade colour, a detail line, and a loot sound.
-- Pop-ups stack upward from bottom centre, or wherever you move them
-- (UI/ToastMover.lua). Left-click
-- opens the pouch, right-click dismisses, hovering pauses. Own frames and
-- animation groups, so nothing is tainted and nothing runs every frame.
local _, ns = ...

local Art, Chat, Errors = ns.Art, ns.Chat, ns.Errors

local Toast = {}
ns.Toast = Toast

Toast.MAX = 3 -- on screen at once; the oldest makes way for a new one
Toast.HOLD = 4 -- seconds on screen before fading
Toast.FADE = 0.6
Toast.WIDTH, Toast.HEIGHT, Toast.GAP = 300, 58, 6
Toast.ANCHOR = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 260 } -- above the action bars
Toast.SOUND_GAP = 2 -- seconds; within it only a grander sound plays

-- Blizzard's loot-toast sounds (SoundKitConstants) and how grand each is.
local SOUNDS = {
	[1] = { name = "UI_RAID_LOOT_TOAST_LESSER_ITEM_WON", tier = 1 },
	[2] = { name = "UI_RAID_LOOT_TOAST_LESSER_ITEM_WON", tier = 1 },
	[3] = { name = "UI_EPICLOOT_TOAST", tier = 2 },
	[4] = { name = "UI_EPICLOOT_TOAST", tier = 2 },
	[5] = { name = "UI_LEGENDARY_LOOT_TOAST", tier = 3 },
}
-- Blizzard's loot-toast art (Blizzard_FrameXML/Mainline/AlertFrameSystems).
local ICON_BORDER = { [2] = "green", [3] = "blue", [4] = "purple", [5] = "orange" }
local DEATH_RED = { 0.75, 0.12, 0.1 }
local HINT_EAR = "Click to open in your pouch. Right-click to dismiss."
local HINT_DEATH = "Click to see your rivals. Right-click to dismiss."

---@class EarCollector.Toast : Button
---@field bg Texture
---@field glow Texture
---@field iconBorder Texture
---@field icon Texture
---@field label FontString
---@field title FontString
---@field detail FontString
---@field appear AnimationGroup
---@field leave AnimationGroup
---@field fadeOut Alpha
---@field ear table? the ear it shows
---@field death table? or the death

local pool = {} ---@type EarCollector.Toast[]
local active = {} ---@type EarCollector.Toast[] newest first
local lastSound = { at = -math.huge, tier = 0 }

local function hasAtlas(atlas)
	return C_Texture.GetAtlasInfo(atlas) ~= nil
end

-- An atlas if the client has it, else a flat colour.
local function paint(texture, atlas, r, g, b, a)
	if atlas and hasAtlas(atlas) then
		texture:SetAtlas(atlas)
		texture:SetVertexColor(1, 1, 1)
	else
		texture:SetColorTexture(r, g, b, a)
	end
end

--- Where the first pop-up sits: where you moved them, or above the action bars.
---@return { point: string, relativePoint: string, x: number, y: number }
function Toast.Anchor()
	local saved = ns.db and ns.db.ui.toast
	if
		type(saved) == "table"
		and type(saved.point) == "string"
		and type(saved.relativePoint) == "string"
		and type(saved.x) == "number"
		and type(saved.y) == "number"
	then
		return saved
	end
	return Toast.ANCHOR
end

local function layout()
	local a = Toast.Anchor()
	for i, toast in ipairs(active) do
		toast:ClearAllPoints()
		toast:SetPoint(a.point, UIParent, a.relativePoint, a.x, a.y + (i - 1) * (Toast.HEIGHT + Toast.GAP))
	end
end

--- Take a pop-up off the screen and back to the pool. Safe to call twice: a
--- hovered pop-up that's clicked gets OnLeave as it hides.
---@param toast EarCollector.Toast
local function release(toast)
	local index
	for i, t in ipairs(active) do
		if t == toast then
			index = i
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
	toast.ear, toast.death = nil, nil
	pool[#pool + 1] = toast
	layout()
end

--- One line under the name: the grade, level, race and class, then who landed
--- the blow. The label already says "Assist", except on a Vengeance ear.
---@param ear table
---@return string
function Toast.Detail(ear)
	local parts, who = { ns.Quality(ear.quality).name }, {}
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
	elseif ear.by == "assist" and ear.vengeance then
		parts[#parts + 1] = "Assist"
	end
	if ear.vengeance then
		parts[#parts + 1] = ("Avenged %d deaths"):format(ear.vengeance)
	end
	return table.concat(parts, " · ")
end

local function showTooltip(toast)
	local lines
	if toast.ear then
		lines = ns.EarsTab.TooltipLines(toast.ear)
		lines[#lines + 1] = { text = HINT_EAR, r = 0.62, g = 0.62, b = 0.62 }
	elseif toast.death then
		lines = { { text = HINT_DEATH, r = 0.62, g = 0.62, b = 0.62 } }
	end
	if lines then
		Chat.ShowTooltip(toast, "ANCHOR_TOP", lines)
	end
end

---@return EarCollector.Toast
local function build()
	local toast = CreateFrame("Button", nil, UIParent) --[[@as EarCollector.Toast]]
	toast:SetSize(Toast.WIDTH, Toast.HEIGHT)
	toast:SetFrameStrata("HIGH")
	toast:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	toast.bg = toast:CreateTexture(nil, "BACKGROUND")
	toast.bg:SetAllPoints()
	toast.glow = toast:CreateTexture(nil, "BORDER")
	toast.glow:SetAllPoints()
	toast.glow:SetBlendMode("ADD")
	paint(toast.glow, "loottoast-glow", 1, 0.82, 0.3, 0.2)

	toast.iconBorder = toast:CreateTexture(nil, "ARTWORK")
	toast.iconBorder:SetSize(46, 46)
	toast.iconBorder:SetPoint("LEFT", 6, 0)
	toast.icon = toast:CreateTexture(nil, "ARTWORK", nil, -1)
	toast.icon:SetPoint("TOPLEFT", toast.iconBorder, "TOPLEFT", 3, -3)
	toast.icon:SetPoint("BOTTOMRIGHT", toast.iconBorder, "BOTTOMRIGHT", -3, 3)

	toast.label = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	toast.label:SetPoint("TOPLEFT", toast.iconBorder, "TOPRIGHT", 9, -1)
	toast.title = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	toast.title:SetPoint("LEFT", toast.iconBorder, "RIGHT", 9, 0)
	toast.title:SetPoint("RIGHT", toast, "RIGHT", -8, 0)
	toast.title:SetJustifyH("LEFT")
	toast.title:SetWordWrap(false)
	toast.detail = toast:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	toast.detail:SetPoint("BOTTOMLEFT", toast.iconBorder, "BOTTOMRIGHT", 9, 1)
	toast.detail:SetPoint("BOTTOMRIGHT", toast, "BOTTOMRIGHT", -8, 7)
	toast.detail:SetJustifyH("LEFT")
	toast.detail:SetWordWrap(false)

	-- The pop-up and its glow fade in; the glow then fades away; the pop-up leaves later.
	toast.appear = toast:CreateAnimationGroup()
	local fadeIn = toast.appear:CreateAnimation("Alpha") --[[@as Alpha]]
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(0.2)
	local glowOut = toast.appear:CreateAnimation("Alpha") --[[@as Alpha]]
	glowOut:SetTarget(toast.glow)
	glowOut:SetFromAlpha(1)
	glowOut:SetToAlpha(0)
	glowOut:SetStartDelay(0.2)
	glowOut:SetDuration(0.5)

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
			if not toast.ear and not toast.death then
				return -- already released (OnLeave as it hides after a click)
			end
			toast.fadeOut:SetStartDelay(1.5)
			toast.leave:Play()
		end)
	)
	toast:SetScript(
		"OnClick",
		Errors.Wrap("toast", function(_, button)
			local ear, death = toast.ear, toast.death
			release(toast)
			if button == "RightButton" then
				return
			elseif ear then
				ns.EarsTab.Focus(ear.guid, ear.at)
			elseif death then
				ns.Pouch.Open("Rivals")
			end
		end)
	)
	return toast
end

local function playSound(db, quality)
	local sound = SOUNDS[quality]
	if not db.settings.toastSound or not sound or not SOUNDKIT or not SOUNDKIT[sound.name] then
		return -- Poor ears are silent
	end
	local now = GetTime()
	if now - lastSound.at < Toast.SOUND_GAP and sound.tier <= lastSound.tier then
		return -- one sound per burst, unless this one is grander
	end
	lastSound = { at = now, tier = sound.tier }
	PlaySound(SOUNDKIT[sound.name], "SFX")
end

local function present(toast)
	if #active >= Toast.MAX then
		release(active[#active])
	end
	table.insert(active, 1, toast)
	layout()
	toast:SetAlpha(1)
	toast.glow:SetAlpha(1)
	toast:Show()
	toast.appear:Play()
	toast.fadeOut:SetStartDelay(Toast.HOLD)
	toast.leave:Play()
end

--- Pop up a newly collected ear, unless pop-ups are off or it's below the
--- grade the options ask for (a Vengeance ear is Legendary, so it always shows).
---@param ear table
function Toast.Show(ear)
	local db = ns.db
	if not db or not db.settings.toast or (ear.quality or 2) < db.settings.toastMinQuality then
		return
	end
	local toast = table.remove(pool) or build()
	toast.ear, toast.death = ear, nil
	local quality = ns.Quality(ear.quality)
	if ear.vengeance then
		paint(toast.bg, "LegendaryToast-background", 0.16, 0.09, 0.02, 0.95)
	else
		local faction = UnitFactionGroup("player")
		local bg = (faction == "Horde" or faction == "Alliance") and "loottoast-bg-" .. faction:lower()
		paint(toast.bg, bg, 0.06, 0.05, 0.04, 0.92)
	end
	local border = ICON_BORDER[ear.quality] or "white"
	paint(toast.iconBorder, "loottoast-itemborder-" .. border, quality.r, quality.g, quality.b, 1)
	toast.icon:SetTexture(Art.EarTexture(ear.race, ear.guid))
	toast.icon:SetDesaturated(ear.quality == 0)
	local label = ear.by == "assist" and "Assist collected" or "Ear collected"
	toast.label:SetText(ear.vengeance and "Vengeance!" or label)
	toast.title:SetText(("|c%s%s's Ear|r"):format(quality.color, ear.name))
	toast.detail:SetText(Toast.Detail(ear))
	present(toast)
	playSound(db, ear.quality)
end

--- Pop up a death to an enemy player: "Grimbash took your ear", in red.
---@param death table
---@param debt integer deaths to them since you last killed them, this one included
function Toast.ShowDeath(death, debt)
	local db = ns.db
	if not db or not db.settings.toast then
		return
	end
	local toast = table.remove(pool) or build()
	toast.ear, toast.death = nil, death
	toast.bg:SetColorTexture(0.18, 0.03, 0.02, 0.92)
	toast.iconBorder:SetColorTexture(DEATH_RED[1], DEATH_RED[2], DEATH_RED[3], 1)
	toast.icon:SetTexture(Art.EarTexture(death.race, death.guid))
	toast.icon:SetDesaturated(true)
	toast.label:SetText("|cffff4a3aEar lost|r")
	toast.title:SetText(Chat.InClassColour(death.name, death.class) .. " took your ear")
	if debt >= ns.Deaths.VENGEANCE then
		toast.detail:SetText(("|c%sVengeance owed:|r their next ear is Legendary"):format(ns.QUALITY[5].color))
	elseif debt > 1 then
		toast.detail:SetText(("Killed you %d times since you last killed them"):format(debt))
	else
		toast.detail:SetText(
			Chat.ClassName(death.class) .. (death.level and (" · Level %d"):format(death.level) or "")
		)
	end
	present(toast)
end

--- Save where pop-ups appear, for the account, and move any on screen.
function Toast.SetAnchor(point, relativePoint, x, y)
	if ns.db then
		ns.db.ui.toast = { point = point, relativePoint = relativePoint, x = x, y = y }
	end
	layout()
end

--- Pop-ups on screen, newest first (for specs).
---@return EarCollector.Toast[]
function Toast.Active()
	return active
end
