-- Client half of the integration run (required by integration_spec.luau): boots the real client
-- scripts against the world the server half just built, feeds them real server payloads and
-- presses every button in the UI.
local R = _G.RCP
local world, Mock, check, step, player, gui = R.world, R.Mock, R.check, R.step, R.player, R.playerGui
local roblox = require("@lune/roblox")
local ws = world.workspace

local function frames(n: number)
	for _ = 1, n do
		Mock.clock += 1 / 60
		Mock.sync()
		world.heartbeat:Fire(1 / 60)
		world.renderStepped:Fire(1 / 60)
		for _, fn in world.renderSteps do
			fn(1 / 60)
		end
	end
end

Mock.fired = {}
world.require(world.client.Main)
local screen = gui:FindFirstChild("RagdollCrashPhysics")
check("client boots and builds the ScreenGui", screen ~= nil)
frames(5)
local function find(name: string)
	return screen:FindFirstChild(name, true)
end
for _, w in { "Shop", "Vehicles", "Sandbox", "Settings", "Dummy", "Report", "DamageBar", "DriveHud", "Inspection" } do
	check("UI element exists: " .. w, find(w) ~= nil)
end

-- every dummy got a face and a floating name tag
local faces, tags, total = 0, 0, 0
for _, d in ws.Dummies:GetChildren() do
	total += 1
	local head = d:FindFirstChild("Head")
	if head and (head:FindFirstChild("Face") or head:FindFirstChildOfClass("FaceControls")) then
		faces += 1
	end
	if head and head:FindFirstChild("StatusLabel") then
		tags += 1
	end
end
check("every dummy has an animated face", faces == total and total > 0, { faces, total })
check("every dummy has a name tag", tags == total, { tags, total })

-- a real hit through the real server -> the bottom damage bar
local Dummy = world.require(world.server.DummyService)
local remotes = world.replicated:FindFirstChild("Remotes")
local id = next(Dummy.dummies)
local d = Dummy.dummies[id]
Mock.fired = {}
Dummy.hit(id, { part = d.model.LeftLowerLeg, relVelocity = roblox.Vector3.new(0, 0, -80), relSpeed = 80, vehicleImpact = 1.4, source = "Sedan", chain = false })
step(0.05)
local payload = nil
for _, f in Mock.fired do
	if f.remote == "Impact" then
		payload = f.args[1]
	end
end
check("server sent the impact to clients", payload ~= nil and #payload >= 1)
if payload then
	remotes.Impact.OnClientEvent:Fire(payload)
	frames(3)
	local bar = find("DamageBar")
	local labels = {}
	for _, c in bar:GetChildren() do
		if c:IsA("TextLabel") then
			table.insert(labels, c.Text)
		end
	end
	check("damage bar is visible after a hit", bar.Visible == true)
	check("damage bar line 1 names the body part", labels[1] == "Left Knee", labels[1])
	local parts = string.split(labels[2] or "", " · ")
	check("damage bar line 2 has at most 3 facts", #parts >= 2 and #parts <= 3, labels[2])
	check("damage bar shows the injury first", parts[1] == payload[#payload].injury, labels[2])
	print("   damage bar example ->", labels[1], "|", labels[2])
	check("face expression follows the server state", d.model:GetAttribute("Face") ~= "Normal")
end
-- pile-up summary
local many = {}
for i = 1, 6 do
	table.insert(many, { id = 100 + i, display = "DUMMY", region = "TORSO", part = "Chest", severity = "HEAVY", damage = 30, health = 70, status = "DOWN",
		condition = if i < 4 then "Down" elseif i < 6 then "Knocked out" else "Dead", injury = "Broken ribs", source = "City Bus", chain = false, mph = 50,
		blood = 90, bleeding = true, dead = i == 6, position = roblox.Vector3.new(0, 3, 0) })
end
remotes.Impact.OnClientEvent:Fire(many)
frames(2)
local texts = {}
for _, c in find("DamageBar"):GetChildren() do
	if c:IsA("TextLabel") then
		table.insert(texts, c.Text)
	end
end
check("pile-up collapses into one summary", texts[1] == "6 dummies hit" and #string.split(texts[2], " · ") <= 3, texts)
print("   pile-up example    ->", texts[1], "|", texts[2])

-- other server events
remotes.Report.OnClientEvent:Fire({ vehicle = "Sedan", mph = 50, hit = 6, down = 3, unconscious = 2, dead = 1, chain = 1, props = 4, score = 2450 })
remotes.Explosion.OnClientEvent:Fire(roblox.Vector3.new(0, 2, 0), 1.2)
remotes.VehicleCrash.OnClientEvent:Fire(ws.Vehicles:GetChildren()[1], 95, roblox.Vector3.new(0, 2, 0))
remotes.Notice.OnClientEvent:Fire("hello")
frames(3)

-- driving HUD: sit the player in the vehicle
local car = ws.Vehicles:GetChildren()[1]
local seat = car:FindFirstChild("DriverSeat")
seat.Occupant = player.Character:FindFirstChildOfClass("Humanoid")
seat.ThrottleFloat = 1
frames(4)
local hud = find("DriveHud")
check("drive HUD appears with key binds while driving", hud.Visible == true)
local drive = car.PrimaryPart:FindFirstChild("Drive")
check("throttle produces a forward drive force", drive.Force.Magnitude > 0, drive.Force)
seat.Occupant = roblox.Instance.new("Humanoid") -- someone else: the player is no longer the driver
frames(3)
check("drive HUD hides after leaving the vehicle", hud.Visible == false)

-- press every button in the UI (twice, so toggles go both ways)
local pressed = 0
for round = 1, 2 do
	for _, b in screen:GetDescendants() do
		local alive, isButton = pcall(function()
			return b:IsA("TextButton") and b.Parent ~= nil
		end)
		if alive and isButton then -- (cards are rebuilt when a tab is pressed, so some are gone by now)
			b.Activated:Fire()
			pressed += 1
		end
	end
	frames(2)
end
for _, b in screen:GetDescendants() do -- the freshly rebuilt vehicle cards
	if b:IsA("TextLabel") and b.Name == "Caption" and b.Text == "SPAWN" then
		b.Parent.Activated:Fire()
		pressed += 1
		break
	end
end
check("pressed every button without a script error: " .. pressed, pressed > 120, pressed)
local sent = {}
for _, f in Mock.fired do
	if f.remote == "Request" then
		sent[f.args[1]] = true
	end
end
for _, action in { "SpawnVehicle", "SpawnDummies", "Preset", "ResetScene", "ResetDummies", "ResetVehicle", "Teleport", "Event", "LoadMap", "SetBody", "SetDummyLimit" } do
	check("UI sends request: " .. action, sent[action] == true)
end
-- replay ran (the PLAY button was pressed): ghosts are cleaned up and input is live again
local Replay = world.require(world.client.ReplayController)
local VehicleInput = world.require(world.client.VehicleInputController)
check("replay finished cleanly", Replay.playing == false and VehicleInput.suspended == false and world.camera:FindFirstChild("ReplayGhosts") == nil)
frames(30)
check("no script warnings on the client", (Mock.warnings or 0) == 0, Mock.warnings)
