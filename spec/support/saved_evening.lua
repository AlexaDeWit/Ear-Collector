-- Plays the same evening of world PvP in whichever Ear Collector checkout busted
-- runs from, and writes the SavedVariables that version saved to $SAVED_OUT.
-- It records spec/fixtures/saved (docs/testing.md, "Saved files from past
-- releases"). Not a spec: its name keeps it out of the suite.
local wow = require("spec.support.wow")

-- Lua's reserved words can't be bare keys: a band named "repeat" needs brackets.
local KEYWORDS = {}
for word in
	("and break do else elseif end false for function if in local nil not or repeat return then true until while"):gmatch(
		"%a+"
	)
do
	KEYWORDS[word] = true
end

local function serialize(value, indent)
	indent = indent or ""
	local t = type(value)
	if t == "string" then
		return ("%q"):format(value)
	elseif t == "number" then
		return value == math.floor(value) and ("%d"):format(value) or ("%.4g"):format(value)
	elseif t ~= "table" then
		return tostring(value)
	end
	local inner = indent .. "\t"
	local out, n = {}, #value
	for i = 1, n do
		out[#out + 1] = inner .. serialize(value[i], inner) .. ","
	end
	local keys = {}
	for k in pairs(value) do
		if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then
			keys[#keys + 1] = k
		end
	end
	table.sort(keys, function(a, b)
		if type(a) ~= type(b) then
			return type(a) == "number"
		end
		return a < b
	end)
	for _, k in ipairs(keys) do
		local bare = type(k) == "string" and k:match("^[%a_][%w_]*$") and not KEYWORDS[k]
		local key = bare and k or ("[" .. serialize(k) .. "]")
		out[#out + 1] = ("%s%s = %s,"):format(inner, key, serialize(value[k], inner))
	end
	if #out == 0 then
		return "{}"
	end
	return "{\n" .. table.concat(out, "\n") .. "\n" .. indent .. "}"
end

local ME = "Player-4395-0000000A"
local BRAKKA = "Player-4395-0000BEEF"
local P = {
	cedric = { "Player-4395-0C3D1A01", { name = "Cedric Vale", class = "Warrior", race = "Human", level = 60 } },
	brannoc = { "Player-4395-0C3D1A02", { name = "Brannoc Stonebrow", class = "Paladin", race = "Dwarf", level = 55 } },
	sylvara = {
		"Player-4395-0C3D1A03",
		{ name = "Sylvara Nightbloom", class = "Druid", race = "NightElf", raceName = "Night Elf", level = 52 },
	},
	tilda = { "Player-4395-0C3D1A04", { name = "Tilda Sprocketspark", class = "Mage", race = "Gnome", level = 49 } },
	joss = { "Player-4395-0C3D1A05", { name = "Joss Harlow", class = "Mage", race = "Human", level = 30 } },
	aldric = { "Player-4395-0C3D1A06", { name = "Aldric Thorne", class = "Priest", race = "Human", level = 53 } },
}

describe("an evening of world PvP", function()
	it("is saved", function()
		wow.reset({ playerLevel = 52 })
		wow.addPlayer(BRAKKA, { name = "Brakka", class = "Warrior", race = "Tauren", level = 52 })
		wow.state().group[BRAKKA] = true
		for _, p in pairs(P) do
			wow.addPlayer(p[1], p[2])
		end
		local ns = wow.loadAddon("EarCollector.toc")
		wow.fireEvent("PLAYER_ENTERING_WORLD", false, false)
		local function later(minutes)
			wow.state().now = wow.state().now + minutes * 60
		end
		local function kill(who, by)
			if wow.meterFight then -- each kill in a fight of its own, which the meter has no record of
				wow.startCombat()
				wow.advance(10)
				wow.fireEvent("PARTY_KILL", by or ME, P[who][1])
				wow.meterFight({}, {})
				wow.endCombat()
				wow.advance(ns.DamageMeter.SETTLE)
			else
				wow.fireEvent("PARTY_KILL", by or ME, P[who][1])
			end
		end

		if wow.meterFight then -- grades from the fight: one hard one read from the meter
			wow.startCombat()
			wow.advance(45)
			wow.fireEvent("PARTY_KILL", ME, P.sylvara[1])
			wow.meterFight({
				{ guid = P.sylvara[1], name = "Sylvara Nightbloom", amount = 5000 },
				{ guid = P.joss[1], name = "Joss Harlow", amount = 800 },
			}, {
				DamageTaken = { { amount = 1600, me = true } },
				DamageDone = { { amount = 5000, me = true } },
			})
			wow.endCombat()
			wow.advance(ns.DamageMeter.SETTLE)
		else
			kill("sylvara")
		end
		later(15)
		kill("cedric") -- red
		later(15)
		kill("brannoc") -- orange
		later(15)
		kill("tilda") -- green
		later(2)
		kill("tilda") -- camped
		later(15)
		kill("joss") -- grey
		later(15)
		kill("brannoc", BRAKKA) -- your group's kill
		for _ = 1, 3 do
			later(5)
			ns.RecordDeath(
				ns.db,
				{ guid = P.aldric[1], name = "Aldric Thorne", class = "PRIEST", race = "Human", level = 53 }
			)
		end
		later(5)
		kill("aldric") -- Vengeance

		ns.db.settings.toastMinQuality = 2
		ns.db.settings.campWindow = 300
		if ns.db.hiddenGrades then
			ns.db.hiddenGrades[0] = true
		end
		local out = assert(io.open(os.getenv("SAVED_OUT"), "w"))
		out:write(
			"return ",
			serialize({ EarCollectorDB = _G.EarCollectorDB, EarCollectorCharDB = _G.EarCollectorCharDB }),
			"\n"
		)
		out:close()
	end)
end)
