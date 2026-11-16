--!nonstrict
-- Builds the whole sandbox procedurally at server start: one continuous 700 x 700 stud test ground
-- (bright grass baseplate, flat tiled plaza, scaffolding, containers, ramps - the look shared by
-- the current top ragdoll sandboxes) with six connected crash-test zones.
-- Anchored geometry goes in workspace.Map.Static, knock-about props in workspace.Map.Props.
local Lighting = game:GetService("Lighting")
local Config = require(game.ReplicatedStorage.Shared.GameConfig)

local MapService = {}
local static: Folder, props: Folder

local C = {
	grass = "#73c25e", grassDark = "#5faa4d", concrete = "#b9bcc2", concreteDark = "#8f939b", asphalt = "#4a4d55",
	line = "#e9eaee", yellow = "#ffd21a", red = "#e2342b", blue = "#2f7fe0", dirt = "#a8835a", brick = "#b5533c",
	foam = "#ffb3d1", foamBlue = "#9ad7ff", white = "#f4f5f7", dark = "#30333a", steel = "#737a86", wood = "#b98a55",
}

local function block(name: string, size: Vector3, pos: Vector3, color: string, material: Enum.Material?, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = CFrame.new(pos)
	p.Color = Color3.fromHex(color)
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent or static
	return p
end

-- flat ground decal: top surface sits `lift` above y = 0
local function pad(name: string, sx: number, sz: number, x: number, z: number, color: string, lift: number?, material: Enum.Material?): Part
	local top = lift or 0.1
	return block(name, Vector3.new(sx, 0.4, sz), Vector3.new(x, top - 0.2, z), color, material)
end

local function mark(sx: number, sz: number, x: number, z: number, color: string, lift: number?)
	local p = pad("Marking", sx, sz, x, z, color, lift or 0.14)
	p.CanCollide, p.CanQuery, p.CastShadow = false, false, false
	return p
end

local function loose(name: string, size: Vector3, pos: Vector3, color: string, density: number, material: Enum.Material?): Part
	local p = block(name, size, pos, color, material, props)
	p.Anchored = false
	p.CustomPhysicalProperties = PhysicalProperties.new(density, 0.6, 0.1, 1, 1)
	p.CollisionGroup = "Prop"
	return p
end

-- ramp that rises towards -Z (the direction vehicles drive from the spawn)
local function ramp(name: string, width: number, height: number, length: number, x: number, zLowEdge: number, color: string): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Size = Vector3.new(width, height, length)
	w.CFrame = CFrame.new(x, height / 2, zLowEdge - length / 2) * CFrame.Angles(0, math.rad(180), 0)
	w.Color = Color3.fromHex(color)
	w.Material = Enum.Material.SmoothPlastic
	w.Anchored = true
	w.Parent = static
	return w
end

local function sign(text: string, pos: Vector3, size: Vector3, yaw: number?, bg: string?, fg: string?): Part
	local p = block("Sign", size, pos, bg or C.yellow)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw or 0), 0)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local g = Instance.new("SurfaceGui")
		g.Face = face
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 20
		g.Parent = p
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Text = text
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.TextColor3 = Color3.fromHex(fg or "#15171c")
		t.Parent = g
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft, padding.PaddingRight = UDim.new(0.04, 0), UDim.new(0.04, 0)
		padding.PaddingTop, padding.PaddingBottom = UDim.new(0.08, 0), UDim.new(0.08, 0)
		padding.Parent = t
	end
	return p
end

local function signOnPosts(text: string, x: number, z: number, width: number, height: number, yaw: number?)
	local rad = math.rad(yaw or 0)
	local right = Vector3.new(math.cos(rad), 0, -math.sin(rad))
	for _, s in { -1, 1 } do
		block("Post", Vector3.new(1, height, 1), Vector3.new(x, height / 2, z) + right * s * (width / 2 - 1), C.dark, Enum.Material.Metal)
	end
	sign(text, Vector3.new(x, height + 2.5, z), Vector3.new(width, 5, 0.6), yaw)
end

