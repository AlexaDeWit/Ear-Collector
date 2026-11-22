-- Ways to open the pouch besides /ears: the minimap addon drawer (right-click
-- opens options), the key binding, your bags (hooksecurefunc post-hooks), and
-- ear links in chat (EventRegistry "SetItemRef").
local addonName, ns = ...

local Chat, Ears, Errors, Pouch = ns.Chat, ns.Ears, ns.Errors, ns.Pouch

-- Key binding: Bindings.xml shows these strings in Key Bindings > AddOns.
BINDING_HEADER_EARCOLLECTOR = "Ear Collector"
BINDING_NAME_EARCOLLECTOR_TOGGLE = "Toggle Ear Pouch"

EarCollector_TogglePouch = Errors.Wrap("key binding", function()
	Pouch.Toggle()
end)

-- Minimap addon drawer. The client calls these globals as (addonName, mouseButton | button):
-- the click passes the mouse button's name (Blizzard_Minimap/Mainline/AddonCompartment.lua).
EarCollector_OnAddonCompartmentClick = Errors.Wrap("minimap drawer", function(_, mouseButton)
	if mouseButton == "RightButton" then
		ns.Options.Open()
	else
		Pouch.Toggle()
	end
end)

EarCollector_OnAddonCompartmentEnter = Errors.Wrap("minimap drawer tooltip", function(_, button)
	local db = ns.db
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:AddLine("Ear Collector")
	if db then
		GameTooltip:AddLine(Chat.EarCount(#db.ears, Ears.CountAssists(db.ears)), 1, 1, 1)
		local latest = db.ears[#db.ears]
		if latest then
			GameTooltip:AddLine("Latest: " .. Chat.EarName(latest), 1, 1, 1)
		end
		local week = Ears.CountSince(db, GetServerTime() - Ears.WEEK)
		GameTooltip:AddLine(("%d in the last 7 days"):format(week), 0.62, 0.62, 0.62)
	end
	GameTooltip:AddLine("Click to open your Ear Pouch. Right-click for options.", 0.62, 0.62, 0.62)
	GameTooltip:Show()
end)

EarCollector_OnAddonCompartmentLeave = Errors.Wrap("minimap drawer tooltip", function()
	GameTooltip:Hide()
end)

-- Bags: after any of these runs, open or close the pouch to match. CloseBag is
-- what a bag's own close button calls (ContainerFrameMixin:OnCloseClicked).
local BAG_FUNCTIONS = {
	"ToggleAllBags",
	"CloseAllBags",
	"ToggleBackpack",
	"OpenBackpack",
	"CloseBackpack",
	"ToggleBag",
	"OpenBag",
	"CloseBag",
}

---@param openedByPanel boolean? a merchant, bank, mailbox or trade window opened the bags
local function followBags(openedByPanel)
	local db = ns.db
	if not db or not db.settings.openWithBags then
		return
	end
	if IsAnyBagOpen() then
		if not openedByPanel then
			Pouch.ShowWithBags()
		end
	else
		Pouch.HideWithBags()
	end
end

local bagHook = Errors.Wrap("bag hook", function()
	followBags(false)
end)
for _, name in ipairs(BAG_FUNCTIONS) do
	if type(_G[name]) == "function" then
		hooksecurefunc(name, bagHook)
	end
end
-- Merchants, banks, mailboxes and trade windows call OpenAllBags(self); opening
-- the bags yourself calls it with no frame. Only the second opens the pouch.
if type(_G["OpenAllBags"]) == "function" then
	hooksecurefunc(
		"OpenAllBags",
		Errors.Wrap("bag hook", function(frame)
			followBags(frame ~= nil)
		end)
	)
end

-- Ear links in chat: hovering shows the ear's tooltip (ChatFrameMixin fires these
-- through EventRegistry), and clicking opens the pouch on it.
local showingLink = false -- so leaving another addon's or Blizzard's link leaves its tooltip alone

local function findEar(guid, at)
	for _, ear in ipairs(ns.db and ns.db.ears or {}) do
		if ear.guid == guid and ear.at == at then
			return ear
		end
	end
end

EventRegistry:RegisterCallback(
	"ChatFrame.OnHyperlinkEnter",
	Errors.Wrap("ear link", function(_, chatFrame, link)
		local guid, at = Chat.ParseEarLink(link)
		local ear = guid and at and findEar(guid, at)
		if ear then
			Chat.ShowTooltip(chatFrame, "ANCHOR_CURSOR", ns.EarsTab.TooltipLines(ear))
			showingLink = true
		end
	end),
	addonName
)

EventRegistry:RegisterCallback(
	"ChatFrame.OnHyperlinkLeave",
	Errors.Wrap("ear link", function()
		if showingLink then
			showingLink = false
			GameTooltip:Hide()
		end
	end),
	addonName
)

EventRegistry:RegisterCallback(
	"SetItemRef",
	Errors.Wrap("ear link", function(_, link)
		local guid, at = Chat.ParseEarLink(link)
		if guid and at and not ns.EarsTab.Focus(guid, at) then
			Chat.Print("That ear is no longer in your pouch.")
		end
	end),
	addonName
)

-- One line, once per account, on the first login with the addon.
ns.On("PLAYER_LOGIN", function()
	local db = ns.db
	if db and not db.ui.welcomed then
		db.ui.welcomed = true
		Chat.Print(
			db.settings.openWithBags and "Your Ear Pouch opens with your bags. Type /ears for commands."
				or "Type /ears to open your Ear Pouch, and /ears help for commands."
		)
	end
end)
