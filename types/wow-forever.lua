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
