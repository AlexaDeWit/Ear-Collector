-- Options > AddOns > Ear Collector, built with Blizzard's Settings API so nothing
-- is tainted. Checkboxes bind straight to db.settings; the repeat-kill slider is
-- a proxy setting whose getter and setter Blizzard calls inside securecall, so
-- they run in Errors.Call. Nothing caches settings, so changes apply at once.
local addonName, ns = ...

local Chat, Database, Errors = ns.Chat, ns.Database, ns.Errors

local Options = {}
ns.Options = Options

Options.TITLE = "Ear Collector"
Options.CAMP_MIN, Options.CAMP_MAX = 0, 60 -- minutes

-- Checkboxes by section, in display order. Each `key` is a boolean in
-- Database.DEFAULT_SETTINGS.
Options.SECTIONS = {
	{
		title = "When you collect an ear",
		checkboxes = {
			{
				key = "announce",
				label = "Chat line for each ear and death",
				tooltip = "Print a line in your chat window when you collect an ear or an enemy player kills you. "
					.. "Only you see it. Click an ear's name in it to open the pouch on that ear.",
			},
			{
				key = "toast",
				label = "Show a pop-up",
				tooltip = "Show a pop-up with the ear when you collect one. Click it to open the pouch on that ear.",
			},
			{
				key = "toastSound",
				label = "Play a loot sound",
				tooltip = "Play a loot sound with the pop-up. Rare and better ears play the epic loot sound.",
			},
		},
	},
	{
		title = "Ear Pouch",
		checkboxes = {
			{
				key = "openWithBags",
				label = "Open with your bags",
				tooltip = "Open the pouch when you open your bags, and close it with them if they opened it.",
			},
		},
	},
	{
		title = "What counts",
		checkboxes = {
			{
				key = "includeFreeForAll",
				label = "Free-for-all areas",
				tooltip = "Count kills in free-for-all areas such as Gurubashi Arena.",
			},
			{
				key = "includeBattlefields",
				label = "Zone-wide battles",
				tooltip = "Count kills in zones where a zone-wide battle is on. Battlegrounds, arenas and dungeons never count.",
			},
		},
		camp = true, -- the camping-window slider goes at the end of this section
	},
}

Options.CAMP_LABEL = "Repeat kill window"
Options.CAMP_TOOLTIP = "Killing the same player again within this many minutes adds to that ear's count "
	.. "instead of dropping a new ear. Each repeat restarts the window. At 0, every kill drops a new ear."

local category ---@type SettingsCategory?

local function clamp(value, low, high)
	return math.min(math.max(value, low), high)
end

local function defaultCampMinutes()
	return math.floor(Database.DEFAULT_SETTINGS.campWindow / 60)
end

--- The saved camping window in whole minutes, within the slider's range.
---@return number
function Options.GetCampMinutes()
	local seconds = ns.db and ns.db.settings.campWindow
	if type(seconds) ~= "number" or seconds ~= seconds then -- missing or NaN
		return defaultCampMinutes()
	end
	return clamp(math.floor(seconds / 60 + 0.5), Options.CAMP_MIN, Options.CAMP_MAX)
end

--- Save a camping window given in minutes. Ignores anything that isn't a number.
---@param minutes any
function Options.SetCampMinutes(minutes)
	if not ns.db or type(minutes) ~= "number" or minutes ~= minutes then
		return
	end
	ns.db.settings.campWindow = clamp(math.floor(minutes + 0.5), Options.CAMP_MIN, Options.CAMP_MAX) * 60
end

-- Blizzard calls these inside securecall; Errors.Call keeps an error ours, and
-- the getter always returns a number the slider can show.
local function campGetter()
	local ok, minutes = Errors.Call("options", Options.GetCampMinutes)
	if ok and type(minutes) == "number" then
		return minutes
	end
	return defaultCampMinutes()
end

local function campSetter(minutes)
	Errors.Call("options", Options.SetCampMinutes, minutes)
end

local function minutesLabel(value)
	if type(value) ~= "number" then
		return ""
	end
	return ("%d min"):format(value)
end

--- Add the Ear Collector category to Blizzard's Settings screen.
---@param db table the migrated saved variables
local function register(db)
	if category or type(Settings) ~= "table" or not Settings.RegisterVerticalLayoutCategory then
		return
	end
	local new, layout = Settings.RegisterVerticalLayoutCategory(Options.TITLE)
	for _, section in ipairs(Options.SECTIONS) do
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(section.title))
		for _, box in ipairs(section.checkboxes) do
			local default = Database.DEFAULT_SETTINGS[box.key]
			local setting = Settings.RegisterAddOnSetting(
				new,
				addonName .. "_" .. box.key,
				box.key,
				db.settings,
				"boolean",
				box.label,
				default
			)
			Settings.CreateCheckbox(new, setting, box.tooltip)
		end
		if section.camp then
			local setting = Settings.RegisterProxySetting(
				new,
				addonName .. "_campWindow",
				"number",
				Options.CAMP_LABEL,
				defaultCampMinutes(),
				campGetter,
				campSetter
			)
			local slider = Settings.CreateSliderOptions(Options.CAMP_MIN, Options.CAMP_MAX, 1)
			slider:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, minutesLabel)
			Settings.CreateSlider(new, setting, slider, Options.CAMP_TOOLTIP)
		end
	end
	Settings.RegisterAddOnCategory(new)
	category = new
end

--- Open the Settings screen on Ear Collector's options.
--- Blizzard restricts opening it from addon code in combat, so that waits.
---@return boolean opened
function Options.Open()
	if not category then
		Chat.Print("The options page isn't available. /ears help lists the commands.")
		return false
	end
	if ns.Context.InCombat() then
		Chat.Print("Options can't open during combat. Try again when it ends.")
		return false
	end
	Settings.OpenToCategory(category:GetID())
	return true
end

--- Whether the category was registered (for specs and /ears help).
---@return boolean
function Options.IsRegistered()
	return category ~= nil
end

ns.On("ADDON_LOADED", function(loadedName)
	if loadedName == addonName and ns.db then
		register(ns.db)
	end
end)
