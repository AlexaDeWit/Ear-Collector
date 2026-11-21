-- A hand-written event sequence in the shape a recorded fixture takes.
-- Replace or add to it with real sequences captured with /ears debug
-- (EarCollectorDB.debugLog), anonymising player names.
local ME = "Player-4395-0000000A"
local GRIMBASH = "Player-4395-0B1C2D3E"
local VELARIA = "Player-1-00FF00FF"
local PARTY_MEMBER = "Player-4395-0000BEEF"

return {
	setup = {
		group = { [PARTY_MEMBER] = true },
		players = {
			[PARTY_MEMBER] = { name = "Brakka", class = "Warrior", race = "Tauren", level = 60 },
			[GRIMBASH] = { name = "Grimbash", class = "Warrior", race = "Orc", level = 60 },
			[VELARIA] = { name = "Velaria", realm = "Stonemaul", class = "Rogue", race = "Scourge", level = 59 },
		},
	},
	events = {
		{ "PARTY_KILL", ME, GRIMBASH }, -- your killing blow: new ear
		{ set = { now = 1795293660 + 90 } },
		{ "PARTY_KILL", PARTY_MEMBER, VELARIA }, -- a party member's killing blow: new ear
		{ "PARTY_KILL", "Player-4395-0000F00D", GRIMBASH }, -- a stranger's kill: no ear
		{ "PARTY_KILL", ME, "Creature-0-4395-0-1-2738-00001234" }, -- an NPC: no ear
		{ set = { now = 1795293660 + 240 } },
		{ "PARTY_KILL", ME, GRIMBASH }, -- he ran back: camped
		{ set = { now = 1795293660 + 1800, subzone = "Southshore" } },
		{ "PARTY_KILL", ME, VELARIA }, -- 27 minutes after the last Velaria kill: new ear
		{ set = { inInstance = true, instanceType = "pvp" } },
		{ "PARTY_KILL", ME, GRIMBASH }, -- in a battleground: no ear
		{ set = { inInstance = false, instanceType = "none" } },
		{ "PARTY_KILL", ME, "<secret>" }, -- identity hidden by the client: counted as hidden
	},
}
