--!nonstrict
-- Shared tuning constants for RAGDOLL CRASH PHYSICS. Everything a designer may want to tweak lives here.
local Config = {}

-- Units ---------------------------------------------------------------
-- Game convention: 1 stud = 0.28 m (Roblox's documented character scale), so
-- 1 stud/s = 0.28 m/s = 0.626 mph. Every "MPH" shown in the UI uses this.
Config.STUDS_PER_SEC_TO_MPH = 0.626

-- Session -------------------------------------------------------------
Config.MAX_PLAYERS = 1 -- set the same value in Game Settings > Places
Config.MAX_VEHICLES = 2
Config.DUMMY_LIMITS = { Low = 12, Automatic = 20, High = 25 }
Config.MOBILE_DUMMY_LIMIT = 14

-- Dummies -------------------------------------------------------------
Config.DummyTypes = {
	Noob = { display = "DUMMY", scale = 1, density = 0.7, armor = 1, health = 100,
		colors = { head = "#f5cd30", arms = "#f5cd30", torso = "#0d69ac", legs = "#4b974b" } },
	Crash = { display = "CRASH DUMMY", scale = 1, density = 0.7, armor = 1, health = 100,
		colors = { head = "#a3a2a5", arms = "#a3a2a5", torso = "#1b2a4a", legs = "#8d8c90" }, markings = true },
	Heavy = { display = "HEAVY DUMMY", scale = 1.18, density = 1.6, armor = 0.7, health = 140,
		colors = { head = "#f5cd30", arms = "#f5cd30", torso = "#7a2d2d", legs = "#3a3a3f" } },
	Light = { display = "LIGHT DUMMY", scale = 0.88, density = 0.35, armor = 1.2, health = 80,
		colors = { head = "#f5cd30", arms = "#f5cd30", torso = "#ff9ecb", legs = "#9ad7ff" } },
	Armored = { display = "ARMORED DUMMY", scale = 1, density = 1.0, armor = 0.5, health = 110,
		colors = { head = "#f5cd30", arms = "#5c6166", torso = "#3c4043", legs = "#5c6166" }, armorKit = true },
}

-- Impact detection ----------------------------------------------------
Config.Impact = {
	MIN_SPEED = 8,            -- studs/s relative speed below which a touch is only a push
	CONTACT_BREAK_TIME = 0.35, -- contact must be absent this long before a new impact can register
	MIN_REHIT_TIME = 0.5,     -- hard floor between two damaging hits from the same source
	QUERY_PADDING = 1.5,      -- studs added around the vehicle for the swept overlap query
	MAX_IMPULSE_SPEED = 170,  -- clamp for the velocity a hit can give a dummy part (studs/s)
	ACTIVE_RADIUS = 260,      -- vehicles further than this from every dummy skip queries
}

-- Damage curve (see DamageModel) ---------------------------------------
Config.Damage = {
	SPEED_FLOOR = 8,     -- studs/s where damage starts
	SPEED_FULL = 130,    -- studs/s where the base curve reaches BASE_MAX
	BASE_MAX = 70,
	CURVE = 1.25,
	REGION_MULT = { Head = 1.35, Torso = 1.0, LeftArm = 0.6, RightArm = 0.6, LeftLeg = 0.75, RightLeg = 0.75 },
	RAGDOLLED_MULT = 0.6, -- an already tumbling dummy absorbs less
	SEVERITY = { MEDIUM = 22, HEAVY = 55, CRITICAL = 95 }, -- thresholds on relSpeed * vehicleImpact
	BLEED_RATE = 1,      -- health per second while BLEEDING
	BLEED_FLOOR = 10,    -- bleeding alone never takes a dummy below this
	CRITICAL_HEALTH = 25,
	STAGGER_TIME = 1.3,
	HIT_FLASH_TIME = 1.2,
	RECOVER_TIME = 1.6,
	DOWN_TIME = { 2.5, 6 }, -- seconds a conscious, healthy-legged dummy stays down (min, max by damage)
}

-- Crash score -----------------------------------------------------------
Config.Score = { LIGHT = 50, MEDIUM = 150, HEAVY = 400, CRITICAL = 800, CHAIN = 120, PROP = 15, REPEAT_WINDOW = 4 }

-- Replay ----------------------------------------------------------------
Config.Replay = { SECONDS = 10, HZ_HIGH = 30, HZ_LOW = 15, SPEED = 0.25 }

-- Map -------------------------------------------------------------------
Config.Map = {
	SIZE = 700,
	Spawns = { -- position (ground level) and yaw in degrees; yaw 0 faces -Z
		Road = { 0, 0, 34, 0 },
		TankField = { -220, 0, 185, 0 },
		Runway = { 290, 0, 285, 0 },
		Helipad = { 236, 0, 150, 0 },
		Rail = { -330, 0, 285, 0 },
		SledTrack = { 335, 0, 290, 0 },
	},
	Zones = { -- name, teleport position for the player
		{ "Central Spawn", 0, 48 },
		{ "Dummy Testing Field", -190, -20 },
		{ "High-Speed Crash Track", -150, 240 },
		{ "Giant Ramp Area", 150, -30 },
		{ "Aircraft Airfield", 262, 270 },
		{ "Tank Test Field", -200, 190 },
		{ "Destruction Yard", 120, 60 },
	},
}

Config.StatusColors = {
	HEALTHY = "#7ee08a", HIT = "#fff3b0", STAGGERING = "#ffd84a", DOWN = "#ff9a3c", LIMPING = "#ffc46b",
	CRAWLING = "#ff8a5c", BLEEDING = "#d9534f", UNCONSCIOUS = "#b49cff", CRITICAL = "#ff3b3b",
	DEAD = "#9a6b6b", RECOVERING = "#5fe3e0",
}

return Config
