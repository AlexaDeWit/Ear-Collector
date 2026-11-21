-- Recorded in play on 2026-11-21: an assist in Western Plaguelands. An ally
-- outside your group finished a level 58 enemy while you (level 52) earned
-- honor for it. Names and GUIDs are changed; the timing between the death and
-- the honorable kill wasn't recorded, so the pause is an estimate.
local VICTIM = "Player-6936-0000AB12"

return {
	setup = {
		playerLevel = 52,
		mapID = 1422,
		zone = "Western Plaguelands",
		subzone = "Dalson's Tears",
		lifetimeHonorableKills = 120,
		players = {
			-- Forever gives the full name as one name, with no separate surname.
			[VICTIM] = { name = "Tobble Sparkwhistle", class = "Mage", race = "Gnome", sex = 2, level = 58 },
		},
	},
	events = {
		{ "PLAYER_ENTERING_WORLD", false, false },
		{ "UNIT_DIED", VICTIM }, -- "assist candidate"
		{ advance = 1 },
		{ set = { lifetimeHonorableKills = 121 } },
		{ "PLAYER_PVP_KILLS_CHANGED", "player" },
		{ advance = 3 }, -- "new ear (assist)"
	},
}
