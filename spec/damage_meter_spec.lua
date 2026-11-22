local wow = require("spec.support.wow")

local ME = "Player-4395-0000000A"
local GRIMBASH = "Player-4395-0B1C2D3E"
local VELARIA = "Player-4395-0C1D2E3F" -- far below you: no honor
local GROUPMATE = "Player-4395-0000BEEF"
local ALLY = "Player-4395-0000A11E" -- a friendly player outside your group

describe("assists from the damage meter", function()
	local ns

	before_each(function()
		wow.reset()
		wow.addPlayer(GRIMBASH, { name = "Grimbash", class = "Warrior", race = "Orc", level = 60 })
		wow.addPlayer(VELARIA, { name = "Velaria", class = "Rogue", race = "Troll", level = 45 })
		wow.addPlayer(GROUPMATE, { name = "Brakka", class = "Warrior", race = "Human", level = 60 })
		wow.state().group[GROUPMATE] = true
		ns = wow.loadAddon("EarCollector.toc")
		wow.fireEvent("PLAYER_ENTERING_WORLD", false, false)
		ns.db.settings.debug = true
	end)

	local decisions = wow.decisions

	-- Leave combat and let the meter be read.
	local function leaveCombat()
		wow.endCombat()
		wow.advance(ns.DamageMeter.SETTLE)
	end

	it("collects an assist for a player you damaged who died with no honor", function()
		wow.startCombat()
		wow.meterFight({ { guid = GRIMBASH, name = "Grimbash" } })
		wow.fireEvent("UNIT_DIED", GRIMBASH)
		wow.advance(ns.Assists.WINDOW + 1)
		assert.are.equal(0, #ns.db.ears) -- the meter is secret until combat ends
		leaveCombat()
		assert.are.equal(1, #ns.db.ears)
		assert.are.equal("assist", ns.db.ears[1].by)
		assert.are.same({ "new ear (assist, damage)" }, decisions("DAMAGE_METER"))
		assert.are.equal(1, wow.printed("You collected .*Grimbash's Ear.*Assist%."))
	end)

	it("gives a grey victim you damaged a Poor assist ear", function()
		wow.startCombat()
		wow.meterFight({ { guid = VELARIA, name = "Velaria" } })
		wow.fireEvent("UNIT_DIED", VELARIA)
		wow.advance(ns.Assists.WINDOW + 1)
		leaveCombat()
		assert.are.equal(1, #ns.db.ears)
		assert.are.equal(0, ns.db.ears[1].quality)
	end)

	it("collects an assist when a player outside your group lands the blow", function()
		wow.startCombat()
		wow.meterFight({ { guid = GRIMBASH, name = "Grimbash" } })
		wow.fireEvent("PARTY_KILL", ALLY, GRIMBASH)
		wow.advance(ns.Assists.WINDOW + 1)
		leaveCombat()
		assert.are.equal(1, #ns.db.ears)
		assert.are.equal("assist", ns.db.ears[1].by)
	end)

	it("judges each death against the fight it happened in", function()
		wow.startCombat()
		wow.meterFight({ { guid = GRIMBASH, name = "Grimbash" } })
		leaveCombat()
		wow.advance(ns.Assists.RECENT + 10)
		wow.startCombat()
		wow.meterFight({ { guid = VELARIA, name = "Velaria" } })
		wow.fireEvent("UNIT_DIED", VELARIA)
		wow.advance(ns.Assists.WINDOW + 1)
		leaveCombat()
		assert.are.equal(1, #ns.db.ears)
		assert.are.equal("Velaria", ns.db.ears[1].name)
	end)

	it("gives no ear for a death you didn't damage", function()
		wow.startCombat()
		wow.meterFight({ { guid = VELARIA, name = "Velaria" } })
		wow.fireEvent("UNIT_DIED", GRIMBASH)
		wow.advance(ns.Assists.WINDOW + 1)
		leaveCombat()
		assert.are.equal(0, #ns.db.ears)
		assert.are.same({ "no assist: not on the damage meter" }, decisions("DAMAGE_METER"))
	end)

	it("counts a death soon after your fight, but not long after", function()
		wow.startCombat()
		wow.meterFight({ { guid = GRIMBASH, name = "Grimbash" }, { guid = VELARIA, name = "Velaria" } })
		wow.advance(10)
		leaveCombat()
		wow.advance(30)
		wow.fireEvent("UNIT_DIED", GRIMBASH) -- a guard finishes them
		wow.advance(ns.Assists.WINDOW + 1)
		assert.are.equal(1, #ns.db.ears)
		wow.advance(ns.Assists.RECENT)
		wow.fireEvent("UNIT_DIED", VELARIA)
		wow.advance(ns.Assists.WINDOW + 1)
		assert.are.equal(1, #ns.db.ears)
		assert.are.same({
			"new ear (assist, damage)",
			"no assist: not during or just after your last fight",
		}, decisions("DAMAGE_METER"))
	end)

	it("adds nothing when honor already named the death", function()
		wow.startCombat()
		wow.meterFight({ { guid = GRIMBASH, name = "Grimbash" } })
		wow.fireEvent("UNIT_DIED", GRIMBASH)
		wow.honorableKill()
		wow.advance(ns.Assists.WINDOW + 1)
		leaveCombat()
		assert.are.equal(1, #ns.db.ears)
		assert.are.same({}, decisions("DAMAGE_METER"))
	end)

	it("adds nothing to your group's own kill", function()
		wow.startCombat()
		wow.meterFight({ { guid = GRIMBASH, name = "Grimbash" } })
		wow.fireEvent("UNIT_DIED", GRIMBASH)
		wow.fireEvent("PARTY_KILL", GROUPMATE, GRIMBASH)
		wow.advance(ns.Assists.WINDOW + 1)
		leaveCombat()
		assert.are.equal(1, #ns.db.ears)
		assert.are.equal("group", ns.db.ears[1].by)
		assert.are.equal(0, ns.db.ears[1].camped)
		assert.are.same({}, decisions("DAMAGE_METER"))
	end)

	it("carries on without the meter when it's unavailable", function()
		wow.state().damageMeter.available = false
		wow.startCombat()
		wow.meterFight({ { guid = GRIMBASH, name = "Grimbash" } })
		wow.fireEvent("UNIT_DIED", GRIMBASH)
		wow.advance(ns.Assists.WINDOW + 1)
		leaveCombat()
		assert.are.equal(0, #ns.db.ears)
		assert.are.same({ "no assist: damage meter unavailable" }, decisions("DAMAGE_METER"))
		assert.are.same({}, ns.db.errors)
	end)

	it("skips hidden players on the meter without touching them", function()
		wow.startCombat()
		wow.meterFight({ { guid = wow.secret(), name = wow.secret() } })
		wow.fireEvent("UNIT_DIED", GRIMBASH)
		wow.advance(ns.Assists.WINDOW + 1)
		leaveCombat()
		assert.are.equal(0, #ns.db.ears)
		assert.are.same({}, ns.db.errors)
	end)

	it("reads nothing while the meter is secret", function()
		wow.state().inCombat = true
		local damaged, reason = ns.DamageMeter.EnemyPlayers()
		assert.is_nil(damaged)
		assert.are.equal("in combat", reason)
	end)

	it("checks a death after your fight as soon as it's matched", function()
		wow.startCombat()
		wow.meterFight({ { guid = GRIMBASH, name = "Grimbash" } })
		leaveCombat()
		wow.fireEvent("UNIT_DIED", GRIMBASH)
		wow.advance(ns.Assists.WINDOW + 0.5)
		assert.are.equal(1, #ns.db.ears)
	end)

	it("waits out a fight that starts before the meter is read", function()
		wow.startCombat()
		wow.meterFight({ { guid = GRIMBASH, name = "Grimbash" } })
		wow.fireEvent("UNIT_DIED", GRIMBASH)
		wow.advance(ns.Assists.WINDOW + 1)
		wow.endCombat()
		wow.startCombat() -- someone else jumps you before the meter is read
		wow.meterFight({ { guid = VELARIA, name = "Velaria" } })
		wow.advance(ns.DamageMeter.SETTLE)
		assert.are.equal(0, #ns.db.ears)
		leaveCombat()
		assert.are.equal(1, #ns.db.ears)
	end)

	it("lists only enemy players who took damage", function()
		wow.meterFight({
			{ guid = GRIMBASH, name = "Grimbash" },
			{ guid = VELARIA, name = "Velaria", amount = 0 },
			{ guid = "Creature-0-4395-0-1-2738-00001234", name = "Defias Bandit" },
		})
		assert.are.same({ [GRIMBASH] = "Grimbash" }, ns.DamageMeter.EnemyPlayers())
	end)

	it("reads the latest fight even when the current session is empty", function()
		wow.meterFight({ { guid = VELARIA, name = "Velaria" } }) -- an older fight
		wow.meterFight({ { guid = GRIMBASH, name = "Grimbash" } })
		_G.C_DamageMeter.GetCombatSessionFromType = function()
			return { combatSources = {} }
		end
		local damaged = ns.DamageMeter.EnemyPlayers()
		assert.are.same({ [GRIMBASH] = "Grimbash" }, damaged)
	end)

	it("keeps detecting kills when reading the meter fails", function()
		_G.C_DamageMeter.GetCombatSessionFromType = function()
			error("meter changed")
		end
		for _ = 1, 3 do
			wow.startCombat()
			wow.fireEvent("UNIT_DIED", GRIMBASH)
			wow.advance(ns.Assists.WINDOW + 1)
			leaveCombat()
		end
		assert.is_true(ns.Errors.IsDisabled("damage meter"))
		wow.fireEvent("PARTY_KILL", ME, GRIMBASH)
		assert.are.equal(1, #ns.db.ears)
	end)

	it("holds a bounded number of deaths for the meter", function()
		local deaths = {}
		for i = 1, ns.DamageMeter.QUEUE_SIZE + 5 do
			local guid = ("Player-1-%08X"):format(i)
			deaths[i] = { guid = guid, t = 0, kill = { guid = guid, name = "V" .. i } }
		end
		wow.startCombat()
		ns.DamageMeter.Queue(deaths)
		wow.endCombat()
		_G.C_DamageMeter.IsDamageMeterAvailable = function()
			return false
		end
		wow.advance(ns.DamageMeter.SETTLE)
		assert.are.equal(ns.DamageMeter.QUEUE_SIZE, #decisions("DAMAGE_METER"))
	end)

	describe("finding who killed you", function()
		it("finds a killer out of sight on the meter, when you hit them", function()
			wow.meterFight({ { guid = VELARIA, name = wow.secret() }, { guid = GRIMBASH, name = "Grimbash" } })
			wow.state().recap = { { sourceName = "Grimbash", spellName = "Mortal Strike" } }
			wow.fireEvent("PLAYER_DEAD")
			wow.advance(ns.DeathWatch.RECAP_DELAY)
			assert.are.equal(1, #ns.db.deaths)
			assert.are.equal(GRIMBASH, ns.db.deaths[1].guid)
			assert.matches("by name, from the damage meter", decisions("PLAYER_DEAD")[1])
		end)

		it("prefers the players in view to the meter", function()
			wow.state().units.target = GRIMBASH
			_G.C_DamageMeter.IsDamageMeterAvailable = function()
				error("the meter shouldn't be read")
			end
			wow.state().recap = { { sourceName = "Grimbash", spellName = "Mortal Strike" } }
			wow.fireEvent("PLAYER_DEAD")
			wow.advance(ns.DeathWatch.RECAP_DELAY)
			assert.are.equal(1, #ns.db.deaths)
			assert.matches("by name %(", decisions("PLAYER_DEAD")[1])
			assert.are.same({}, ns.db.errors)
		end)
	end)
end)