local function brickWall(x: number, z: number, cols: number, rows: number, alongX: boolean)
	local bs = Vector3.new(4, 2, 2)
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local off = (c - (cols - 1) / 2) * 4 + (if r % 2 == 1 then 2 else 0)
			local pos = if alongX then Vector3.new(x + off, 1.2 + r * 2, z) else Vector3.new(x, 1.2 + r * 2, z + off)
			local b = loose("Brick", if alongX then bs else Vector3.new(2, 2, 4), pos, if (r + c) % 2 == 0 then C.brick else "#a34a35", 0.9, Enum.Material.Brick)
			b:SetAttribute("Breakable", true)
		end
	end
end

local function foamCubes(x: number, z: number, cols: number, rows: number, size: number, alongX: boolean)
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local off = (c - (cols - 1) / 2) * size
			local pos = if alongX then Vector3.new(x + off, size / 2 + 0.2 + r * size, z) else Vector3.new(x, size / 2 + 0.2 + r * size, z + off)
			loose("FoamCube", Vector3.one * size, pos, if (r + c) % 2 == 0 then C.foam else C.foamBlue, 0.06)
		end
	end
end

-- open scaffold tower, the landmark every reference sandbox has
local function scaffold(x: number, z: number, levels: number)
	for l = 0, levels - 1 do
		local y = l * 12
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				block("ScaffoldLeg", Vector3.new(1, 12, 1), Vector3.new(x + sx * 7, y + 6, z + sz * 7), C.yellow, Enum.Material.Metal)
			end
			local brace = block("ScaffoldBrace", Vector3.new(0.6, 18, 0.6), Vector3.new(x + sx * 7, y + 6, z), C.dark, Enum.Material.Metal)
			brace.CFrame = CFrame.new(x + sx * 7, y + 6, z) * CFrame.Angles(math.rad(50 * sx), 0, 0)
			brace.CanCollide = false
		end
		block("ScaffoldDeck", Vector3.new(15, 0.6, 15), Vector3.new(x, y + 12, z), C.wood, Enum.Material.WoodPlanks)
	end
end

local function lighting()
	Lighting.ClockTime = 13.5
	Lighting.GeographicLatitude = 35
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(110, 115, 125)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 155, 165)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 250, 235)
	Lighting.EnvironmentDiffuseScale, Lighting.EnvironmentSpecularScale = 0.6, 0.4
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = 0
	for _, e in Lighting:GetChildren() do
		if e:IsA("PostEffect") or e:IsA("Atmosphere") or e:IsA("Sky") then
			e:Destroy()
		end
	end
	local atmo = Instance.new("Atmosphere")
	atmo.Density, atmo.Offset, atmo.Haze, atmo.Glare = 0.22, 0.1, 0.6, 0
	atmo.Color, atmo.Decay = Color3.fromRGB(199, 220, 255), Color3.fromRGB(180, 205, 240)
	atmo.Parent = Lighting
	local clouds = Instance.new("Clouds")
	clouds.Cover, clouds.Density, clouds.Color = 0.55, 0.35, Color3.new(1, 1, 1)
	clouds.Parent = workspace.Terrain
end

