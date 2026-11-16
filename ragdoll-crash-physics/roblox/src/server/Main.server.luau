--!nonstrict
-- Server bootstrap for RAGDOLL CRASH PHYSICS. Owns all authoritative state; the client can only
-- *request* things through one validated, rate-limited remote.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Specs = require(Shared.VehicleSpecs)

local MapService = require(script.Parent.MapService)
local DummyService = require(script.Parent.DummyService)
local RagdollService = require(script.Parent.RagdollService)
local ImpactService = require(script.Parent.ImpactService)
local VehicleService = require(script.Parent.VehicleService)
local CrashReportService = require(script.Parent.CrashReportService)
local ScenarioService = require(script.Parent.ScenarioService)
local SceneResetService = require(script.Parent.SceneResetService)

-- Collision groups ---------------------------------------------------------
for _, g in { "Player", "Dummy", "Vehicle", "VehicleDecor", "Prop" } do
	PhysicsService:RegisterCollisionGroup(g)
end
PhysicsService:CollisionGroupSetCollidable("Vehicle", "VehicleDecor", false)
PhysicsService:CollisionGroupSetCollidable("VehicleDecor", "VehicleDecor", false)
PhysicsService:CollisionGroupSetCollidable("VehicleDecor", "Player", false)

-- Remotes ---------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
for _, name in { "Request", "Impact", "Report", "VehicleCrash", "Notice" } do
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
end
remotes.Parent = ReplicatedStorage

-- World ---------------------------------------------------------------------------
local map, railAnchor = MapService.build()
local vehicles = Instance.new("Folder")
vehicles.Name = "Vehicles"
vehicles.Parent = workspace

DummyService.init()
VehicleService.init(vehicles, railAnchor)
ImpactService.init(vehicles)
CrashReportService.init(remotes)
CrashReportService.countDisturbedProps = SceneResetService.countDisturbed
SceneResetService.capture(map.Props)
ScenarioService.apply("Showcase")

table.insert(ImpactService.vehicleCrashListeners, function(vehicle: Model, dv: number, pos: Vector3)
	VehicleService.onCrash(vehicle, dv)
	remotes.VehicleCrash:FireAllClients(vehicle, dv, pos)
end)

-- Players ---------------------------------------------------------------------------
local starterGiven = false
local grabs = {} :: { [Player]: { id: number, align: AlignPosition, target: Attachment, att: Attachment } }

local function releaseGrab(player: Player)
	local g = grabs[player]
	if g then
		grabs[player] = nil
		g.align:Destroy()
		g.target:Destroy()
		g.att:Destroy()
	end
end

local function onCharacter(char: Model)
	do
		for _, p in char:GetDescendants() do
			if p:IsA("BasePart") then
				p.CollisionGroup = "Player"
			end
		end
		char.DescendantAdded:Connect(function(p)
			if p:IsA("BasePart") then
				p.CollisionGroup = "Player"
			end
		end)
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
	if not starterGiven then
		starterGiven = true
		-- the bright yellow sports car, parked facing the first row of dummies
		VehicleService.spawn(player, "SportsCar", false)
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end
Players.PlayerRemoving:Connect(function(player)
	releaseGrab(player)
end)

-- Stations on the plaza: walk onto a pad prompt to spawn that vehicle.
for _, st in MapService.stations do
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Spawn"
	prompt.ObjectText = Specs.Vehicles[st.key].display
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = st.part
	prompt.Triggered:Connect(function(player)
		VehicleService.spawn(player, st.key, true)
	end)
end

-- Requests ---------------------------------------------------------------------------
local lastCall = {} :: { [Player]: { [string]: number } }
local COOLDOWN = { SpawnVehicle = 0.6, SpawnDummies = 0.4, Preset = 0.6, ResetScene = 0.6, ResetDummies = 0.5, GrabMove = 0 }

local function playerPos(player: Player): Vector3?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

local function notice(player: Player, text: string)
	remotes.Notice:FireClient(player, text)
end

local handlers = {}

function handlers.SpawnVehicle(player, key)
	if typeof(key) == "string" and Specs.Vehicles[key] then
		VehicleService.spawn(player, key, true)
	end
end

function handlers.ResetVehicle(player)
	local v = VehicleService.current(player)
	if v then
		VehicleService.reset(v)
	end
end

function handlers.DeleteVehicle(player)
	local v = VehicleService.current(player)
	if v then
		VehicleService.delete(v)
	end
end

