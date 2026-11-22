-- Widgets for the fake client: frames, buttons, textures, font strings, the
-- game tooltip and animation groups. Methods whose state specs inspect are real;
-- any other capitalised method is a no-op so UI code can run.
-- lua-language-server, not these stubs, checks that method names exist.
local Widgets = {}

local state -- the fake client's state, set by Widgets.reset
local animationGroups = {}
local widgetMethods = {}
local function noop() end

local function fire(self, script, ...)
	local handler = self.scripts[script]
	if handler then
		return handler(self, ...)
	end
end

local newWidget

local widgetMeta = {
	__index = function(_, key)
		if widgetMethods[key] then
			return widgetMethods[key]
		end
		if type(key) == "string" and key:find("^%u") then
			return noop -- an unstubbed widget method
		end
		return nil -- an unset field, e.g. slot.ear
	end,
}

newWidget = function(widgetType, name, parent, template)
	local w = setmetatable({
		widgetType = widgetType,
		name = name,
		parent = parent,
		events = {},
		scripts = {},
		points = {},
		shown = true,
		enabled = true,
	}, widgetMeta)
	if template and template:find("BasicFrameTemplate") then
		w.TitleText = newWidget("FontString", nil, w)
		w.CloseButton = newWidget("Button", nil, w)
	end
	if template == "PanelTabButtonTemplate" then
		-- parentArray="Tabs": the client adds each tab to its parent's Tabs array.
		w.Text = newWidget("FontString", nil, w)
		w.Left = newWidget("Texture", nil, w)
		w.Right = newWidget("Texture", nil, w)
		local tabs = rawget(parent, "Tabs") or {}
		tabs[#tabs + 1] = w
		rawset(parent, "Tabs", tabs)
	end
	return w
end

-- Frame methods Forever restricts in combat (HasRestrictions in Blizzard's
-- SimpleFrame and SimpleScriptRegion API docs). The client blocks them from
-- addon code during combat; here they raise, so a spec fails if the addon uses
-- one while `state.inCombat` is true.
for _, method in ipairs({
	"SetPropagateKeyboardInput",
	"SetPassThroughButtons",
	"SetPropagateMouseClicks",
	"SetPropagateMouseMotion",
}) do
	widgetMethods[method] = function()
		if state.inCombat then
			error(method .. " is blocked in combat", 2)
		end
	end
end

function widgetMethods:RegisterEvent(event)
	self.events[event] = true
end
function widgetMethods:UnregisterEvent(event)
	self.events[event] = nil
end
function widgetMethods:IsEventRegistered(event)
	return self.events[event] == true
end
function widgetMethods:SetScript(script, handler)
	self.scripts[script] = handler
end
function widgetMethods:GetScript(script)
	return self.scripts[script]
end
function widgetMethods:Show()
	if not self.shown then
		self.shown = true
		fire(self, "OnShow")
	end
end
function widgetMethods:Hide()
	if self.shown then
		self.shown = false
		fire(self, "OnHide")
		-- Hiding a frame under the mouse sends it OnLeave. (Assumed, not
		-- verified in game: code must be safe either way.)
		if self.hovered then
			self.hovered = false
			fire(self, "OnLeave")
		end
	end
end
function widgetMethods:IsShown()
	return self.shown
end
function widgetMethods:SetShown(shown)
	if shown then
		self:Show()
	else
		self:Hide()
	end
end
function widgetMethods:SetText(text)
	self.text = text
end
function widgetMethods:GetText()
	return self.text
end
function widgetMethods:SetAtlas(atlas)
	self.atlas, self.texture = atlas, nil
end
function widgetMethods:SetTexture(texture)
	self.texture, self.atlas = texture, nil
end
function widgetMethods:SetColorTexture(r, g, b, a)
	self.color = { r, g, b, a }
end
function widgetMethods:SetDesaturated(desaturated)
	self.desaturated = desaturated
end
function widgetMethods:SetEnabled(enabled)
	self.enabled = enabled
end
function widgetMethods:IsEnabled()
	return self.enabled
end
function widgetMethods:SetPoint(...)
	self.points[#self.points + 1] = { ... }
end
function widgetMethods:GetPoint(i)
	local p = self.points[i or 1]
	if p then
		return unpack(p)
	end
end
function widgetMethods:ClearAllPoints()
	self.points = {}
end
function widgetMethods:SetSize(width, height)
	self.width, self.height = width, height
end
function widgetMethods:GetWidth()
	return self.width or 0
end
function widgetMethods:SetWidth(width)
	self.width = width
end
function widgetMethods:SetHeight(height)
	self.height = height
end
function widgetMethods:GetHeight()
	return self.height or 0
end
function widgetMethods:SetID(id)
	self.id = id
end
function widgetMethods:GetID()
	return self.id or 0
end
function widgetMethods:LockHighlight()
	self.highlightLocked = true
end
function widgetMethods:UnlockHighlight()
	self.highlightLocked = false
end
function widgetMethods:SetAlpha(alpha)
	self.alpha = alpha
end
function widgetMethods:GetAlpha()
	return self.alpha or 1
end
-- Animation groups: Play/Stop/IsPlaying; Widgets.finishAnimations completes them.
function widgetMethods.CreateAnimationGroup(owner)
	local group = newWidget("AnimationGroup", nil, owner)
	group.playing, group.plays = false, 0
	function group:Play()
		self.playing, self.plays = true, self.plays + 1
	end
	function group:Stop()
		self.playing = false
	end
	function group:IsPlaying()
		return self.playing
	end
	function group:CreateAnimation(kind)
		return newWidget(kind or "Animation", nil, self)
	end
	animationGroups[#animationGroups + 1] = group
	return group
end
function widgetMethods:CreateTexture(name)
	return newWidget("Texture", name, self)
end
function widgetMethods:CreateFontString(name)
	return newWidget("FontString", name, self)
end
--- Spec helpers: act like the player.
function widgetMethods:Click(button)
	fire(self, "OnClick", button or "LeftButton")
end
function widgetMethods:Enter()
	self.hovered = true
	fire(self, "OnEnter")
end
function widgetMethods:Leave()
	self.hovered = false
	fire(self, "OnLeave")
end
function widgetMethods:Drag()
	fire(self, "OnDragStart")
	self.points = { { "CENTER", _G.UIParent, "CENTER", 100, -50 } }
	fire(self, "OnDragStop")
end
function widgetMethods:Wheel(delta)
	fire(self, "OnMouseWheel", delta)
end

-- The game tooltip records its lines.
function Widgets.tooltip()
	local tip = newWidget("GameTooltip", "GameTooltip")
	tip.shown = false
	tip.lines = {}
	function tip:SetOwner(owner)
		self.owner = owner
		self.lines = {}
	end
	function tip:IsOwned(frame)
		return self.owner == frame
	end
	function tip:AddLine(text)
		self.lines[#self.lines + 1] = text
	end
	function tip:AddDoubleLine(left, right)
		self.lines[#self.lines + 1] = left .. " | " .. right
	end
	return tip
end

Widgets.new = newWidget

--- Start afresh with the fake client's `state` (for combat checks).
function Widgets.reset(newState)
	state = newState
	animationGroups = {}
end

--- Finish every playing animation group, firing OnFinished as the client does.
function Widgets.finishAnimations()
	for _, group in ipairs(animationGroups) do
		if group.playing then
			group.playing = false
			local handler = group.scripts.OnFinished
			if handler then
				handler(group, false)
			end
		end
	end
end

return Widgets
