-- The pouch's Rivals tab: everyone you have taken ears from, most kills first,
-- ten to a page. Hover a row for details; click it to see their latest ear.
-- The list comes from Core/Rivals.lua; this file only draws it.
local _, ns = ...

local Chat, Errors, Pouch, Rivals = ns.Chat, ns.Errors, ns.Pouch, ns.Rivals

local RivalsTab = {}
ns.RivalsTab = RivalsTab

RivalsTab.ROWS = 10

local PAD = Pouch.PAD
local INNER = Pouch.WIDTH - 2 * PAD
local ROW_HEIGHT = 18
local TOP = -50 -- first row, under the column headings
local KILLS_RIGHT, LAST_LEFT, MARK_LEFT = 196, 210, 268 -- column edges from the panel's left
local GREY = { 0.62, 0.62, 0.62 }
local PREY_COLOR = { 0.75, 0.7, 0.55 }

---@class EarCollector.RivalRow : Button
---@field name FontString
---@field kills FontString
---@field last FontString
---@field mark FontString
---@field rival EarCollector.Rival?

local rows = {} ---@type EarCollector.RivalRow[]
local list = {} ---@type EarCollector.Rival[]
local page = 1
local headings, emptyText ---@type Frame, FontString

local function pageCount()
	return math.max(1, math.ceil(#list / RivalsTab.ROWS))
end

local function classHex(token)
	local color = type(token) == "string" and C_ClassColor.GetClassColor(token)
	local hex = color and color:GenerateHexColor()
	if type(hex) == "string" and hex:find("^%x%x%x%x%x%x%x%x$") then
		return hex
	end
	return "ffffffff"
end

--- The tooltip for a rival, as lines like Pouch.TooltipLines. Pure, for specs.
---@param rival EarCollector.Rival
---@return table[]
function RivalsTab.TooltipLines(rival)
	local ear = rival.latest
	local lines = {}
	local function add(text, color)
		color = color or { 1, 1, 1 }
		lines[#lines + 1] = { text = text, r = color[1], g = color[2], b = color[3] }
	end
	local fullName = ear.surname and ("%s %s"):format(rival.name, ear.surname) or rival.name
	add(("|c%s%s|r"):format(classHex(ear.class), fullName))
	local race = ear.raceName or ear.race or ""
	local atlas = Chat.RaceAtlas(ear.race, ear.sex)
	if atlas then
		race = ("|A:%s:14:14|a %s"):format(atlas, race)
	end
	local class = ear.className or ear.class or ""
	add((("Level %s %s %s"):format(ear.level and tostring(ear.level) or "??", race, class):gsub("%s+$", "")))
	add(" ")
	local times = rival.kills == 1 and "once" or ("%d times"):format(rival.kills)
	local ears = rival.ears == 1 and "1 ear" or ("%d ears"):format(rival.ears)
	add(("Killed %s (%s)"):format(times, ears))
	add(("First: %s"):format(date("%b %d, %Y", rival.firstAt)), GREY)
	local last = ("Last: %s"):format(date("%b %d, %Y %H:%M", rival.lastAt))
	if ear.zone then
		last = ("%s, %s"):format(last, ear.subzone or ear.zone)
	end
	add(last, GREY)
	if rival.prey then
		add(("Prey: you've killed them %d or more times"):format(Rivals.PREY), PREY_COLOR)
	end
	add("Click to see their latest ear.", GREY)
	return lines
end

local function showTooltip(row)
	if not row.rival then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	for _, line in ipairs(RivalsTab.TooltipLines(row.rival)) do
		GameTooltip:AddLine(line.text, line.r, line.g, line.b, true)
	end
	GameTooltip:Show()
end

local function hideTooltip(row)
	if GameTooltip:IsOwned(row) then
		GameTooltip:Hide()
	end
end

local function newRow(panel, index)
	local row = CreateFrame("Button", nil, panel) --[[@as EarCollector.RivalRow]]
	row:SetSize(INNER, ROW_HEIGHT)
	row:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, TOP - (index - 1) * ROW_HEIGHT)
	if index % 2 == 0 then
		local stripe = row:CreateTexture(nil, "BACKGROUND")
		stripe:SetAllPoints()
		stripe:SetColorTexture(1, 1, 1, 0.04)
	end
	local glow = row:CreateTexture(nil, "HIGHLIGHT")
	glow:SetAllPoints()
	glow:SetColorTexture(1, 0.82, 0.2, 0.15)

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
	row.name:SetWidth(KILLS_RIGHT - 50)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.kills = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.kills:SetPoint("RIGHT", row, "LEFT", KILLS_RIGHT - PAD, 0)
	row.kills:SetJustifyH("RIGHT")
	row.last = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.last:SetPoint("LEFT", row, "LEFT", LAST_LEFT - PAD, 0)
	row.mark = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.mark:SetPoint("LEFT", row, "LEFT", MARK_LEFT - PAD, 0)
	row.mark:SetTextColor(PREY_COLOR[1], PREY_COLOR[2], PREY_COLOR[3])

	row:SetScript("OnEnter", Errors.Wrap("rivals tooltip", showTooltip))
	row:SetScript("OnLeave", Errors.Wrap("rivals tooltip", hideTooltip))
	row:SetScript(
		"OnClick",
		Errors.Wrap("rivals", function()
			local rival = row.rival
			if rival then
				hideTooltip(row)
				Pouch.FocusEar(rival.latest.guid, rival.latest.at)
			end
		end)
	)
	return row
end

local function build(panel)
	headings = CreateFrame("Frame", nil, panel)
	headings:SetAllPoints()
	for _, column in ipairs({
		{ "Player", "LEFT", PAD + 4 },
		{ "Kills", "RIGHT", KILLS_RIGHT },
		{ "Last", "LEFT", LAST_LEFT },
	}) do
		local label = headings:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("TOP" .. column[2], headings, "TOPLEFT", column[3], -32)
		label:SetText(column[1])
	end
	for i = 1, RivalsTab.ROWS do
		rows[i] = newRow(panel, i)
	end
	emptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	emptyText:SetPoint("CENTER", panel, "CENTER", 0, 0)
	emptyText:SetWidth(INNER - 20)
	emptyText:SetText("No rivals yet. Everyone you take an ear from is listed here.")
end

local function refresh()
	local db = ns.db
	list = Rivals.List(db and db.ears or {})
	page = math.min(math.max(page, 1), pageCount())
	local first = (page - 1) * RivalsTab.ROWS
	for i, row in ipairs(rows) do
		local rival = list[first + i]
		row.rival = rival
		if rival then
			row.name:SetText(("|c%s%s|r"):format(classHex(rival.latest.class), rival.name))
			row.kills:SetText(tostring(rival.kills))
			row.last:SetText(date("%b %d", rival.lastAt) --[[@as string]])
			row.mark:SetText(rival.prey and "Prey" or "")
			row:Show()
		else
			row:Hide()
		end
	end
	headings:SetShown(#list > 0)
	emptyText:SetShown(#list == 0)
end

--- The row widgets, for specs.
---@return EarCollector.RivalRow[]
function RivalsTab.Rows()
	return rows
end

--- The column headings and the empty-list message, for specs.
function RivalsTab.Widgets()
	return { headings = headings, empty = emptyText }
end

Pouch.AddTab({
	title = "Rivals",
	build = build,
	refresh = refresh,
	pages = function()
		return page, pageCount()
	end,
	setPage = function(n)
		page = n
	end,
})
