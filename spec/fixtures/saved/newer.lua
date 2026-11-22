-- SavedVariables from a version newer than this one: a higher schema, and fields,
-- settings and band names this version doesn't know. Hand-written.
return {
	EarCollectorDB = {
		schema = 99,
		settings = { campWindow = 300, toastMinQuality = 2, pouchSort = "grade" },
		ui = { pouch = { point = "CENTER", x = 10, y = 20 }, pouchTab = 2 },
		errors = {},
		debugLog = {},
	},
	EarCollectorCharDB = {
		schema = 99,
		ears = {
			{
				guid = "Player-4395-0C3D1A01",
				name = "Cedric Vale",
				class = "WARRIOR",
				race = "Human",
				level = 60,
				yourLevel = 60,
				by = "you",
				at = 1795294605,
				lastAt = 1795294605,
				camped = 0,
				quality = 3,
				note = "Caught them at the crossroads",
				fight = {
					read = true,
					secs = 5,
					size = 2.1,
					score = 13,
					fightScore = 13,
					why = { "giant", "ambush" },
					points = { giant = 13, ambush = 0 },
					ambush = "from behind",
				},
			},
		},
		deaths = {},
		stats = { hiddenKills = 0, unnamedHonorKills = 0 },
		hiddenGrades = {},
		folders = { { name = "Keepers", ears = { 1 } } },
	},
}
