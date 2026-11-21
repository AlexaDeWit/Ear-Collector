-- One hidden frame dispatches game events to handlers registered with ns.On.
-- Each handler runs inside Errors.Call, so an error in one never escapes to the
-- game and never stops the other handlers for the same event.
local _, ns = ...

local Errors = ns.Errors

---@type Frame
local frame = CreateFrame("Frame")
local handlers = {}

--- Call `fn(...)` with the event's payload whenever `event` fires.
--- Pass event names as string literals so scripts/check_wow_names.lua can check them.
---@param event string
---@param fn fun(...)
function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		frame:RegisterEvent(event)
	end
	local list = handlers[event]
	list[#list + 1] = { name = ("%s handler %d"):format(event, #list + 1), fn = fn }
end

frame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then
		return
	end
	for i = 1, #list do
		Errors.Call(list[i].name, list[i].fn, ...)
	end
end)
