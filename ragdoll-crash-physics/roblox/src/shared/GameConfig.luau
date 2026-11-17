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
-- Every dummy is fully grey. `body` picks the avatar: "Robloxian2" (default) | "Man" | "Blocky".
-- Robloxian 2.0 / Man bodies and the animatable Man head are Roblox's own catalog assets, loaded at
-- runtime with Players:CreateHumanoidModelFromDescription (see DummyRig).
Config.DummyBody = "Robloxian2"
Config.Bodies = {
	Robloxian2 = { Torso = 27112025, RightArm = 27112039, LeftArm = 27112052, LeftLeg = 27112056, RightLeg = 27112068 },
	Man = { Torso = 86500008, RightArm = 86500036, LeftArm = 86500054, LeftLeg = 86500064, RightLeg = 86500078 },
	Blocky = {},
}
Config.MAN_DYNAMIC_HEAD = 10725826963 -- "Man Face - Head": the dynamic (FaceControls) Man head
local function grey(hex)
	return { head = hex, arms = hex, torso = hex, legs = hex }
end
Config.DummyTypes = {
	Noob = { display = "DUMMY", scale = 1, density = 0.7, armor = 1, health = 100, colors = grey("#a3a2a5") },
	Crash = { display = "CRASH DUMMY", scale = 1, density = 0.7, armor = 1, health = 100, colors = grey("#8d8c90"), markings = true },
	Heavy = { display = "HEAVY DUMMY", scale = 1.18, density = 1.6, armor = 0.7, health = 140, colors = grey("#6f6e72") },
	Light = { display = "LIGHT DUMMY", scale = 0.88, density = 0.35, armor = 1.2, health = 80, colors = grey("#c4c3c7") },
	Armored = { display = "ARMORED DUMMY", scale = 1, density = 1.0, armor = 0.5, health = 110, colors = grey("#7b7a7e"), armorKit = true },
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
	BLOOD_RATE = 0.8,    -- % of blood lost per second while BLEEDING
	BLOOD_FLOOR = 40,    -- bleeding stops by itself here (clotting); below 55% the dummy passes out
	CRITICAL_HEALTH = 25,
	STAGGER_TIME = 1.3,
	HIT_FLASH_TIME = 2.0,
	RECOVER_TIME = 1.6,
	DOWN_TIME = { 2.5, 6 }, -- seconds a conscious, healthy-legged dummy stays down (min, max by damage)
}

-- Crash score -----------------------------------------------------------
Config.Score = { LIGHT = 50, MEDIUM = 150, HEAVY = 400, CRITICAL = 800, CHAIN = 120, PROP = 15, REPEAT_WINDOW = 4 }

-- Replay ----------------------------------------------------------------
Config.Replay = { SECONDS = 10, HZ_HIGH = 20, HZ_LOW = 10, SPEED = 0.25 }

-- Map -------------------------------------------------------------------
Config.Map = {
	SIZE = 700,
	Names = { "Test Grounds", "Downtown", "Desert Range" },
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

-- Progression -----------------------------------------------------------------------------------
-- Vehicles are ranked from least to most cool. The first 14 unlock in that order as the player's
-- lifetime CRASH POINTS grow (points come only from verified crash reports that a vehicle started).
-- The 3 coolest are Robux game passes: create them on the Creator Dashboard (Monetization > Passes)
-- and paste each pass id below; while an id is 0 the vehicle shows "SOON" and stays locked.
Config.Progression = {
	Ladder = { -- { vehicle, lifetime crash points needed }
		{ "Sedan", 0 }, { "GoKart", 1500 }, { "CityBus", 4000 }, { "PickupTruck", 8000 }, { "DumpTruck", 13000 },
		{ "PoliceCar", 19000 }, { "MuscleCar", 26000 }, { "Bulldozer", 34000 }, { "Train", 43000 }, { "SmallPlane", 53000 },
		{ "ArmoredTruck", 64000 }, { "SportsCar", 76000 }, { "Helicopter", 90000 }, { "CargoPlane", 110000 },
	},
	Paid = { -- coolest last
		{ vehicle = "MonsterTruck", passId = 0, price = 99 },
		{ vehicle = "Tank", passId = 0, price = 149 },
		{ vehicle = "RocketSled", passId = 0, price = 199 },
	},
	MAX_POINTS_PER_CRASH = 15000, -- one report can never award more than this
	DATASTORE = "RCP_Progress_v1",
	AUTOSAVE_SECONDS = 120,
	StudioUnlockAll = false, -- true = every vehicle usable while testing in Studio (never in a live server)
}

-- Shop window: the three Robux vehicles (built from Config.Progression.Paid).
Config.Shop = {}
for _, p in Config.Progression.Paid do
	table.insert(Config.Shop, { vehicle = p.vehicle, price = p.price, id = p.passId, kind = "pass" })
end

-- Crash explosions: velocity lost in one physics step (studs/s) that turns a crash into a fireball.
Config.Explosion = { GROUND_DV = 70, AIRCRAFT_DV = 45, RADIUS = 30, COOLDOWN = 2 }

Config.StatusColors = {
	HEALTHY = "#7ee08a", HIT = "#fff3b0", STAGGERING = "#ffd84a", DOWN = "#ff9a3c", LIMPING = "#ffc46b",
	CRAWLING = "#ff8a5c", BLEEDING = "#d9534f", UNCONSCIOUS = "#b49cff", CRITICAL = "#ff3b3b",
	DEAD = "#9a6b6b", RECOVERING = "#5fe3e0",
}

return Config
