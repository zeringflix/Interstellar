--!nonstrict
-- Prepared dummy arrangements. Each preset is a list of { x, y, z, yawDegrees, type? } ground points.
local DummyService = require(script.Parent.DummyService)

local ScenarioService = {}
ScenarioService.current = "Showcase"

local function line(n: number, x0: number, dx: number, y: number, z: number, yaw: number?, typeName: string?)
	local t = {}
	for i = 0, n - 1 do
		table.insert(t, { x0 + i * dx, y, z, yaw or 180, typeName })
	end
	return t
end

local function pins(cx: number, y: number, z: number, gap: number)
	local t = {}
	for row = 0, 3 do
		for i = 0, row do
			table.insert(t, { cx + (i - row / 2) * gap, y, z - row * gap * 0.9, 180 })
		end
	end
	return t
end

local function join(...)
	local out = {}
	for _, list in { ... } do
		for _, v in list do
			table.insert(out, v)
		end
	end
	return out
end

local function crowd(cx: number, cz: number, n: number)
	local t, rng = {}, Random.new(7) -- fixed seed: the same crowd every time, so tests are repeatable
	local types = { "Noob", "Noob", "Noob", "Crash", "Light", "Heavy" }
	local tries = 0
	while #t < n and tries < 400 do
		tries += 1
		local a, r = rng:NextNumber(0, math.pi * 2), 3 + rng:NextNumber(0, 1) ^ 0.5 * 13
		local x, z = cx + math.cos(a) * r, cz + math.sin(a) * r
		local free = true
		for _, o in t do -- keep at least 3.2 studs between dummies so nobody spawns inside a neighbour
			if (o[1] - x) ^ 2 + (o[3] - z) ^ 2 < 3.2 ^ 2 then
				free = false
				break
			end
		end
		if free then
			table.insert(t, { x, 0.1, z, rng:NextInteger(0, 359), types[rng:NextInteger(1, #types)] })
		end
	end
	return t
end

ScenarioService.Presets = {
	-- what the player sees on joining: something to hit in every zone
	Showcase = join(
		line(6, -15, 6, 0.1, -40),                 -- central row
		pins(-150, 0.1, -150, 4.5),                -- bowling lane in the dummy field
		line(4, 138, 8, 25.1, -200, 180, "Crash")  -- on the platform past the long ramp
	),
	Line = line(6, -15, 6, 0.1, -40),
	Bowling = pins(0, 0.1, -60, 4.5),
	Crowd = crowd(0, -62, 15),
	Tower = join(
		line(3, -206, 6, 9.1, -160, 180), line(3, -206, 6, 18.1, -160, 180), line(2, -203, 6, 27.1, -160, 180),
		line(4, -244, 6, 9.6, -150, 180, "Light")
	),
	Crossing = join(line(6, -342, 4.8, 0.5, 0, 90, "Crash"), line(3, -336, 6, 0.5, -14, 90)),
	Types = { { -12, 0.1, -40, 180, "Noob" }, { -6, 0.1, -40, 180, "Crash" }, { 0, 0.1, -40, 180, "Heavy" },
		{ 6, 0.1, -40, 180, "Light" }, { 12, 0.1, -40, 180, "Armored" } },
}
ScenarioService.Order = { "Line", "Bowling", "Crowd", "Tower", "Crossing", "Types", "Showcase" }

function ScenarioService.apply(name: string): boolean
	local preset = ScenarioService.Presets[name]
	if not preset then
		return false
	end
	ScenarioService.current = name
	DummyService.clear()
	for _, p in preset do
		DummyService.spawn(p[5] or "Noob", CFrame.new(p[1], p[2], p[3]) * CFrame.Angles(0, math.rad(p[4]), 0), "preset")
	end
	return true
end

return ScenarioService
