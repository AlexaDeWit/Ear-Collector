local wow = require("spec.support.wow")

describe("Context", function()
	local Context, settings

	before_each(function()
		wow.reset()
		local ns = wow.loadAddon("EarCollector.toc")
		Context = ns.Context
		settings = ns.db.settings
	end)

	it("counts the open world", function()
		assert.is_true((Context.Classify(false, "none", "contested", settings)))
		assert.is_true((Context.Classify(false, "none", "hostile", settings)))
		assert.is_true((Context.Classify(false, "none", nil, settings)))
	end)

	it("never counts instances", function()
		for _, instanceType in ipairs({ "pvp", "arena", "party", "raid", "scenario" }) do
			local counts, reason = Context.Classify(true, instanceType, nil, settings)
			assert.is_false(counts, instanceType)
			assert.are.equal("instance:" .. instanceType, reason)
		end
	end)

	it("excludes zone-wide battles unless turned on", function()
		assert.is_false((Context.Classify(false, "none", "combat", settings)))
		settings.includeBattlefields = true
		assert.is_true((Context.Classify(false, "none", "combat", settings)))
	end)

	it("includes free-for-all areas unless turned off", function()
		assert.is_true((Context.Classify(false, "none", "arena", settings)))
		settings.includeFreeForAll = false
		assert.is_false((Context.Classify(false, "none", "arena", settings)))
	end)

	it("treats a hidden location as not open world", function()
		wow.state().instanceType = wow.secret()
		local counts, reason = Context.Current(settings)
		assert.is_false(counts)
		assert.are.equal("location hidden", reason)
	end)

	it("reads the player's location, leaving hidden or empty values out", function()
		assert.are.same({ mapID = 1424, zone = "Hillsbrad Foothills", subzone = "Tarren Mill" }, Context.Location())
		wow.state().subzone = ""
		wow.state().mapID = wow.secret()
		assert.are.same({ zone = "Hillsbrad Foothills" }, Context.Location())
	end)
end)
