-- The pouch's Ledger tab: totals, ears by grade and by class, and your top zones.
-- The numbers come from Core/Ledger.lua; this file only draws them. Widgets are
-- made once, when the pouch is first built, and refreshed while the tab shows.
local _, ns = ...

local Ledger, Pouch = ns.Ledger, ns.Pouch

local LedgerTab = {}
ns.LedgerTab = LedgerTab

LedgerTab.CLASS_ROWS = 9
LedgerTab.STATS = { "Ears", "Last 7 days", "Assists", "Ears lost" }

local PAD = Pouch.PAD
local INNER = Pouch.WIDTH - 2 * PAD
local ROW = 13
local COLUMN_2 = PAD + 170 -- left edge of the Top zones column
local CLASS_BAR = 62 -- widest class bar
local UNKNOWN_GREY = "ff9d9d9d"

local w = {} -- the tab's widgets

--- Display name and colour for a class entry from Ledger.Summarize.
---@param entry { class: string, name: string? }
---@return string name, string hex "ffRRGGBB"
function LedgerTab.ClassStyle(entry)
	if entry.class == "UNKNOWN" then
		return "Unknown", UNKNOWN_GREY
	end
	local name = entry.name or LOCALIZED_CLASS_NAMES_MALE[entry.class] or entry.class
	return name, ns.Chat.ClassHex(entry.class) or UNKNOWN_GREY
end

local function rgb(hex)
	return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
end

--- The grade legend: "Poor 1  Common 4 ..." in grade colours, grades you have only.
---@param byQuality table<integer, integer>
---@return string
function LedgerTab.GradeLegend(byQuality)
	local parts = {}
	for grade = 0, 5 do
		local quality, count = ns.QUALITY[grade], byQuality[grade] or 0
		if quality and count > 0 then
			parts[#parts + 1] = ("|c%s%s|r %d"):format(quality.color, quality.name, count)
		end
	end
	return table.concat(parts, "   ")
end

local function header(parent, text, x, y)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	label:SetText(text)
	return label
end

local function build(panel)
	local content = CreateFrame("Frame", nil, panel)
	content:SetAllPoints()
	w.content = content

	w.stats = {}
	local boxWidth = (INNER - 3 * 6) / #LedgerTab.STATS
	for i, label in ipairs(LedgerTab.STATS) do
		local box = content:CreateTexture(nil, "BACKGROUND")
		box:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + (i - 1) * (boxWidth + 6), -30)
		box:SetSize(boxWidth, 36)
		box:SetColorTexture(0, 0, 0, 0.45)
		local value = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		value:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -4)
		local text = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		text:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 6, 4)
		text:SetText(label)
		w.stats[i] = value
	end

	header(content, "By grade", PAD, -74)
	local track = content:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -90)
	track:SetSize(INNER, 10)
	track:SetColorTexture(0, 0, 0, 0.45)
	w.grades = {}
	for grade = 0, 5 do
		local quality = ns.QUALITY[grade]
		local segment = content:CreateTexture(nil, "ARTWORK")
		segment:SetColorTexture(quality.r, quality.g, quality.b, 1)
		segment:Hide()
		w.grades[grade] = segment
	end
	w.legend = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	w.legend:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -104)
	w.legend:SetWidth(INNER)
	w.legend:SetJustifyH("LEFT")

	header(content, "By class", PAD, -124)
	w.classes = {}
	for i = 1, LedgerTab.CLASS_ROWS do
		local y = -140 - (i - 1) * ROW
		local row = {}
		row.name = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.name:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
		row.name:SetWidth(64)
		row.name:SetJustifyH("LEFT")
		row.bar = content:CreateTexture(nil, "ARTWORK")
		row.bar:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 66, y - 2)
		row.count = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.count:SetPoint("TOPRIGHT", content, "TOPLEFT", PAD + 156, y)
		row.count:SetJustifyH("RIGHT")
		w.classes[i] = row
	end

	header(content, "Top zones", COLUMN_2, -124)
	w.zones = {}
	for i = 1, Ledger.TOP_ZONES do
		local y = -140 - (i - 1) * ROW
		local row = {}
		row.name = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.name:SetPoint("TOPLEFT", content, "TOPLEFT", COLUMN_2, y)
		row.name:SetWidth(INNER - (COLUMN_2 - PAD) - 28)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.count = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.count:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
		row.count:SetJustifyH("RIGHT")
		w.zones[i] = row
	end

	w.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	w.empty:SetPoint("CENTER", panel, "CENTER", 0, 0)
	w.empty:SetWidth(INNER - 20)
	w.empty:SetText("Your ledger is empty. Collect an ear to start it.")
end

local function refresh()
	local db = ns.db
	local summary = Ledger.Summarize(db and db.ears or {}, GetServerTime(), db and db.deaths)
	local empty = summary.ears == 0 and summary.deaths == 0
	w.content:SetShown(not empty)
	w.empty:SetShown(empty)
	if empty then
		return
	end

	local values = { summary.ears, summary.week, summary.assists, summary.deaths }
	for i, value in ipairs(w.stats) do
		value:SetText(tostring(values[i]))
	end

	-- One bar split by grade, Poor on the left.
	local x = 0
	for grade = 0, 5 do
		local segment, count = w.grades[grade], summary.byQuality[grade] or 0
		if count > 0 then
			local width = INNER * count / summary.ears -- count > 0, so ears > 0
			segment:ClearAllPoints()
			segment:SetPoint("TOPLEFT", w.content, "TOPLEFT", PAD + x, -90)
			segment:SetSize(width, 10)
			segment:Show()
			x = x + width
		else
			segment:Hide()
		end
	end
	w.legend:SetText(LedgerTab.GradeLegend(summary.byQuality))

	local most = summary.byClass[1] and summary.byClass[1].count or 1
	for i, row in ipairs(w.classes) do
		local entry = summary.byClass[i]
		if entry then
			local name, hex = LedgerTab.ClassStyle(entry)
			local r, g, b = rgb(hex)
			row.name:SetText(("|c%s%s|r"):format(hex, name))
			row.bar:SetColorTexture(r, g, b, 0.85)
			row.bar:SetSize(math.max(1, CLASS_BAR * entry.count / most), 8)
			row.bar:Show()
			row.count:SetText(tostring(entry.count))
		else
			row.name:SetText("")
			row.bar:Hide()
			row.count:SetText("")
		end
	end

	for i, row in ipairs(w.zones) do
		local entry = summary.zones[i]
		row.name:SetText(entry and entry.zone or "")
		row.count:SetText(entry and tostring(entry.count) or "")
	end
end

--- The tab's widgets, for specs.
function LedgerTab.Widgets()
	return w
end

Pouch.AddTab({ title = "Ledger", build = build, refresh = refresh })
