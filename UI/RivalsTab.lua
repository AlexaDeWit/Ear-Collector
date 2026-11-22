-- The pouch's Rivals tab: everyone you have taken ears from or died to, most
-- encounters first, ten to a page. Hover a row for details; click it to see
-- their latest ear.
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
-- Column edges, from the panel's left.
local KILLS_RIGHT, DEATHS_RIGHT, LAST_LEFT, MARK_LEFT = 150, 192, 204, 256
local GREY = { 0.62, 0.62, 0.62 }
local MARK_COLORS = {
	Avenge = { ns.QUALITY[5].r, ns.QUALITY[5].g, ns.QUALITY[5].b },
	Nemesis = { 0.85, 0.25, 0.2 },
	Prey = { 0.75, 0.7, 0.55 },
}

---@class EarCollector.RivalRow : Button
---@field name FontString
---@field kills FontString
---@field deaths FontString
---@field last FontString
---@field mark FontString
---@field rival EarCollector.Rival?

local rows = {} ---@type EarCollector.RivalRow[]
local list = {} ---@type EarCollector.Rival[]
local page = 1
local headings, emptyText, countText ---@type Frame, FontString, FontString

local function pageCount()
	return math.max(1, math.ceil(#list / RivalsTab.ROWS))
end

local function classHex(token)
	return Chat.ClassHex(token) or "ffffffff"
end

--- The tooltip for a rival, as lines like EarsTab.TooltipLines. Pure, for specs.
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
	race = Chat.RaceIcon(ear.race, ear.sex) .. race
	local class = ear.className or ear.class or ""
	add((("Level %s %s %s"):format(ear.level and tostring(ear.level) or "??", race, class):gsub("%s+$", "")))
	add(" ")
	local function times(n)
		return n == 1 and "once" or ("%d times"):format(n)
	end
	if rival.kills > 0 then
		local ears = rival.ears == 1 and "1 ear" or ("%d ears"):format(rival.ears)
		add(("You killed them %s (%s)"):format(times(rival.kills), ears))
	end
	if rival.killedYou > 0 then
		add(("They killed you %s"):format(times(rival.killedYou)))
	end
	add(("First met: %s"):format(date("%b %d, %Y", rival.firstAt)), GREY)
	if rival.lastAt then
		local last = ("Last killed: %s"):format(date("%b %d, %Y %H:%M", rival.lastAt))
		if rival.ears > 0 and ear.zone then
			last = ("%s, %s"):format(last, ear.subzone or ear.zone)
		end
		add(last, GREY)
	end
	if rival.lastDeathAt then
		add(("Last killed you: %s"):format(date("%b %d, %Y %H:%M", rival.lastDeathAt)), GREY)
	end
	local mark = Rivals.Mark(rival)
	if mark == "Avenge" then
		add(
			("Vengeance owed: they've killed you %d times since you last killed them. Their next ear is Legendary."):format(
				rival.debt
			),
			MARK_COLORS.Avenge
		)
	elseif mark == "Nemesis" then
		add("Nemesis: they've killed you more often than you've killed them", MARK_COLORS.Nemesis)
	elseif mark == "Prey" then
		add(
			("Prey: you've killed them %d or more times, and they've never killed you"):format(Rivals.PREY),
			MARK_COLORS.Prey
		)
	end
	if rival.ears > 0 then
		add("Click to see their latest ear.", GREY)
	end
	return lines
end

local function showTooltip(row)
	if not row.rival then
		return
	end
	Chat.ShowTooltip(row, "ANCHOR_RIGHT", RivalsTab.TooltipLines(row.rival))
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
	row.deaths = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.deaths:SetPoint("RIGHT", row, "LEFT", DEATHS_RIGHT - PAD, 0)
	row.deaths:SetJustifyH("RIGHT")
	row.last = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.last:SetPoint("LEFT", row, "LEFT", LAST_LEFT - PAD, 0)
	row.mark = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.mark:SetPoint("LEFT", row, "LEFT", MARK_LEFT - PAD, 0)

	row:SetScript("OnEnter", Errors.Wrap("rivals tooltip", showTooltip))
	row:SetScript("OnLeave", Errors.Wrap("rivals tooltip", hideTooltip))
	row:SetScript(
		"OnClick",
		Errors.Wrap("rivals", function()
			local rival = row.rival
			if rival and rival.ears > 0 then
				hideTooltip(row)
				ns.EarsTab.Focus(rival.latest.guid, rival.latest.at)
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
		{ "Deaths", "RIGHT", DEATHS_RIGHT },
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
	emptyText:SetText("No rivals yet. Everyone you take an ear from, or who kills you, is listed here.")
	countText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -32)
	countText:SetJustifyH("RIGHT")
end

local function refresh()
	local db = ns.db
	list = Rivals.List(db and db.ears or {}, db and db.deaths or {})
	page = math.min(math.max(page, 1), pageCount())
	local first = (page - 1) * RivalsTab.ROWS
	for i, row in ipairs(rows) do
		local rival = list[first + i]
		row.rival = rival
		if rival then
			row.name:SetText(("|c%s%s|r"):format(classHex(rival.latest.class), rival.name))
			row.kills:SetText(tostring(rival.kills))
			row.deaths:SetText(tostring(rival.killedYou))
			row.last:SetText(date("%b %d", rival.lastSeen) --[[@as string]])
			local mark = Rivals.Mark(rival)
			local color = MARK_COLORS[mark] or GREY
			row.mark:SetText(mark or "")
			row.mark:SetTextColor(color[1], color[2], color[3])
			row:Show()
		else
			row:Hide()
		end
	end
	headings:SetShown(#list > 0)
	emptyText:SetShown(#list == 0)
	countText:SetText(#list == 1 and "1 rival" or ("%d rivals"):format(#list))
	countText:SetShown(#list > 0)
end

--- The row widgets, for specs.
---@return EarCollector.RivalRow[]
function RivalsTab.Rows()
	return rows
end

--- The column headings and the empty-list message, for specs.
function RivalsTab.Widgets()
	return { headings = headings, empty = emptyText, count = countText }
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
