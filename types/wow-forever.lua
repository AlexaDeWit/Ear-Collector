---@meta
-- Type declarations for real WoW Forever globals that Ketho's annotations
-- (pinned in scripts/setup-tools.sh) don't include. This file is read by
-- lua-language-server only; it is not loaded by the game or packaged.
-- Add an entry only after confirming the global exists in the Forever client
-- (search .cache/wow-ui-source), and say where it is defined.

--- Slash command handlers, keyed by command name. Defined in the client's
--- chat frame code; addons add `SlashCmdList.NAME = fn` with `SLASH_NAME1 = "/cmd"`.
---@type table<string, fun(message: string, editBox: table?)>
SlashCmdList = {}

--- Whether `guid` is in the player's group. Blizzard_APIDocumentationGenerated/PartyInfoDocumentation.lua;
--- the global IsGUIDInGroup is only a deprecation shim on Forever.
---@param guid WOWGUID
---@param category number? party category; the active party when nil
---@return boolean isInGroup
function C_PartyInfo.IsGUIDInGroup(guid, category) end

--- True when characters have a first name and a surname instead of realms
--- (WoW Forever). Blizzard_APIDocumentationGenerated/UnitDocumentation.lua.
---@return boolean result
function RegionalUniqueNamesEnabled() end

--- Localized class names keyed by class token ("WARRIOR" -> "Warrior").
--- Blizzard_FrameXMLBase/Constants.lua.
---@type table<string, string>
LOCALIZED_CLASS_NAMES_MALE = {}

--- True when any bag frame is open. Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua.
---@return boolean
function IsAnyBagOpen() end

--- Sound kit IDs by name, for PlaySound. Blizzard_SharedXML/Mainline/SoundKitConstants.lua.
---@type table<string, number>
SOUNDKIT = {}

-- Blizzard's Settings API, the parts the options page uses.
-- Blizzard_Settings_Shared/Blizzard_Settings.lua (Settings.*), Blizzard_Category.lua
-- (GetID), Blizzard_Setting.lua (GetValue/SetValue), Blizzard_SettingControls.lua
-- (CreateSettingsListSectionHeaderInitializer), Blizzard_SharedXML/Shared/Slider/MinimalSlider.lua.

---@class SettingsCategory
local SettingsCategory = {}
---@return integer
function SettingsCategory:GetID() end

---@class SettingsLayout
local SettingsLayout = {}
---@param initializer table
function SettingsLayout:AddInitializer(initializer) end

---@class SettingsSetting
local SettingsSetting = {}
---@return any
function SettingsSetting:GetValue() end
---@param value any
---@param immediate boolean?
function SettingsSetting:SetValue(value, immediate) end

---@class SettingsSliderOptions
local SettingsSliderOptions = {}
---@param labelType integer a MinimalSliderWithSteppersMixin.Label value
---@param formatter fun(value: number): string
function SettingsSliderOptions:SetLabelFormatter(labelType, formatter) end

Settings = {}

---@param name string
---@return SettingsCategory category
---@return SettingsLayout layout
function Settings.RegisterVerticalLayoutCategory(name) end

---@param category SettingsCategory
function Settings.RegisterAddOnCategory(category) end

--- A setting stored in `tbl[key]`, read and written by Blizzard.
---@param category SettingsCategory
---@param variable string unique across all addons
---@param key string the key in `tbl` (Blizzard: variableKey)
---@param tbl table the saved table (Blizzard: variableTbl)
---@param varType "boolean"|"number"|"string"
---@param name string
---@param default any
---@return SettingsSetting
function Settings.RegisterAddOnSetting(category, variable, key, tbl, varType, name, default) end

--- A setting read and written through getValue/setValue (called inside securecall).
---@param category SettingsCategory
---@param variable string unique across all addons
---@param variableType "boolean"|"number"|"string"
---@param name string
---@param defaultValue any
---@param getValue fun(): any
---@param setValue fun(value: any)
---@return SettingsSetting
function Settings.RegisterProxySetting(category, variable, variableType, name, defaultValue, getValue, setValue) end

---@param category SettingsCategory
---@param setting SettingsSetting
---@param tooltip string?
---@return table initializer
function Settings.CreateCheckbox(category, setting, tooltip) end

---@param minValue number
---@param maxValue number
---@param rate number? the step
---@return SettingsSliderOptions
function Settings.CreateSliderOptions(minValue, maxValue, rate) end

---@param category SettingsCategory
---@param setting SettingsSetting
---@param options SettingsSliderOptions
---@param tooltip string?
---@return table initializer
function Settings.CreateSlider(category, setting, options, tooltip) end

--- Opens the Settings screen (C_SettingsUtil.OpenSettingsPanel, which has restrictions).
---@param categoryID integer?
---@param scrollToElementName string?
function Settings.OpenToCategory(categoryID, scrollToElementName) end

---@param name string
---@param tooltip string?
---@param newTagID any?
---@return table initializer
function CreateSettingsListSectionHeaderInitializer(name, tooltip, newTagID) end

MinimalSliderWithSteppersMixin = {
	---@enum MinimalSliderLabel
	Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 },
}

--- Tab helpers for frames whose tabs use PanelTabButtonTemplate (which adds each
--- tab to its parent's `Tabs` array). Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua.
---@param frame Frame
---@param numTabs integer
function PanelTemplates_SetNumTabs(frame, numTabs) end

---@param frame Frame
---@param id integer
function PanelTemplates_SetTab(frame, id) end

--- Names of frames that Escape hides: CloseSpecialWindows, run inside securecall
--- by CloseAllWindows, the AddOnPost Escape handler.
--- Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua.
---@type string[]
UISpecialFrames = {}

--- Mixed into every frame C_NamePlate.GetNamePlates() returns.
--- Blizzard_NamePlates/Blizzard_NamePlateBase.lua: GetUnit returns the unit token it shows.
---@class NamePlateBaseMixin
---@field GetUnit fun(self: NamePlateBaseMixin): string?