function MapService.build(): (Folder, BasePart)
	local map = Instance.new("Folder")
	map.Name = "Map"
	static = Instance.new("Folder")
	static.Name = "Static"
	static.Parent = map
	props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = map
	lighting()
	local old = workspace:FindFirstChild("Baseplate")
	if old then
		old:Destroy()
	end
	local HALF = Config.Map.SIZE / 2

	-- Ground ------------------------------------------------------------
	block("Baseplate", Vector3.new(2048, 8, 2048), Vector3.new(0, -4, 0), C.grassDark, Enum.Material.Grass)
	local field = pad("Sandbox", Config.Map.SIZE, Config.Map.SIZE, 0, 0, C.grass, 0.02, Enum.Material.Grass)
	field.CanCollide = false
	for _, s in { -1, 1 } do -- low berm + invisible wall so ground vehicles cannot get lost
		block("Berm", Vector3.new(Config.Map.SIZE + 24, 5, 12), Vector3.new(0, 2.5, s * (HALF + 6)), C.grassDark, Enum.Material.Grass)
		block("Berm", Vector3.new(12, 5, Config.Map.SIZE + 24), Vector3.new(s * (HALF + 6), 2.5, 0), C.grassDark, Enum.Material.Grass)
		local w1 = block("Boundary", Vector3.new(Config.Map.SIZE + 24, 34, 2), Vector3.new(0, 17, s * (HALF + 11)), C.white)
		local w2 = block("Boundary", Vector3.new(2, 34, Config.Map.SIZE + 24), Vector3.new(s * (HALF + 11), 17, 0), C.white)
		w1.Transparency, w2.Transparency = 1, 1
	end
	local rng = Random.new(3)
	for i = 1, 14 do -- distant decorative hills
		local a = i / 14 * math.pi * 2
		local r, size = rng:NextNumber(620, 900), rng:NextNumber(160, 320)
		local hill = block("Hill", Vector3.one * size, Vector3.new(math.cos(a) * r, -size * 0.28, math.sin(a) * r), C.grassDark, Enum.Material.Grass)
		hill.Shape = Enum.PartType.Ball
	end

	-- Central spawn area --------------------------------------------------
	pad("Plaza", 130, 80, 0, 40, C.concrete, 0.1, Enum.Material.Concrete)
	for i = -3, 3 do -- tile seams, like the tiled floors of the reference sandboxes
		mark(0.3, 80, i * 16, 40, C.concreteDark, 0.13)
	end
	pad("TestLane", 30, 150, 0, -75, C.asphalt, 0.1, Enum.Material.Asphalt)
	for z = -10, -140, -20 do
		mark(1, 10, 0, z, C.line)
	end
	mark(30, 2, 0, -2, C.yellow)
	mark(30, 1.5, 0, -32, C.white)
	signOnPosts("CRASH TESTING", 0, -158, 46, 14)
	local spawn = Instance.new("SpawnLocation")
	spawn.Size = Vector3.new(10, 0.4, 10)
	spawn.Anchored = true
	spawn.Color = Color3.fromHex(C.blue)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.CFrame = CFrame.new(12, 0.3, 52) -- player faces -Z: the car, then the dummies
	spawn.Parent = static
	-- equipment-testing building (open front)
	block("LabFloor", Vector3.new(30, 0.4, 22), Vector3.new(-45, 0.3, 58), C.white)
	block("LabWall", Vector3.new(30, 12, 1), Vector3.new(-45, 6, 69), C.concreteDark, Enum.Material.Concrete)
	block("LabWall", Vector3.new(1, 12, 22), Vector3.new(-60, 6, 58), C.concreteDark, Enum.Material.Concrete)
	block("LabWall", Vector3.new(1, 12, 22), Vector3.new(-30, 6, 58), C.concreteDark, Enum.Material.Concrete)
	block("LabRoof", Vector3.new(32, 1, 24), Vector3.new(-45, 12.5, 58), C.blue)
	sign("TEST LAB", Vector3.new(-45, 10, 46.6), Vector3.new(16, 3, 0.4), 0, C.blue, C.white)
	scaffold(52, 62, 2)
	-- quick-spawn pads
	MapService.stations = {}
	for i, key in { "Sedan", "MonsterTruck", "Tank", "SmallPlane" } do
		local p = block("Station" .. key, Vector3.new(8, 0.5, 8), Vector3.new(38 + (i - 1) * 0, 0.35, 12 + (i - 1) * 10), C.blue)
		p.Material = Enum.Material.Neon
		p.Transparency = 0.25
		local post = sign(string.upper(key), Vector3.new(44, 4, 12 + (i - 1) * 10), Vector3.new(0.4, 2.2, 8), 0, C.dark, C.white)
		post.CFrame = CFrame.new(44, 4, 12 + (i - 1) * 10) * CFrame.Angles(0, math.rad(90), 0)
		post.Size = Vector3.new(8, 2.2, 0.4)
		table.insert(MapService.stations, { part = p, key = key })
	end

	-- Zone A: dummy testing field ------------------------------------------
	pad("DummyFieldPad", 70, 60, -230, -70, C.concrete, 0.1, Enum.Material.Concrete)
	pad("BowlingLane", 18, 170, -150, -105, C.asphalt, 0.1, Enum.Material.Asphalt)
	mark(18, 1.5, -150, -30, C.yellow)
	for z = -40, -130, -18 do
		mark(0.8, 8, -150, z, C.line)
	end
	signOnPosts("DUMMY FIELD", -190, -18, 40, 12)
	-- dummy wall: slab on two knock-out supports
	loose("WallSupport", Vector3.new(4, 8.5, 6), Vector3.new(-250, 4.35, -150), C.concreteDark, 1.2, Enum.Material.Concrete)
	loose("WallSupport", Vector3.new(4, 8.5, 6), Vector3.new(-220, 4.35, -150), C.concreteDark, 1.2, Enum.Material.Concrete)
	loose("WallSlab", Vector3.new(40, 1, 8), Vector3.new(-235, 9.1, -150), C.yellow, 0.5)
	-- dummy tower: three loose levels
	for l = 0, 2 do
		local y = l * 9
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				loose("TowerPillar", Vector3.new(2, 8, 2), Vector3.new(-200 + sx * 7, y + 4.2, -160 + sz * 5), C.steel, 1.0, Enum.Material.Metal)
			end
		end
		loose("TowerSlab", Vector3.new(18, 1, 14), Vector3.new(-200, y + 8.7, -160), if l % 2 == 0 then C.red else C.white, 0.6)
	end

	-- Zone B: high-speed crash track -----------------------------------------
	pad("CrashTrack", 340, 32, 0, 260, C.asphalt, 0.1, Enum.Material.Asphalt)
	for x = -150, 150, 24 do
		mark(12, 1, x, 260, C.line)
	end
	for i = 0, 7 do -- chequered start line
		mark(2, 4, -160 + (i % 2) * 2, 246 + i * 4, if i % 2 == 0 then C.white else "#15171c")
	end
	signOnPosts("HIGH-SPEED TRACK  >>>", -150, 238, 44, 12)
	block("CrashBarrier", Vector3.new(6, 12, 40), Vector3.new(175, 6, 260), C.concreteDark, Enum.Material.Concrete)
	for i = 0, 4 do
		block("BarrierStripe", Vector3.new(0.2, 2, 4), Vector3.new(171.9, 3, 244 + i * 8), if i % 2 == 0 then C.yellow else "#15171c")
	end
	brickWall(110, 260, 7, 4, false)
	foamCubes(150, 260, 4, 2, 7, false)

	-- Zone C: giant ramps -----------------------------------------------------
	pad("RampApron", 150, 60, 150, -30, C.concrete, 0.1, Enum.Material.Concrete)
	signOnPosts("RAMPS", 150, -4, 30, 12)
	ramp("BeginnerRamp", 20, 6, 26, 105, -60, C.yellow)
	ramp("LongRamp", 28, 25, 100, 150, -60, C.red)
	block("LongRampDeck", Vector3.new(28, 1, 8), Vector3.new(150, 24.5, -164), C.red)
	block("LongRampSupport", Vector3.new(24, 24, 6), Vector3.new(150, 12, -165), C.concreteDark, Enum.Material.Concrete)
	ramp("LaunchRamp", 22, 30, 46, 198, -60, C.blue)
	block("LaunchSupport", Vector3.new(20, 30, 3), Vector3.new(198, 15, -107.5), C.concreteDark, Enum.Material.Concrete)
	block("TargetPlatform", Vector3.new(60, 1, 34), Vector3.new(150, 24.5, -205), C.concrete, Enum.Material.Concrete)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			block("PlatformLeg", Vector3.new(4, 24, 4), Vector3.new(150 + sx * 26, 12, -205 + sz * 13), C.concreteDark, Enum.Material.Concrete)
		end
	end
	foamCubes(150, -216, 5, 2, 6, true)

	-- Zone D: airfield ----------------------------------------------------------
	pad("Runway", 44, 620, 290, 0, "#3f4249", 0.1, Enum.Material.Asphalt)
	for z = -290, 290, 30 do
		mark(1.4, 14, 290, z, C.line)
	end
	for _, z in { 300, -300 } do
		for i = -3, 3 do
			mark(3, 12, 290 + i * 5.5, z, C.line)
		end
	end
	pad("Apron", 60, 150, 240, 215, C.concrete, 0.1, Enum.Material.Concrete)
	for i, z in { 240, 190 } do
		block("HangarBack", Vector3.new(2, 20, 40), Vector3.new(214, 10, z), C.steel, Enum.Material.Metal)
		block("HangarSide", Vector3.new(44, 20, 2), Vector3.new(235, 10, z - 20), C.steel, Enum.Material.Metal)
		block("HangarSide", Vector3.new(44, 20, 2), Vector3.new(235, 10, z + 20), C.steel, Enum.Material.Metal)
		block("HangarRoof", Vector3.new(46, 2, 44), Vector3.new(236, 21, z), if i == 1 then C.blue else C.red)
	end
	block("TowerShaft", Vector3.new(8, 34, 8), Vector3.new(246, 17, 96), C.white, Enum.Material.Concrete)
	local cab = block("TowerCab", Vector3.new(14, 7, 14), Vector3.new(246, 37.5, 96), "#9fd3ee", Enum.Material.Glass)
	cab.Transparency = 0.4
	block("TowerRoof", Vector3.new(16, 1, 16), Vector3.new(246, 41.5, 96), C.red)
	local helipad = pad("Helipad", 30, 30, 236, 150, C.dark, 0.14)
	helipad.Shape = Enum.PartType.Block
	mark(3, 16, 231, 150, C.yellow, 0.18)
	mark(3, 16, 241, 150, C.yellow, 0.18)
	mark(10, 3, 236, 150, C.yellow, 0.18)
	signOnPosts("AIRFIELD", 262, 318, 30, 12)
	-- aircraft crash target: padded wall + dummy deck near the far end of the runway
	foamCubes(232, -270, 6, 4, 8, true)
	block("TargetDeck", Vector3.new(40, 1, 12), Vector3.new(232, 11.5, -252), C.yellow)
	block("TargetDeckLeg", Vector3.new(3, 11, 3), Vector3.new(214, 5.5, -252), C.dark, Enum.Material.Metal)
	block("TargetDeckLeg", Vector3.new(3, 11, 3), Vector3.new(250, 5.5, -252), C.dark, Enum.Material.Metal)
	scaffold(205, -215, 3)

	-- Zone E: tank / heavy vehicle field ----------------------------------------
	pad("TankField", 160, 150, -220, 120, C.dirt, 0.1, Enum.Material.Ground)
	signOnPosts("HEAVY VEHICLES", -220, 200, 44, 12)
	for i, z in { 150, 110, 70 } do
		block("Barrier", Vector3.new(14, 4, 3), Vector3.new(-260 + i * 14, 2, z), C.concreteDark, Enum.Material.Concrete)
	end
	brickWall(-220, 140, 8, 5, true)
	brickWall(-190, 95, 6, 4, true)
	foamCubes(-250, 95, 3, 3, 7, true)
	for i, x in { -270, -240, -180 } do -- bumps
		ramp("Bump", 18, 3, 12, x, 70 - i * 3, C.dirt).Material = Enum.Material.Ground
	end
	loose("Crate", Vector3.new(6, 6, 6), Vector3.new(-160, 3.2, 150), C.wood, 0.3, Enum.Material.WoodPlanks)
	loose("Crate", Vector3.new(6, 6, 6), Vector3.new(-160, 9.3, 150), C.wood, 0.3, Enum.Material.WoodPlanks)
	loose("Crate", Vector3.new(6, 6, 6), Vector3.new(-167, 3.2, 150), C.wood, 0.3, Enum.Material.WoodPlanks)

	-- Zone F: destruction yard ----------------------------------------------------
	pad("Yard", 140, 110, 120, 130, C.concreteDark, 0.1, Enum.Material.Concrete)
	signOnPosts("DESTRUCTION YARD", 120, 70, 48, 12)
	for i, c in { C.red, C.blue, C.yellow, "#3d8f4a" } do
		block("Container", Vector3.new(10, 10, 26), Vector3.new(70 + i * 12, 5.2, 170), c, Enum.Material.Metal)
	end
	block("Container", Vector3.new(10, 10, 26), Vector3.new(88, 15.2, 170), C.white, Enum.Material.Metal)
	block("Container", Vector3.new(10, 10, 26), Vector3.new(106, 15.2, 170), C.red, Enum.Material.Metal)
	loose("LooseContainer", Vector3.new(10, 10, 22), Vector3.new(150, 5.3, 165), C.blue, 0.25, Enum.Material.Metal)
	brickWall(100, 110, 8, 5, true)
	foamCubes(150, 110, 3, 2, 12, true)
	for i = 0, 3 do
		block("JerseyBarrier", Vector3.new(12, 4, 3), Vector3.new(70 + i * 14, 2, 90), C.concrete, Enum.Material.Concrete)
	end
	-- suspended collision targets on a gantry
	block("GantryLeg", Vector3.new(2, 26, 2), Vector3.new(150, 13, 140), C.yellow, Enum.Material.Metal)
	block("GantryLeg", Vector3.new(2, 26, 2), Vector3.new(180, 13, 140), C.yellow, Enum.Material.Metal)
	local beam = block("GantryBeam", Vector3.new(34, 2, 2), Vector3.new(165, 27, 140), C.yellow, Enum.Material.Metal)
	for _, dx in { -7, 7 } do
		local ball = loose("WreckingTarget", Vector3.one * 7, Vector3.new(165 + dx, 9, 140), C.red, 0.4)
		ball.Shape = Enum.PartType.Ball
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Position = Vector3.new(dx, -1, 0)
		a0.Parent = beam
		a1.Position = Vector3.new(0, 3.5, 0)
		a1.Parent = ball
		local rope = Instance.new("RopeConstraint")
		rope.Attachment0, rope.Attachment1 = a0, a1
		rope.Length = 13.5
		rope.Visible = true
		rope.Thickness = 0.3
		rope.Parent = beam
	end

	-- Railway (train) -----------------------------------------------------------------
	local RX = -330
	pad("RailBed", 16, 640, RX, 0, "#8a7a66", 0.1, Enum.Material.Slate)
	for z = -310, 310, 12 do
		local s = pad("Sleeper", 13, 2.4, RX, z, "#5c4630", 0.3, Enum.Material.Wood)
		s.CanCollide = false
	end
	for _, dx in { -4.2, 4.2 } do
		local rail = block("RailSteel", Vector3.new(0.8, 0.5, 640), Vector3.new(RX + dx, 0.55, 0), C.steel, Enum.Material.Metal)
		rail.CanCollide = false
	end
	pad("Crossing", 60, 20, RX + 14, 0, C.asphalt, 0.32, Enum.Material.Asphalt)
	for i = -2, 2 do
		mark(4, 16, RX + i * 5, 0, if i % 2 == 0 then C.yellow else C.asphalt, 0.36)
	end
	signOnPosts("CRASH TEST CROSSING", RX + 36, -16, 40, 12, 90)
	block("BufferStop", Vector3.new(12, 8, 4), Vector3.new(RX, 4, -316), C.red, Enum.Material.Metal)
	local anchor = block("RailAnchor", Vector3.new(1, 1, 1), Vector3.new(RX, 8, 285), C.dark)
	anchor.Transparency, anchor.CanCollide, anchor.CanQuery = 1, false, false

	-- Rocket sled track ------------------------------------------------------------------
	pad("SledTrack", 12, 620, 335, 0, C.steel, 0.1, Enum.Material.Metal)
	for z = -300, 300, 40 do
		mark(12, 1, 335, z, C.yellow)
	end
	foamCubes(335, -306, 2, 3, 6, true)

	map.Parent = workspace
	return map, anchor
end

return MapService
