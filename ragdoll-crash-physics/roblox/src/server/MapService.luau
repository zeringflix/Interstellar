--!nonstrict
-- Builds the whole sandbox procedurally at server start: one continuous 700 x 700 stud test ground
-- (bright grass baseplate, flat tiled plaza, scaffolding, containers, ramps - the look shared by
-- the current top ragdoll sandboxes) with six connected crash-test zones.
-- Anchored geometry goes in workspace.Map.Static, knock-about props in workspace.Map.Props.
local Lighting = game:GetService("Lighting")
local Config = require(game.ReplicatedStorage.Shared.GameConfig)

local MapService = {}
local static: Folder, props: Folder

-- Three maps share the same test-zone layout (so every preset, spawn and zone teleport works on
-- all of them) and differ in ground, palette, lighting and scenery.
local THEMES = {
	-- ground = the tiled test-ground floor (warm concrete, like the reference sandboxes), tile = its seams,
	-- tile2 = the alternate checker tone, lawn = the few grass patches, outer = beyond the fence
	["Test Grounds"] = { ground = "#cfc8b8", tile = "#bdb5a3", tile2 = "#c7bfae", lawn = "#86a873", outer = "#9a9486", hill = "#8f9a7d",
		scenery = "trees", clock = 13.5, sky = { 199, 220, 255 } },
	Downtown = { ground = "#a9adb3", tile = "#969aa1", tile2 = "#a0a4aa", lawn = "#7f9a72", outer = "#868a90", hill = "#7d828a",
		scenery = "city", clock = 16.2, sky = { 214, 222, 235 } },
	["Desert Range"] = { ground = "#e0c896", tile = "#cdb37f", tile2 = "#d7bd89", lawn = "#a7a46a", outer = "#c9a96b", hill = "#c29a64",
		scenery = "desert", clock = 11.0, sky = { 255, 236, 200 } },
}
MapService.current = "Test Grounds"

