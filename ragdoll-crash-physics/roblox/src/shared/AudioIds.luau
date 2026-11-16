--!nonstrict
-- Every sound in the game. All IDs were found through the Roblox Creator Store audio
-- search (toolbox-service marketplace, category Audio) on 2026-11-15; none are generated.
-- Comment format: asset name | creator | length.
-- "Roblox" and "ProSoundEffects" entries are Roblox-licensed library audio, free in every experience.
-- Entries from community creators are public Creator Store sound effects; if one is ever
-- moderated or made private, swap the ID here (docs/AUDIO.md lists alternates).
local function id(n: number): string
	return "rbxassetid://" .. n
end

return {
	Engine = { -- looped; pitch follows speed (see AudioController)
		car = { id = id(80317022777602), pitch = { 0.8, 1.9 }, volume = 0.5 },   -- Car-Engine-Loop | Roblox Resources | 9s
		sports = { id = id(80317022777602), pitch = { 1.1, 2.5 }, volume = 0.55 }, -- same loop, pitched up for the high-revving cars
		kart = { id = id(9112787430), pitch = { 0.9, 1.8 }, volume = 0.4 },      -- Go Kart Engine Constant 1 (SFX) | ProSoundEffects | 27s
		truck = { id = id(73621051922669), pitch = { 0.75, 1.5 }, volume = 0.6 }, -- diesel truck idle | JARDACZ45 | 4s
		bus = { id = id(93894279029996), pitch = { 0.8, 1.5 }, volume = 0.6 },   -- Bus engine idle | Chev Studio | 5s
		tank = { id = id(8213083943), pitch = { 0.8, 1.35 }, volume = 0.7 },     -- medium tank engine idle loop | Tankentwerfer | 7s
		plane = { id = id(8907185231), pitch = { 0.7, 1.5 }, volume = 0.6 },     -- propeller plane engine loop (fixed) | Zolure | 8s
		heli = { id = id(18630771616), pitch = { 0.85, 1.15 }, volume = 0.7 },   -- Helicopter Bell UH-1H "Huey" rotor sound, loop | ChuckNorrisBR1 | 10s
		train = { id = id(78626311636765), pitch = { 0.6, 1.6 }, volume = 0.7 }, -- Steam train chugging sound | Alonso_RiGo | 7s
		rocket = { id = id(9119414091), pitch = { 0.9, 1.4 }, volume = 0.7 },    -- Spaceship Interior Rocket Engine Constant 1 (SFX) | ProSoundEffects | 36s
	},
	Layer = { -- extra looped layers
		tracks = { id = id(120045859524269), volume = 0.45 }, -- Tank Tracks Moving Rattling Loop | Ey_SmoKrac | 5s
		wind = { id = id(9114057128), volume = 0.5 },         -- Desert Wind Whistley Light Gusts 2 (SFX) | ProSoundEffects | 92s
		skid = { id = id(9120399077), volume = 0.4 },         -- Vehicle Skids Long Heavy Tire Squeal 3 (SFX) | ProSoundEffects | 6s
		servo = { id = id(9118340555), volume = 0.3 },        -- Robot Servo 16 (SFX) | ProSoundEffects | 2s (tank turret)
	},
	OneShot = {
		brake = { id(9112953039) },      -- 1965 Jaguar E-Type Car Emergency Brake 3 (SFX) | ProSoundEffects | 2s
		horn = { id(9114402619) },       -- Ferrari 308 Car Honking Dual Air Horns 9 (SFX) | ProSoundEffects | 2s
		truckHorn = { id(9114075649) },  -- Diesel Truck Horn Air Horn Exterior 4 (SFX) | ProSoundEffects | 3s
		trainHorn = { id(138837778626202) }, -- Train Horn - Sound Effect (HD) | RenatoAnimates | 5s
		-- vehicle crash, by severity (variations are picked at random)
		crashLight = { id(9120188871), id(9120188628), id(9120189160) }, -- Toolbox Impact Wood Metal Hits Fall Crash 12/9/15 | ProSoundEffects | 1s
		crashMedium = { id(7340406573), id(7340406427), id(7340406603), id(9116673678) }, -- Audio/car crash HARD1-3 | RCarCrash | 1s ; Metal Impact Heavy Clunking Hits Scraping 1 | ProSoundEffects
		crashHeavy = { id(7340406550), id(7340406466), id(7340406517), id(7340406496) }, -- Audio/car crash HARD4-7 | RCarCrash | 1s
		glass = { id(118987440163311), id(139826391278483) }, -- glass_shatter_01 / _09 | Robloxianr6o6c6m1y | 1-2s
		debris = { id(9125672786) },     -- Metal Impact Small Bar Thrown Bouncing Crash | ProSoundEffects | 6s
		-- ragdoll body impacts
		bodyLight = { id(9113480917), id(9113480915) },   -- Body Fall Thud 1/2 (SFX) | ProSoundEffects | <1s
		bodyMedium = { id(3765689841), id(9117972730), id(9117972870) }, -- Cartoon Bonk | Phantomazing | 1s ; Punch Thud 1/2 | ProSoundEffects
		bodyHeavy = { id(9116488438), id(9116488784), id(9116489824) }, -- Meaty Thud 2/6/10 (SFX) | ProSoundEffects | 2s
		bodyFall = { id(9113525391), id(9113475819) },    -- Body Impact 1 / Body Fall Master 28 (SFX) | ProSoundEffects
		bodySlide = { id(9113597082), id(9118768952) },   -- Brush Scrub Rubbing On Wood Floor 1 / Sand Paper Rubbing 6 | ProSoundEffects | 1s
		bodyBounce = { id(2772396665), id(9120067802) },  -- Cartoon Jump Sound [HQ] - BOING | Dizzota ; Tire Drop Bounce 16 | ProSoundEffects
		-- dummy state cues
		stateDown = { id(9125647550) },        -- Magic Zoom In And Stop Swooshing Comic Squeak | ProSoundEffects | 2s
		stateUnconscious = { id(9117060368) }, -- Nasa Transmission Beep 3 (SFX) | ProSoundEffects | 1s (played low and quiet)
		stateDead = { id(9117060347) },        -- Nasa Transmission Beep 1 (SFX) | ProSoundEffects | 1s
		stateRecover = { id(9120733724) },     -- Whoosh Rising Swish Airy Various Pitches 2 (SFX) | ProSoundEffects | 1s
		revive = { id(139481162475902) },      -- Fast healing magic sound | Kaoriox | 2s
		-- UI
		uiClick = { id(15675032796) },         -- Roblox_UI_Small_Click | Roblox
		uiSelect = { id(15675059323) },        -- Roblox_UI_Bright_Click | Roblox
		uiOpen = { id(15675037413) },          -- Roblox_UI_Paper_Swipe | Roblox | 1s
		uiDelete = { id(15675075163) },        -- Roblox_UI_Delete | Roblox | 1s
		spawnVehicle = { id(9118329245) },     -- Robot Servo 6 (SFX) | ProSoundEffects | 2s
		spawnDummy = { id(15675055424) },      -- Roblox_UI_Cute_Pop | Roblox
		resetScene = { id(15674975792) },      -- Roblox_UI_Whoosh_03 | Roblox | 1s
		report = { id(9125540237) },           -- Electronic Tinkles Sharp Relay Falling Beeps | ProSoundEffects
		hitNotify = { id(9119717523) },        -- Switch Click On Or Off Toggle Button 2 (SFX) | ProSoundEffects
	},
	Music = id(15675069601), -- Roblox_UI_Loop_Calm_Music | Roblox | 95s (quiet background loop, Music volume slider)
	-- Which engine / horn each vehicle uses.
	Vehicle = {
		Sedan = { engine = "car", horn = "horn" }, SportsCar = { engine = "sports", horn = "horn" },
		PoliceCar = { engine = "car", horn = "horn" }, MuscleCar = { engine = "sports", horn = "horn" },
		PickupTruck = { engine = "truck", horn = "truckHorn" }, MonsterTruck = { engine = "truck", horn = "truckHorn" },
		CityBus = { engine = "bus", horn = "truckHorn" }, DumpTruck = { engine = "truck", horn = "truckHorn" },
		Tank = { engine = "tank", layer = "tracks" }, ArmoredTruck = { engine = "truck", horn = "truckHorn" },
		SmallPlane = { engine = "plane", layer = "wind" }, CargoPlane = { engine = "plane", layer = "wind" },
		Helicopter = { engine = "heli", layer = "wind" }, Train = { engine = "train", horn = "trainHorn" },
		Bulldozer = { engine = "tank", layer = "tracks" }, GoKart = { engine = "kart", horn = "horn" },
		RocketSled = { engine = "rocket", layer = "wind" },
	},
}
