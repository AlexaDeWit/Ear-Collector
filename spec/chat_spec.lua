local wow = require("spec.support.wow")

describe("chat text", function()
	local Chat

	before_each(function()
		wow.reset()
		Chat = wow.loadAddon("EarCollector.toc").Chat
	end)

	it("counts with the right noun", function()
		assert.are.equal("1 kill", Chat.Count(1, "kill"))
		assert.are.equal("0 kills", Chat.Count(0, "kill"))
		assert.are.equal("3 rivals", Chat.Count(3, "rival"))
		assert.are.equal("2 people", Chat.Count(2, "person", "people"))
	end)

	it("counts ears, with assists only when there are some", function()
		assert.are.equal("22 ears (6 assists)", Chat.EarCount(22, 6))
		assert.are.equal("1 ear (1 assist)", Chat.EarCount(1, 1))
		assert.are.equal("1 ear", Chat.EarCount(1, 0))
	end)

	it("writes dates without leading zeros", function()
		local t = os.time({ year = 2026, month = 11, day = 1, hour = 9, min = 5 })
		assert.are.equal("Nov 1", Chat.Date(t))
		assert.are.equal("Nov 1 09:05", Chat.Date(t, "time"))
		assert.are.equal("Nov 1, 2026", Chat.Date(t, "year"))
		assert.are.equal("Nov 1, 2026 09:05", Chat.Date(t, "full"))
	end)

	it("names a class in its colour, falling back without one", function()
		assert.are.equal("|cffc69b6dWarrior|r", Chat.ClassName("WARRIOR"))
		assert.are.equal("|cffc69b6dKrieger|r", Chat.ClassName("WARRIOR", "Krieger"))
		assert.are.equal("Unknown class", Chat.ClassName(nil))
	end)

	it("colours a name by class, and leaves it plain for an unknown class", function()
		assert.are.equal("|cffc69b6dGrimbash|r", Chat.InClassColour("Grimbash", "WARRIOR"))
		assert.are.equal("Grimbash", Chat.InClassColour("Grimbash", "NOT_A_CLASS"))
		assert.are.equal("Grimbash", Chat.InClassColour("Grimbash", nil))
	end)
end)