function handlers.SpawnDummies(player, n, typeName)
	if typeof(n) ~= "number" or n ~= n then
		return
	end
	n = math.clamp(math.floor(n), 1, 10)
	typeName = if typeof(typeName) == "string" and Config.DummyTypes[typeName] then typeName else "Noob"
	local origin = playerPos(player)
	if not origin then
		return
	end
	local look = (player.Character :: Model):GetPivot().LookVector * Vector3.new(1, 0, 1)
	look = if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, -1)
	local right = Vector3.new(-look.Z, 0, look.X)
	local made = 0
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { DummyService.folder, vehicles, player.Character }
	for i = 1, n do
		local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
		local p = origin + look * (14 + row * 5) + right * (col - (math.min(n, 5) - 1) / 2) * 5
		local hit = workspace:Raycast(p + Vector3.new(0, 30, 0), Vector3.new(0, -120, 0), params)
		if hit then
			local cf = CFrame.lookAt(hit.Position, hit.Position - look)
			if DummyService.spawn(typeName, cf, "manual") then
				made += 1
			end
		end
	end
	if made < n then
		notice(player, string.format("Dummy limit reached (%d)", DummyService.limit))
	end
end

function handlers.Preset(player, name)
	if typeof(name) == "string" and ScenarioService.apply(name) then
		local p = ScenarioService.Presets[name][1]
		remotes.Notice:FireClient(player, "Preset: " .. name, Vector3.new(p[1], p[2], p[3]))
	end
end

function handlers.ResetDummies()
	DummyService.resetAll()
end

function handlers.ResetScene(player)
	releaseGrab(player)
	DummyService.resetAll()
	SceneResetService.resetProps()
	local v = VehicleService.current(player)
	if v then
		VehicleService.reset(v)
	end
end

function handlers.DummyAction(player, id, action)
	if typeof(id) ~= "number" or not DummyService.dummies[id] then
		return
	end
	if action == "Revive" then
		DummyService.revive(id)
	elseif action == "Reset" then
		DummyService.reset(id)
	elseif action == "Delete" then
		DummyService.remove(id)
	end
end

function handlers.Teleport(player, index)
	local zone = typeof(index) == "number" and Config.Map.Zones[index]
	local char = player.Character
	if zone and char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum and hum.SeatPart then
			hum.Sit = false
			task.wait(0.1)
		end
		char:PivotTo(CFrame.new(zone[2], 5, zone[3]))
	end
end

function handlers.SetDummyLimit(player, mode, mobile)
	if typeof(mode) == "string" and Config.DUMMY_LIMITS[mode] then
		DummyService.setLimit(mode, mobile == true)
	end
end

-- Grab tool: the server holds the dummy with a spring-like AlignPosition towards a point the
-- client steers, capped in range and force so nothing gets teleported through walls.
function handlers.Grab(player, id)
	releaseGrab(player)
	local d = typeof(id) == "number" and DummyService.dummies[id]
	local origin = playerPos(player)
	if not d or not origin or (d.torso.Position - origin).Magnitude > 90 then
		return
	end
	DummyService.knockDown(d, 1.5)
	if not d.state.ragdolled then
		RagdollService.enable(d.model)
		d.state.ragdolled = true
	end
	local att = Instance.new("Attachment")
	att.Parent = d.torso
	local target = Instance.new("Attachment")
	target.WorldPosition = d.torso.Position
	target.Parent = workspace.Terrain
	local align = Instance.new("AlignPosition")
	align.Attachment0, align.Attachment1 = att, target
	align.MaxForce = d.torso.AssemblyMass * 900 + 4000
	align.MaxVelocity = 70
	align.Responsiveness = 22
	align.Parent = d.torso
	grabs[player] = { id = id, align = align, target = target, att = att }
end

function handlers.GrabMove(player, pos)
	local g = grabs[player]
	local origin = playerPos(player)
	if not g or not origin or typeof(pos) ~= "Vector3" or pos ~= pos then
		return
	end
	local offset = pos - origin
	if offset.Magnitude > 70 then
		offset = offset.Unit * 70
	end
	local p = origin + offset
	g.target.WorldPosition = Vector3.new(p.X, math.clamp(p.Y, 1.5, 90), p.Z)
	local d = DummyService.dummies[g.id]
	if d then
		d.state.downUntil = os.clock() + 1.5 -- stays limp while held
		d.skipVelCheckUntil = os.clock() + 0.4
	else
		releaseGrab(player)
	end
end

function handlers.Release(player)
	releaseGrab(player)
end

remotes.Request.OnServerEvent:Connect(function(player, action, ...)
	if typeof(action) ~= "string" or not handlers[action] then
		return
	end
	local now = os.clock()
	local calls = lastCall[player]
	if not calls then
		calls = {}
		lastCall[player] = calls
	end
	local cd = COOLDOWN[action] or 0.15
	if calls[action] and now - calls[action] < cd then
		return
	end
	calls[action] = now
	local ok, err = pcall(handlers[action], player, ...)
	if not ok then
		warn("[RCP] request " .. action .. " failed: " .. tostring(err))
	end
end)
Players.PlayerRemoving:Connect(function(player)
	lastCall[player] = nil
end)
