-- lune run tests/map_spec.luau
-- Builds the whole map with the real MapService code (against Lune's Roblox Instance API), checks
-- layout invariants, verifies every preset dummy and vehicle spawn stands on something solid, and
-- writes tests/out/map.json for the top-down render (tools/render_map.py).
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local Harness = require("./harness")

local dm = roblox.Instance.new("DataModel")
local workspace = dm:GetService("Workspace")
local lighting = dm:GetService("Lighting")
roblox.Instance.new("Terrain").Parent = workspace
local Random = {}
function Random.new(seed)
	local state = seed or 1
	local r = {}
	local function nextf()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
	function r:NextNumber(a, b)
		return a + (b - a) * nextf()
	end
	function r:NextInteger(a, b)
		return a + math.floor(nextf() * (b - a + 1))
	end
	return r
end
local h = Harness.new(true, { workspace = workspace, Random = Random, services = { Lighting = lighting, RunService = {} } })
local Config = h.require("shared/GameConfig")
local Specs = h.require("shared/VehicleSpecs")
local MapService = h.require("server/MapService")
local Scenario = h.require("server/ScenarioService")

local passed, failed = 0, 0
local function check(name: string, cond: any, detail: any?)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL", name, detail)
	end
end

local ok, map, anchor = pcall(MapService.build)
check("map builds", ok, map)
if not ok then
	process.exit(1)
end

local parts = {}
local static, loose = 0, 0
for _, d in map:GetDescendants() do
	if d:IsA("BasePart") then
		local cf = d.CFrame
		local _, yaw = cf:ToOrientation()
		local p = { name = d.Name, class = d.ClassName, size = { d.Size.X, d.Size.Y, d.Size.Z }, pos = { cf.Position.X, cf.Position.Y, cf.Position.Z },
			yaw = yaw, color = d.Color:ToHex(), anchored = d.Anchored, collide = d.CanCollide, transparency = d.Transparency,
			ball = d:IsA("Part") and d.Shape == roblox.Enum.PartType.Ball }
		table.insert(parts, p)
		if d.Anchored then
			static += 1
		else
			loose += 1
		end
	end
end
check("anchored parts " .. static, static > 150)
check("loose props " .. loose .. " within budget", loose >= 60 and loose <= 260, loose)
check("lighting is bright day", lighting.ClockTime > 10 and lighting.ClockTime < 16 and lighting.Brightness >= 2)
check("rail anchor returned", anchor and anchor.Name == "RailAnchor")
check("4 quick-spawn stations", #MapService.stations == 4)

-- Highest solid, axis-aligned surface under a point (wedges handled by their slope).
local function groundAt(x: number, z: number, maxY: number): number?
	local best = nil
	for _, p in parts do
		if p.collide and not p.ball and math.abs(p.yaw) < 0.01 or (p.collide and p.class == "WedgePart") then
			local hx, hz = p.size[1] / 2, p.size[3] / 2
			if math.abs(x - p.pos[1]) <= hx and math.abs(z - p.pos[3]) <= hz then
				local top = p.pos[2] + p.size[2] / 2
				if p.class == "WedgePart" then
					-- ramps rise towards -Z (built rotated 180)
					local t = (p.pos[3] + hz - z) / p.size[3]
					top = p.pos[2] - p.size[2] / 2 + p.size[2] * t
				end
				if top <= maxY + 0.01 and (not best or top > best) then
					best = top
				end
			end
		end
	end
	return best
end

local HALF = Config.Map.SIZE / 2
for name, s in Config.Map.Spawns do
	local y = groundAt(s[1], s[3], 3)
	check("vehicle spawn on ground: " .. name, y and y <= 0.6 and y >= 0, y)
	check("vehicle spawn inside sandbox: " .. name, math.abs(s[1]) < HALF and math.abs(s[3]) < HALF)
end
for _, key in Specs.Order do
	local spec = Specs.Vehicles[key]
	local s = Config.Map.Spawns[spec.spawn]
	-- the spawn box must not start inside a wall / building (ignore flat ground decals and loose props)
	local hx, hz = 0, 0
	for _, p in spec.parts do
		hx = math.max(hx, math.abs(p.pos[1]) + p.size[1] / 2)
		hz = math.max(hz, math.abs(p.pos[3]) + p.size[3] / 2)
	end
	local blocked = nil
	for _, p in parts do
		if p.collide and p.anchored and p.pos[2] + p.size[2] / 2 > 1.2 and p.name ~= "Boundary" and p.name ~= "Berm" and p.name ~= "Hill" then
			if math.abs(s[1] - p.pos[1]) < hx + p.size[1] / 2 and math.abs(s[3] - p.pos[3]) < hz + p.size[3] / 2 and p.pos[2] - p.size[2] / 2 < 12 then
				blocked = p.name
			end
		end
	end
	check(key .. " spawn is clear of structures", blocked == nil, blocked)
end

local presetCount = 0
for name, list in Scenario.Presets do
	check(name .. " within Automatic dummy limit", #list <= Config.DUMMY_LIMITS.Automatic, #list)
	for i, p in list do
		presetCount += 1
		check(name .. " type valid", Config.DummyTypes[p[5] or "Noob"] ~= nil)
		local y = groundAt(p[1], p[3], p[2] + 0.6)
		check(string.format("%s #%d stands on a surface (y=%.1f, ground=%s)", name, i, p[2], tostring(y)), y and math.abs(y - p[2]) <= 0.65, y)
		for j = i + 1, #list do
			local q = list[j]
			local d = math.sqrt((p[1] - q[1]) ^ 2 + (p[3] - q[3]) ^ 2)
			if math.abs(p[2] - q[2]) < 3 and d < 2.2 then
				check(string.format("%s #%d and #%d overlap", name, i, j), false, d)
			end
		end
	end
end
for _, name in Scenario.Order do
	check("preset listed: " .. name, Scenario.Presets[name] ~= nil)
end
for i, z in Config.Map.Zones do
	check("zone teleport inside sandbox: " .. z[1], math.abs(z[2]) < HALF and math.abs(z[3]) < HALF)
end

fs.writeDir("tests/out")
fs.writeFile("tests/out/map.json", serde.encode("json", { parts = parts, spawns = Config.Map.Spawns, zones = Config.Map.Zones, presets = Scenario.Presets }))
print(string.format("map_spec: %d passed, %d failed  (%d anchored parts, %d loose props, %d preset dummy positions)", passed, failed, static, loose, presetCount))
process.exit(if failed > 0 then 1 else 0)