local C = {
	grass = "#58c96a", grassDark = "#3fae55", concrete = "#b9bcc2", concreteDark = "#8f939b", asphalt = "#4a4d55",
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

-- ramp rising along `dir` (unit vector in XZ) from its low edge at (x, z)
local function rampAt(name: string, width: number, height: number, length: number, x: number, z: number, dir: Vector3, color: string): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Size = Vector3.new(width, height, length)
	local centre = Vector3.new(x, height / 2, z) + dir * (length / 2)
	-- WedgePart: tall face is the back (+Z local), slope bottom at the front (-Z), so the back faces along dir
	w.CFrame = CFrame.lookAt(centre, centre - dir)
	w.Color = Color3.fromHex(color)
	w.Material = Enum.Material.SmoothPlastic
	w.Anchored = true
	w.Parent = static
	return w
end

-- asphalt road between two points on the ground, with kerb edges, white edge lines and a dashed
-- yellow centre line. Roads sit at 0.12 so they never z-fight with the 0.1 zone pads.
local function road(name: string, a: Vector2, b: Vector2, width: number)
	local d = b - a
	local len = d.Magnitude
	local mid = (a + b) / 2
	local along = Vector3.new(d.X, 0, d.Y).Unit
	local cf = CFrame.lookAt(Vector3.new(mid.X, 0, mid.Y), Vector3.new(mid.X, 0, mid.Y) + along)
	local function strip(n: string, w: number, l: number, offX: number, offZ: number, top: number, color: string, mat: Enum.Material?)
		local p = block(n, Vector3.new(w, 0.4, l), Vector3.zero, color, mat)
		p.CFrame = cf * CFrame.new(offX, top - 0.2, offZ)
		return p
	end
	strip(name, width, len, 0, 0, 0.12, C.asphalt, Enum.Material.Asphalt)
	for _, s in { -1, 1 } do
		strip("EdgeLine", 0.6, len - 2, s * (width / 2 - 1.4), 0, 0.15, C.line).CanCollide = false
		strip("Kerb", 1.2, len, s * (width / 2 + 0.6), 0, 0.32, C.concrete, Enum.Material.Concrete)
	end
	local dash = 0
	while dash + 6 < len - 4 do
		strip("CentreLine", 0.6, 6, 0, -len / 2 + 4 + dash + 3, 0.15, C.yellow).CanCollide = false
		dash += 12
	end
end

local function crosswalk(x: number, z: number, width: number, alongX: boolean)
	for k = -3, 3 do
		if alongX then
			mark(2, width - 4, x + k * 3.4, z, C.white, 0.16)
		else
			mark(width - 4, 2, x, z + k * 3.4, C.white, 0.16)
		end
	end
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

local function lighting(theme)
	Lighting.ClockTime = theme.clock
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
	atmo.Color, atmo.Decay = Color3.fromRGB(theme.sky[1], theme.sky[2], theme.sky[3]), Color3.fromRGB(180, 205, 240)
	atmo.Parent = Lighting
	local oldClouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if oldClouds then
		oldClouds:Destroy()
	end
	local clouds = Instance.new("Clouds")
	clouds.Cover, clouds.Density, clouds.Color = 0.55, 0.35, Color3.new(1, 1, 1)
	clouds.Parent = workspace.Terrain
end

-- Free strips between the test zones where scenery may go: { x0, x1, z0, z1 }
local FREE = { { -100, -30, -160, -20 }, { 25, 65, -200, -70 }, { -125, -18, 95, 230 }, { 18, 40, 100, 230 }, { -300, 250, 324, 342 }, { -300, -20, -285, -240 }, { 20, 100, -285, -240 }, { 220, 258, -170, 12 } }

local function scatter(count: number, gap: number, seed: number): { Vector3 }
	local rng = Random.new(seed)
	local out = {}
	local tries = 0
	while #out < count and tries < count * 30 do
		tries += 1
		local r = FREE[rng:NextInteger(1, #FREE)]
		local p = Vector3.new(rng:NextNumber(r[1], r[2]), 0, rng:NextNumber(r[3], r[4]))
		local ok = true
		for _, o in out do
			if (o - p).Magnitude < gap then
				ok = false
				break
			end
		end
		if ok then
			table.insert(out, p)
		end
	end
	return out
end

function MapService.scenery(kind: string)
	local rng = Random.new(11)
	if kind == "trees" then
		for _, p in scatter(44, 16, 5) do -- low-poly trees: trunk + two leaf blocks
			local h = rng:NextNumber(9, 15)
			block("Trunk", Vector3.new(2, h, 2), p + Vector3.new(0, h / 2, 0), "#7a5230", Enum.Material.Wood)
			local a = block("Leaves", Vector3.new(9, 6, 9), p + Vector3.new(0, h + 2, 0), "#3fae55")
			a.CFrame = CFrame.new(p + Vector3.new(0, h + 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 1.5), 0)
			local b = block("Leaves", Vector3.new(6, 5, 6), p + Vector3.new(0, h + 6.5, 0), "#58c96a")
			b.CFrame = CFrame.new(p + Vector3.new(0, h + 6.5, 0)) * CFrame.Angles(0, rng:NextNumber(0, 1.5), 0)
			a.CanCollide, b.CanCollide = false, false
		end
		for _, p in scatter(10, 40, 9) do -- grey concrete blocks and crates, as in the reference maps
			block("ConcreteBlock", Vector3.new(14, 10, 14), p + Vector3.new(0, 5, 0), C.concrete, Enum.Material.Concrete)
			loose("Crate", Vector3.new(5, 5, 5), p + Vector3.new(11, 2.7, 0), C.wood, 0.3, Enum.Material.WoodPlanks)
		end
	elseif kind == "city" then
		local cols = { "#c9ced6", "#b7a99a", "#9db1c4", "#d6c9b0", "#a8adb5" }
		for i, p in scatter(22, 34, 21) do -- office blocks with window bands and roof plant
			local w, d, h = rng:NextNumber(20, 30), rng:NextNumber(20, 30), rng:NextNumber(28, 70)
			block("Building", Vector3.new(w, h, d), p + Vector3.new(0, h / 2, 0), cols[i % #cols + 1], Enum.Material.Concrete)
			for y = 8, h - 4, 8 do
				block("Windows", Vector3.new(w + 0.3, 3.2, d + 0.3), p + Vector3.new(0, y, 0), "#2b3a4d", Enum.Material.Glass).CanCollide = false
			end
			block("RoofPlant", Vector3.new(w * 0.4, 3, d * 0.4), p + Vector3.new(0, h + 1.5, 0), C.steel, Enum.Material.Metal).CanCollide = false
		end
		for _, p in scatter(24, 22, 33) do -- street lamps
			block("LampPost", Vector3.new(0.6, 16, 0.6), p + Vector3.new(0, 8, 0), C.dark, Enum.Material.Metal)
			block("LampHead", Vector3.new(3.4, 0.5, 1.2), p + Vector3.new(1.4, 16, 0), "#fff3c4", Enum.Material.Neon).CanCollide = false
		end
		for _, p in scatter(18, 12, 44) do
			loose("Cone", Vector3.new(1.6, 2.4, 1.6), p + Vector3.new(0, 1.3, 0), "#ff7a1a", 0.2)
		end
	else -- desert
		for _, p in scatter(26, 22, 51) do -- sandstone outcrops
			local sz = rng:NextNumber(10, 26)
			local rock = block("Rock", Vector3.new(sz, sz * rng:NextNumber(0.6, 1.3), sz * rng:NextNumber(0.7, 1.2)), p + Vector3.new(0, sz * 0.25, 0), "#b98a5a", Enum.Material.Sandstone)
			rock.CFrame = CFrame.new(p + Vector3.new(0, sz * 0.25, 0)) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, 3), rng:NextNumber(-0.2, 0.2))
		end
		for _, p in scatter(30, 14, 63) do -- saguaro cacti
			local h = rng:NextNumber(7, 12)
			local trunk = block("Cactus", Vector3.new(h, 1.8, 1.8), p + Vector3.new(0, h / 2, 0), "#4f8f4a")
			trunk.Shape = Enum.PartType.Cylinder
			trunk.CFrame = CFrame.new(p + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
			local arm = block("CactusArm", Vector3.new(3.4, 1.2, 1.2), p + Vector3.new(1.6, h * 0.55, 0), "#4f8f4a")
			arm.Shape = Enum.PartType.Cylinder
			arm.CanCollide = false
		end
		for _, p in scatter(6, 60, 71) do -- timber shacks
			block("Shack", Vector3.new(16, 9, 12), p + Vector3.new(0, 4.5, 0), "#9a7146", Enum.Material.WoodPlanks)
			block("ShackRoof", Vector3.new(18, 0.8, 14), p + Vector3.new(0, 9.4, 0), "#6b4a2c", Enum.Material.WoodPlanks).CanCollide = false
		end
	end
end

function MapService.build(name: string?): (Folder, BasePart)
	local theme = THEMES[name or ""] or THEMES["Test Grounds"]
	MapService.current = if THEMES[name or ""] then name :: string else "Test Grounds"
	C.grass, C.grassDark = theme.lawn, theme.outer
	local previous = workspace:FindFirstChild("Map")
	if previous and previous:GetAttribute("Prebuilt") == MapService.current and previous:FindFirstChild("Static") then
		-- the place file ships with this map already built (tools/bake_place.luau): reuse it as-is,
		-- so anything you change in Studio's editor is what players get
		static = previous.Static :: Folder
		props = previous:FindFirstChild("Props") :: Folder
		lighting(theme)
		MapService.stations = {}
		for _, key in { "Sedan", "MonsterTruck", "Tank", "SmallPlane" } do
			local st = static:FindFirstChild("Station" .. key)
			if st then
				table.insert(MapService.stations, { part = st, key = key })
			end
		end
		previous:SetAttribute("Prebuilt", nil)
		return previous, static:FindFirstChild("RailAnchor") :: BasePart
	end
	if previous then
		previous:Destroy()
	end
	local map = Instance.new("Folder")
	map.Name = "Map"
	static = Instance.new("Folder")
	static.Name = "Static"
	static.Parent = map
	props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = map
	lighting(theme)
	local old = workspace:FindFirstChild("Baseplate")
	if old then
		old:Destroy()
	end
	local HALF = Config.Map.SIZE / 2

	-- Ground ------------------------------------------------------------
	block("Baseplate", Vector3.new(2048, 8, 2048), Vector3.new(0, -4, 0), theme.outer, Enum.Material.Ground)
	local field = pad("Sandbox", Config.Map.SIZE, Config.Map.SIZE, 0, 0, theme.ground, 0.02, Enum.Material.SmoothPlastic)
	field.CanCollide = false
	for _, s in { -1, 1 } do -- low concrete wall + invisible fence so ground vehicles cannot get lost
		block("Berm", Vector3.new(Config.Map.SIZE + 24, 4, 3), Vector3.new(0, 2, s * (HALF + 6)), C.concreteDark, Enum.Material.Concrete)
		block("Berm", Vector3.new(3, 4, Config.Map.SIZE + 24), Vector3.new(s * (HALF + 6), 2, 0), C.concreteDark, Enum.Material.Concrete)
		local w1 = block("Boundary", Vector3.new(Config.Map.SIZE + 24, 34, 2), Vector3.new(0, 17, s * (HALF + 11)), C.white)
		local w2 = block("Boundary", Vector3.new(2, 34, Config.Map.SIZE + 24), Vector3.new(s * (HALF + 11), 17, 0), C.white)
		w1.Transparency, w2.Transparency = 1, 1
	end
	-- 48-stud floor tiles: a soft two-tone checker (one part per dark tile row-run) plus thin seams
	local T = 48
	local n = math.floor(Config.Map.SIZE / T / 2)
	for i = -n, n - 1 do
		for j = -n, n - 1 do
			if (i + j) % 2 == 0 then
				local t = pad("Tile", T, T, (i + 0.5) * T, (j + 0.5) * T, theme.tile2, 0.035)
				t.CanCollide, t.CanQuery = false, false
			end
		end
	end
	for k = -n, n do
		mark(0.4, Config.Map.SIZE, k * T, 0, theme.tile, 0.05)
		mark(Config.Map.SIZE, 0.4, 0, k * T, theme.tile, 0.05)
	end
	-- a few lawns, so the ground is mostly concrete with green accents rather than a green field
	for _, l in { { -90, -190, 60, 50 }, { 60, -250, 70, 50 }, { -60, 160, 60, 110 }, { 80, -110, 30, 60 }, { 200, -40, 30, 60 } } do
		local lawn = pad("Lawn", l[3], l[4], l[1], l[2], theme.lawn, 0.06, Enum.Material.Grass)
		lawn.CanCollide = false
		mark(l[3] + 1.2, 0.6, l[1], l[2] - l[4] / 2, C.concrete, 0.07)
		mark(l[3] + 1.2, 0.6, l[1], l[2] + l[4] / 2, C.concrete, 0.07)
		mark(0.6, l[4], l[1] - l[3] / 2, l[2], C.concrete, 0.07)
		mark(0.6, l[4], l[1] + l[3] / 2, l[2], C.concrete, 0.07)
	end
	local rng = Random.new(3)
	for i = 1, 14 do -- distant decorative hills
		local a = i / 14 * math.pi * 2
		local r, size = rng:NextNumber(620, 900), rng:NextNumber(160, 320)
		local hill = block("Hill", Vector3.one * size, Vector3.new(math.cos(a) * r, -size * 0.28, math.sin(a) * r), theme.hill, Enum.Material.Ground)
		hill.Shape = Enum.PartType.Ball
	end

	-- Central spawn area --------------------------------------------------
	pad("Plaza", 130, 80, 0, 40, C.concrete, 0.1, Enum.Material.Concrete)
	pad("SpawnDeck", 34, 26, 12, 58, C.wood, 0.16, Enum.Material.WoodPlanks) -- wooden spawn deck
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
	brickWall(110, 260, 6, 4, false)
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
	foamCubes(232, -270, 5, 3, 8, true)
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
	brickWall(-220, 140, 6, 4, true)
	brickWall(-190, 95, 5, 3, true)
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
	brickWall(100, 110, 6, 4, true)
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

	-- Railway: ballasted track that runs the length of the map and ENDS in a buffer stop ----------
	local RX = -330
	pad("BallastBase", 19, 640, RX, 0, "#77705f", 0.22, Enum.Material.Slate)
	pad("BallastTop", 14, 640, RX, 0, "#8a8372", 0.5, Enum.Material.Slate)
	for z = -316, 316, 4 do -- timber sleepers
		local s = block("Sleeper", Vector3.new(11.5, 0.5, 1.5), Vector3.new(RX, 0.55, z), "#4d3a28", Enum.Material.Wood)
		s.CanCollide = false
	end
	for _, dx in { -4.2, 4.2 } do -- flat-bottom rail: foot, web, head
		for _, r in { { 1.2, 0.14, 0.87, "#5d6169" }, { 0.3, 0.55, 1.2, "#5d6169" }, { 0.62, 0.3, 1.6, "#b9bec6" } } do
			local rail = block("Rail", Vector3.new(r[1], r[2], 640), Vector3.new(RX + dx, r[3], 0), r[4], Enum.Material.Metal)
			rail.CanCollide = false
		end
		for z = -300, 300, 40 do -- fishplates at the rail joints
			block("Fishplate", Vector3.new(0.5, 0.4, 3), Vector3.new(RX + dx, 1.2, z), "#3a3d43", Enum.Material.Metal).CanCollide = false
		end
	end
	-- dead end: buffer stop built from rail, with a sand drag in front of it
	local END = -318
	for _, dx in { -4.2, 4.2 } do
		for _, a in { { 0, 0 }, { 28, 2.2 } } do
			local leg = block("BufferLeg", Vector3.new(0.7, 6.5, 0.7), Vector3.new(RX + dx, 3.6, END + a[2]), "#8b1a16", Enum.Material.Metal)
			leg.CFrame = CFrame.new(RX + dx, 3.6, END + a[2] + (if a[1] > 0 then 1.4 else 0)) * CFrame.Angles(math.rad(a[1]), 0, 0)
		end
	end
	block("BufferBeam", Vector3.new(12, 1.6, 1.2), Vector3.new(RX, 5.6, END), C.red, Enum.Material.Metal)
	for k = -2, 2 do
		block("BufferStripe", Vector3.new(1.2, 1.62, 1.22), Vector3.new(RX + k * 2.4, 5.6, END), C.white, Enum.Material.Metal).CanCollide = false
	end
	local lamp = block("BufferLamp", Vector3.new(0.9, 0.9, 0.6), Vector3.new(RX, 7.0, END + 0.4), "#ff2b2b", Enum.Material.Neon)
	lamp.Shape = Enum.PartType.Cylinder
	lamp.CFrame = CFrame.new(RX, 7.0, END + 0.4) * CFrame.Angles(0, math.rad(90), 0)
	block("SandDrag", Vector3.new(13, 1.4, 16), Vector3.new(RX, 0.9, END + 12), "#d9c08a", Enum.Material.Sand).CanCollide = false
	block("EndWall", Vector3.new(16, 9, 2), Vector3.new(RX, 4.5, END - 3), C.concreteDark, Enum.Material.Concrete)
	sign("END OF TRACK", Vector3.new(RX + 9.5, 6, END + 6), Vector3.new(7, 2.4, 0.4), 0, C.red, C.white)
	block("SignPost", Vector3.new(0.5, 6, 0.5), Vector3.new(RX + 9.5, 3, END + 6), C.dark, Enum.Material.Metal)
	-- level crossing: road deck, crossbucks, warning lights, raised barrier arms
	pad("Crossing", 60, 20, RX + 14, 0, C.asphalt, 0.62, Enum.Material.Asphalt)
	for _, dx in { -1.4, 1.4 } do
		mark(1.0, 20, RX + dx * 3, 0, C.yellow, 0.66)
	end
	for _, sz in { -1, 1 } do
		local px, pz = RX + sz * 9, sz * 12
		block("CrossPost", Vector3.new(0.6, 13, 0.6), Vector3.new(px, 6.5, pz), C.white, Enum.Material.Metal)
		for _, rot in { 35, -35 } do
			local arm = block("Crossbuck", Vector3.new(7, 1.1, 0.25), Vector3.new(px, 11.5, pz), C.white)
			arm.CFrame = CFrame.new(px, 11.5, pz) * CFrame.Angles(0, math.rad(90), math.rad(rot))
			arm.CanCollide = false
		end
		for _, dz in { -1.3, 1.3 } do
			local l = block("CrossLight", Vector3.new(0.4, 1.3, 1.3), Vector3.new(px, 8.6, pz + dz), "#ff2b2b", Enum.Material.Neon)
			l.Shape = Enum.PartType.Cylinder
			l.CanCollide = false
		end
		block("GateBase", Vector3.new(1.6, 4, 1.6), Vector3.new(px + sz * 3, 2, pz), C.dark, Enum.Material.Metal)
		local gate = block("GateArm", Vector3.new(0.5, 22, 0.5), Vector3.new(px + sz * 3, 14, pz), C.red)
		gate.CanCollide = false
		for k = 0, 4 do
			block("GateStripe", Vector3.new(0.52, 2.2, 0.52), Vector3.new(px + sz * 3, 5.5 + k * 4.4, pz), C.white).CanCollide = false
		end
	end
	signOnPosts("CRASH TEST CROSSING", RX + 36, -16, 40, 12, 90)
	-- station halt with canopy, signal and line-side poles
	block("Platform", Vector3.new(12, 2.4, 70), Vector3.new(RX + 14, 1.2, 150), C.concrete, Enum.Material.Concrete)
	block("PlatformEdge", Vector3.new(1.2, 0.1, 70), Vector3.new(RX + 8.8, 2.45, 150), C.yellow).CanCollide = false
	for z = 130, 170, 20 do
		block("CanopyPost", Vector3.new(0.7, 9, 0.7), Vector3.new(RX + 17, 6.9, z), C.dark, Enum.Material.Metal)
	end
	block("Canopy", Vector3.new(10, 0.6, 50), Vector3.new(RX + 15, 11.6, 150), C.blue, Enum.Material.Metal)
	block("Bench", Vector3.new(1.6, 1.2, 8), Vector3.new(RX + 18, 3.0, 150), C.wood, Enum.Material.WoodPlanks)
	local stationSign = sign("CRASH JUNCTION", Vector3.new(RX + 19.4, 7.5, 150), Vector3.new(0.4, 2.4, 16), 0, C.blue, C.white)
	stationSign.CFrame = CFrame.new(RX + 19.4, 7.5, 150) * CFrame.Angles(0, math.rad(90), 0)
	stationSign.Size = Vector3.new(16, 2.4, 0.4)
	block("SignalMast", Vector3.new(0.6, 16, 0.6), Vector3.new(RX + 8, 8, 60), C.dark, Enum.Material.Metal)
	block("SignalHead", Vector3.new(1.6, 4.4, 1.2), Vector3.new(RX + 8, 15, 60), "#15171c")
	for k, col in { "#ff2b2b", "#ffb52e", "#35d24a" } do
		local l = block("SignalLamp", Vector3.new(0.3, 1.0, 1.0), Vector3.new(RX + 8, 16.4 - (k - 1) * 1.4, 60.7), col, if k == 3 then Enum.Material.Neon else Enum.Material.SmoothPlastic)
		l.Shape = Enum.PartType.Cylinder
		l.CFrame = CFrame.new(RX + 8, 16.4 - (k - 1) * 1.4, 60.7) * CFrame.Angles(0, math.rad(90), 0)
		l.CanCollide = false
	end
	for z = -280, 280, 80 do
		block("TelegraphPole", Vector3.new(0.7, 20, 0.7), Vector3.new(RX - 11, 10, z), "#5c4630", Enum.Material.Wood)
		block("Crossarm", Vector3.new(5, 0.4, 0.4), Vector3.new(RX - 11, 18.5, z), "#5c4630", Enum.Material.Wood).CanCollide = false
	end
	for _, dx in { -2, 2 } do
		block("Wire", Vector3.new(0.08, 0.08, 560), Vector3.new(RX - 11 + dx, 18.8, 0), "#22252b").CanCollide = false
	end
	local anchor = block("RailAnchor", Vector3.new(1, 1, 1), Vector3.new(RX, 8, 285), C.dark)
	anchor.Transparency, anchor.CanCollide, anchor.CanQuery = 1, false, false

	-- Rocket sled track ------------------------------------------------------------------
	pad("SledTrack", 12, 620, 335, 0, C.steel, 0.1, Enum.Material.Metal)
	for z = -300, 300, 40 do
		mark(12, 1, 335, z, C.yellow)
	end
	foamCubes(335, -306, 2, 3, 6, true)

	-- Road network linking every zone ------------------------------------------------------------
	road("NorthRoad", Vector2.new(-310, -300), Vector2.new(258, -300), 22)
	road("SouthRoad", Vector2.new(-310, 306), Vector2.new(258, 306), 22)
	road("WestAvenue", Vector2.new(-286, 0), Vector2.new(-66, 0), 20)
	road("EastAvenue", Vector2.new(66, 30), Vector2.new(266, 30), 20)
	road("NorthLink", Vector2.new(0, -166), Vector2.new(0, -289), 20)
	road("SouthLink", Vector2.new(0, 81), Vector2.new(0, 295), 20)
	crosswalk(-80, 0, 20, true)
	crosswalk(80, 30, 20, true)
	crosswalk(0, 95, 20, false)
	crosswalk(0, -180, 20, false)
	-- stunt jump on the north road: kicker, a 40-stud gap over parked containers, landing ramp
	rampAt("JumpKicker", 18, 9, 30, -190, -300, Vector3.new(1, 0, 0), C.yellow)
	rampAt("JumpLanding", 18, 7, 34, -86, -300, Vector3.new(-1, 0, 0), C.yellow)
	for k = 0, 2 do
		block("GapContainer", Vector3.new(10, 6, 20), Vector3.new(-148 + k * 12, 3, -300), ({ C.red, C.blue, "#3d8f4a" })[k + 1], Enum.Material.Metal)
	end
	sign("JUMP!", Vector3.new(-200, 8, -315), Vector3.new(12, 3, 0.5), 0)
	-- road ramps on the south road: two small kickers to launch into the high-speed track run-off
	rampAt("SouthKicker", 16, 4, 20, 120, 306, Vector3.new(1, 0, 0), C.red)
	rampAt("SouthKicker2", 16, 6, 24, -120, 306, Vector3.new(-1, 0, 0), C.red)
	-- traffic props along the avenues
	for _, p in { { -200, 12 }, { -140, 12 }, { 120, 42 }, { 200, 42 } } do
		block("LampPost", Vector3.new(0.6, 16, 0.6), Vector3.new(p[1], 8, p[2]), C.dark, Enum.Material.Metal)
		block("LampHead", Vector3.new(3.4, 0.5, 1.2), Vector3.new(p[1], 16, p[2] - 1.4), "#fff3c4", Enum.Material.Neon).CanCollide = false
	end

	MapService.scenery(theme.scenery)

	-- Performance pass: nothing on the map needs Touched; flat / tiny / non-solid parts skip shadows
	-- and spatial queries. (Dummies, vehicles and props are the only things that move.)
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanTouch = false
			local sz = d.Size
			if not d.CanCollide then
				d.CanQuery = false
				d.CastShadow = false
			elseif sz.Y < 1.2 or math.max(sz.X, sz.Y, sz.Z) < 3 then
				d.CastShadow = false
			end
			if d.Anchored then
				d.Massless = true
			end
		end
	end
	map.Parent = workspace
	return map, anchor
end

return MapService
