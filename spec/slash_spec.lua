local wow = require("spec.support.wow")

local ME = "Player-4395-0000000A"
local GRIMBASH = "Player-4395-0B1C2D3E"

describe("/ears", function()
	local ns

	before_each(function()
		wow.reset()
		wow.addPlayer(GRIMBASH, { name = "Grimbash", class = "Warrior", race = "Orc", level = 60 })
		ns = wow.loadAddon("EarCollector.toc")
	end)

	it("switches off only a failing command, and /ears errors always works", function()
		ns.Pouch.Toggle = function()
			error("pouch bug")
		end
		for _ = 1, 3 do
			wow.slash("/ears")
		end
		assert.is_true(ns.Errors.IsDisabled("/ears pouch"))
		local before = #wow.state().printed
		wow.slash("/ears errors")
		wow.slash("/ears stats")
		assert.is_true(#wow.state().printed > before + 1)
	end)

	it("lists a damaged saved error without failing", function()
		ns.db.errors[1] = { at = "yesterday" }
		ns.db.errors[2] = 5
		local before = #wow.state().printed
		assert.has_no.errors(function()
			wow.slash("/ears errors")
		end)
		assert.matches("%? in nil %(nil%): nil", wow.state().printed[before + 2])
		assert.is_nil(ns.Errors.SessionCounts()["/ears"])
	end)

	it("shows at least one ear for /ears recent 0", function()
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		wow.slash("/ears recent 0")
		assert.matches("Grimbash's Ear", wow.state().printed[#wow.state().printed])
	end)

	it("reports hidden and unnamed kills in /ears stats", function()
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		ns.db.stats.hiddenKills, ns.db.stats.unnamedHonorKills = 2, 3
		wow.slash("/ears stats")
		assert.are.equal(1, wow.printed("2 kill%(s%) the game hid"))
		assert.are.equal(1, wow.printed("3 honorable kill%(s%) not tied"))
	end)
end)
