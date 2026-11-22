local wow = require("spec.support.wow")

describe("grade buttons on the Ears tab", function()
	local ns, EarsTab, GradeFilter

	before_each(function()
		wow.reset()
		ns = wow.loadAddon("EarCollector.toc")
		EarsTab, GradeFilter = ns.EarsTab, ns.GradeFilter
	end)

	-- Collect one ear per entry in `grades`, oldest first, with that grade.
	local function collect(grades)
		for i, grade in ipairs(grades) do
			local kill =
				{ guid = ("Player-1-%08X"):format(i), name = "Victim" .. i, race = "Orc", level = 60, by = "you" }
			ns.Ears.Record(ns.db, kill, 1795290000 + i * 60)
			ns.db.ears[#ns.db.ears].quality = grade
		end
		wow.slash("/ears")
	end

	local function button(grade)
		return GradeFilter.Buttons()[grade + 1]
	end

	local function shown()
		local ears = {}
		for _, slot in ipairs(EarsTab.Widgets().slots) do
			ears[#ears + 1] = slot.ear
		end
		return ears
	end

	it("has a button for each grade, Poor to Legendary, all showing at first", function()
		collect({ 2 })
		assert.are.equal(6, #GradeFilter.Buttons())
		for grade = 0, 5 do
			assert.are.equal(grade, button(grade).grade)
			assert.is_false(button(grade).slash:IsShown())
		end
	end)

	it("hides a grade's ears with one click, says how many are hidden, and shows them again", function()
		collect({ 0, 2, 0 })
		button(0):Click()
		assert.are.same({ ns.db.ears[2] }, shown())
		assert.are.equal("1 ear, 2 hidden", EarsTab.Widgets().count:GetText())
		assert.is_true(button(0).slash:IsShown())
		assert.are.equal(0.35, button(0).edge:GetAlpha())

		button(0):Click()
		assert.are.equal(3, #shown())
		assert.are.equal("3 ears", EarsTab.Widgets().count:GetText())
		assert.is_false(button(0).slash:IsShown())
	end)

	it("keeps the choice for this character, across sessions", function()
		collect({ 0 })
		button(0):Click()
		assert.is_true(_G.EarCollectorCharDB.hiddenGrades[0])
		assert.is_nil(_G.EarCollectorDB.hiddenGrades)
		local saved = { EarCollectorDB = _G.EarCollectorDB, EarCollectorCharDB = _G.EarCollectorCharDB }
		wow.reset()
		ns = wow.loadAddon("EarCollector.toc", saved)
		assert.is_true(ns.db.hiddenGrades[0])
	end)

	it("says in its tooltip how many ears the grade has, and what a click does", function()
		collect({ 0, 0, 3 })
		button(0):Enter()
		assert.are.same({ "Poor", "2 ears, shown", "Click to hide them." }, _G.GameTooltip.lines)
		button(0):Click()
		assert.are.same({ "Poor", "2 ears, hidden", "Click to show them." }, _G.GameTooltip.lines)
	end)

	it("plays the checkbox sounds", function()
		_G.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON = 856
		_G.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF = 857
		collect({ 0 })
		wow.state().sounds = {}
		button(0):Click()
		button(0):Click()
		assert.are.same({ 857, 856 }, { wow.state().sounds[1].id, wow.state().sounds[2].id })
	end)

	it("pages by the ears it shows", function()
		local grades = { 3, 3, 3, 3 }
		for _ = 1, 41 do
			grades[#grades + 1] = 0
		end
		collect(grades)
		assert.are.same({ 1, 2 }, { ns.Pouch.GetPage() })
		button(0):Click()
		assert.are.same({ 1, 1 }, { ns.Pouch.GetPage() })
	end)

	it("says so when every ear is hidden", function()
		collect({ 0, 0 })
		button(0):Click()
		assert.is_true(EarsTab.Widgets().empty:IsShown())
		assert.are.equal("Every ear is hidden", EarsTab.Widgets().emptyHeading:GetText())
	end)

	it("shows a hidden ear's grade again when you open the ear from chat", function()
		collect({ 0, 2 })
		button(0):Click()
		local grey = ns.db.ears[1]
		assert.is_true(EarsTab.Focus(grey.guid, grey.at))
		assert.is_nil(ns.db.hiddenGrades[0])
		assert.are.equal(2, #shown())
	end)
end)
