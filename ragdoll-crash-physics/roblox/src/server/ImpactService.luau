--!nonstrict
-- Server-side vehicle -> dummy collision detection.
-- Every physics step each moving vehicle sweeps an oriented box (its bounds, padded and stretched
-- along its velocity so fast vehicles cannot tunnel past a dummy between frames) against the
-- Dummies folder only. A hit is registered once per contact: the contact has to break for
-- CONTACT_BREAK_TIME before the same vehicle can damage the same dummy again, so a car resting
-- on or pushing a dummy never deals damage every frame.
local RunService = game:GetService("RunService")
local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.GameConfig)
local Specs = require(Shared.VehicleSpecs)
local DummyService = require(script.Parent.DummyService)

local ImpactService = {}
ImpactService.vehicleCrashListeners = {} :: { (Model, number, Vector3) -> () }

local contacts = {} :: { [Model]: { [number]: { seen: number, hit: number } } }
local lastVel = {} :: { [Model]: Vector3 }
local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Include

-- Closest point on an oriented box to a world point.
local function closestOnBox(cf: CFrame, size: Vector3, point: Vector3): Vector3
	local l = cf:PointToObjectSpace(point)
	local h = size / 2
	return cf:PointToWorldSpace(Vector3.new(math.clamp(l.X, -h.X, h.X), math.clamp(l.Y, -h.Y, h.Y), math.clamp(l.Z, -h.Z, h.Z)))
end

local function processVehicle(vehicle: Model, dt: number, now: number, batch)
	local root = vehicle.PrimaryPart
	if not root then
		return
	end
	local key = vehicle:GetAttribute("VehicleKey")
	local spec = Specs.Vehicles[key]
	local vel = root.AssemblyLinearVelocity
	local speed = vel.Magnitude
	-- sanity clamp: a client-owned vehicle can never report more than 1.6x its top speed
	local maxSpeed = spec.phys.maxSpeed * 1.6 + 30
	if speed > maxSpeed then
		vel = vel.Unit * maxSpeed
		speed = maxSpeed
	end

	-- Vehicle-vs-world crash: a big velocity change in one step.
	local prev = lastVel[vehicle]
	lastVel[vehicle] = vel
	if prev then
		local dv = (vel - prev).Magnitude
		if dv > 22 and prev.Magnitude > vel.Magnitude then
			for _, fn in ImpactService.vehicleCrashListeners do
				fn(vehicle, dv, root.Position)
			end
		end
	end

	local vc = contacts[vehicle]
	if not vc then
		vc = {}
		contacts[vehicle] = vc
	end
	if speed < 2 and next(vc) == nil then
		return
	end

	local pad = Config.Impact.QUERY_PADDING
	local sweep = speed * dt
	local dirLocal = if speed > 0.5 then root.CFrame:VectorToObjectSpace(vel.Unit) else Vector3.zero
	local size = root.Size + Vector3.one * pad * 2
		+ Vector3.new(math.abs(dirLocal.X), math.abs(dirLocal.Y), math.abs(dirLocal.Z)) * sweep
	local cf = root.CFrame + vel * dt * 0.5
	local found = workspace:GetPartBoundsInBox(cf, size, params)

	-- group overlapping parts by dummy, keeping the part nearest the vehicle's main body
	local body = vehicle:FindFirstChild(spec.parts[1].name) :: BasePart? or root
	local nearest = {} :: { [number]: { part: BasePart, dist: number } }
	for _, part in found do
		local model = part:FindFirstAncestorOfClass("Model")
		while model and model.Parent ~= DummyService.folder do
			model = model:FindFirstAncestorOfClass("Model")
		end
		local id = model and model:GetAttribute("DummyId")
		if id and part.Name ~= "HumanoidRootPart" then
			local dist = (part.Position - closestOnBox(body.CFrame, body.Size, part.Position)).Magnitude
			local cur = nearest[id]
			if not cur or dist < cur.dist then
				nearest[id] = { part = part, dist = dist }
			end
		end
	end

	for id, n in nearest do
		local d = DummyService.dummies[id]
		if not d then
			continue
		end
		local c = vc[id]
		local wasSeen = c and c.seen or -math.huge
		if not c then
			c = { seen = now, hit = -math.huge }
			vc[id] = c
		end
		c.seen = now
		local relVel = vel - n.part.AssemblyLinearVelocity
		local relSpeed = relVel.Magnitude
		local toDummy = n.part.Position - root.Position
		local closing = relVel:Dot(toDummy) > 0
		local fresh = (now - wasSeen) > Config.Impact.CONTACT_BREAK_TIME
		if closing and fresh and relSpeed >= Config.Impact.MIN_SPEED and (now - c.hit) >= Config.Impact.MIN_REHIT_TIME then
			c.hit = now
			local record = DummyService.hit(id, {
				part = n.part, relVelocity = relVel, relSpeed = relSpeed,
				vehicleImpact = spec.impact, source = spec.display, chain = false,
			})
			if record then
				record.vehicle = key
				table.insert(batch, record)
			end
		end
	end
	for id, c in vc do
		if now - c.seen > 3 then
			vc[id] = nil
		end
	end
end

function ImpactService.init(vehicleFolder: Folder)
	params.FilterDescendantsInstances = { DummyService.folder }
	vehicleFolder.ChildRemoved:Connect(function(v)
		contacts[v :: Model] = nil
		lastVel[v :: Model] = nil
	end)
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		local batch = {}
		for _, vehicle in vehicleFolder:GetChildren() do
			if vehicle:IsA("Model") then
				processVehicle(vehicle, dt, now, batch)
			end
		end
	end)
end

return ImpactService
