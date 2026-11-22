local wow = require("spec.support.wow")

describe("Ears", function()
	local ns, Ears, db

	before_each(function()
		wow.reset()
		ns = wow.loadAddon("EarCollector.toc")
		Ears = ns.Ears
		db = ns.db
	end)

	local function kill(guid, fields)
		local k = { guid = guid, name = "Grimbash", class = "WARRIOR", race = "Orc", level = 60, yourLevel = 60 }
		for key, value in pairs(fields or {}) do
			k[key] = value
		end
		return k
	end

	describe("Grade", function()
		it("follows the game's level colours", function()
			assert.are.equal(4, Ears.Grade(65, 60, 12)) -- 5 above: red, Epic
			assert.are.equal(3, Ears.Grade(64, 60, 12)) -- 4 above: orange, Rare
			assert.are.equal(3, Ears.Grade(60, 57, 12)) -- 3 above: orange, Rare
			assert.are.equal(2, Ears.Grade(59, 57, 12)) -- 2 above: yellow, Uncommon
			assert.are.equal(2, Ears.Grade(60, 60, 12)) -- even: yellow, Uncommon
			assert.are.equal(2, Ears.Grade(56, 60, 12)) -- 4 below: yellow, Uncommon
			assert.are.equal(1, Ears.Grade(55, 60, 12)) -- 5 below: green, Common
			assert.are.equal(1, Ears.Grade(48, 60, 12)) -- 12 below, at the game's range: green, Common
			assert.are.equal(0, Ears.Grade(47, 60, 12)) -- 13 below: grey, Poor
		end)

		it("takes the green range from the game, which varies with your level", function()
			assert.are.equal(1, Ears.Grade(12, 20, 8)) -- 8 below a level 20: green
			assert.are.equal(0, Ears.Grade(11, 20, 8)) -- 9 below: grey
		end)

		it("uses a fixed green range when the game doesn't give one", function()
			assert.are.equal(1, Ears.Grade(60 - Ears.TRIVIAL_FALLBACK, 60))
			assert.are.equal(0, Ears.Grade(59 - Ears.TRIVIAL_FALLBACK, 60))
		end)

		it("treats unknown levels as an even fight", function()
			assert.are.equal(2, Ears.Grade(nil, 60))
			assert.are.equal(2, Ears.Grade(60, nil))
		end)
	end)

	describe("Record", function()
		it("stores a new ear with the kill's details", function()
			local ear, isNew = Ears.Record(db, kill("Player-1-A", { zone = "Hillsbrad Foothills" }), 1000)
			assert.is_true(isNew)
			assert.are.equal(1, #db.ears)
			assert.are.same({
				guid = "Player-1-A",
				name = "Grimbash",
				class = "WARRIOR",
				race = "Orc",
				level = 60,
				yourLevel = 60,
				zone = "Hillsbrad Foothills",
				at = 1000,
				lastAt = 1000,
				camped = 0,
				quality = 2,
			}, ear)
		end)

		it("counts a repeat kill inside the camping window on the existing ear", function()
			Ears.Record(db, kill("Player-1-A"), 1000)
			local ear, isNew = Ears.Record(db, kill("Player-1-A"), 1000 + 300)
			assert.is_false(isNew)
			assert.are.equal(1, #db.ears)
			assert.are.equal(1, ear.camped)
			assert.are.equal(1300, ear.lastAt)
		end)

		it("restarts the window on each camped kill", function()
			Ears.Record(db, kill("Player-1-A"), 0)
			Ears.Record(db, kill("Player-1-A"), 500)
			local ear, isNew = Ears.Record(db, kill("Player-1-A"), 1000) -- 1000s after the first, 500s after the last
			assert.is_false(isNew)
			assert.are.equal(2, ear.camped)
		end)

		it("drops a new ear once the window has passed", function()
			Ears.Record(db, kill("Player-1-A"), 1000)
			local _, isNew = Ears.Record(db, kill("Player-1-A"), 1000 + db.settings.campWindow + 1)
			assert.is_true(isNew)
			assert.are.equal(2, #db.ears)
		end)

		it("keeps different players apart", function()
			Ears.Record(db, kill("Player-1-A"), 1000)
			local _, isNew = Ears.Record(db, kill("Player-1-B", { name = "Velaria" }), 1010)
			assert.is_true(isNew)
			assert.are.equal(2, #db.ears)
		end)
	end)

	it("lists recent ears newest first and counts by time", function()
		Ears.Record(db, kill("Player-1-A", { name = "A" }), 100)
		Ears.Record(db, kill("Player-1-B", { name = "B" }), 200)
		Ears.Record(db, kill("Player-1-C", { name = "C" }), 300)
		local names = {}
		for _, ear in ipairs(Ears.Recent(db, 2)) do
			names[#names + 1] = ear.name
		end
		assert.are.same({ "C", "B" }, names)
		assert.are.equal(2, Ears.CountSince(db, 200))
		assert.are.equal(3, #Ears.Recent(db, 10))
	end)
end)
