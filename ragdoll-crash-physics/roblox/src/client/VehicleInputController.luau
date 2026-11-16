--!nonstrict
-- Drives every vehicle the player owns. The server gives the player network ownership, so the
-- forces applied here are simulated locally with zero input lag; the collisions with dummies are
-- still real physical contacts and all damage is decided on the server.
--
-- Controls (also shown on the HUD):
--   Cars / tank / train   W S throttle + brake/reverse, A D steer        (thumbstick on mobile / gamepad)
--   Plane                 W S engine power up / down (stays where you leave it), A D bank + turn,
--                         E pull up, Q nose down                          (UP / DOWN touch buttons)
--   Helicopter            W S forward / back, A D turn, E climb, Q descend
--   H horn, jump to exit
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local Shared = game.ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Specs = require(Shared.VehicleSpecs)

local Controller = {}
Controller.current = nil :: any -- { model, spec, key, kind, speedMph, throttle, grounded, braking }
Controller.onHorn = nil :: (() -> ())?
Controller.suspended = false -- true while a replay is on screen: inputs are ignored

local player = Players.LocalPlayer
local folder: Folder
local pitchUp, pitchDown = false, false
local planeThrottle = {} :: { [Model]: number }
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function clampMag(v: Vector3, max: number): Vector3
	local m = v.Magnitude
	return if m > max then v * (max / m) else v
end

local function bindAir(on: boolean)
	if on then
		ContextActionService:BindAction("RCP_PitchUp", function(_, state)
			pitchUp = state == Enum.UserInputState.Begin
			return Enum.ContextActionResult.Sink
		end, true, Enum.KeyCode.E, Enum.KeyCode.ButtonR1)
		ContextActionService:BindAction("RCP_PitchDown", function(_, state)
			pitchDown = state == Enum.UserInputState.Begin
			return Enum.ContextActionResult.Sink
		end, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
		ContextActionService:SetTitle("RCP_PitchUp", "UP")
		ContextActionService:SetTitle("RCP_PitchDown", "DOWN")
		ContextActionService:SetPosition("RCP_PitchUp", UDim2.new(1, -150, 1, -230))
		ContextActionService:SetPosition("RCP_PitchDown", UDim2.new(1, -230, 1, -160))
	else
		ContextActionService:UnbindAction("RCP_PitchUp")
		ContextActionService:UnbindAction("RCP_PitchDown")
		pitchUp, pitchDown = false, false
	end
end

local function grounded(root: BasePart): boolean
	local up = root.CFrame.UpVector
	return workspace:Raycast(root.Position, -up * (root.Size.Y / 2 + 1.4), rayParams) ~= nil
end

local function stepVehicle(model: Model, dt: number, humanoid: Humanoid?)
	local root = model.PrimaryPart
	local drive = root and root:FindFirstChild("Drive") :: VectorForce?
	local steer = root and root:FindFirstChild("Steer") :: Torque?
	local seat = model:FindFirstChild("DriverSeat") :: VehicleSeat?
	if not (root and drive and steer and seat) then
		return
	end
	local key = model:GetAttribute("VehicleKey")
	local spec = Specs.Vehicles[key]
	local phys = spec.phys
	local kind = phys.kind
	local driving = humanoid ~= nil and seat.Occupant == humanoid
	local live = driving and not Controller.suspended
	local throttle = if live then (if seat.ThrottleFloat ~= 0 then seat.ThrottleFloat else seat.Throttle) else 0
	local steerIn = if live then (if seat.SteerFloat ~= 0 then seat.SteerFloat else seat.Steer) else 0

	local cf = root.CFrame
	local look, right, up = cf.LookVector, cf.RightVector, cf.UpVector
	local v = root.AssemblyLinearVelocity
	local w = root.AssemblyAngularVelocity
	local fwd, lat = v:Dot(look), v:Dot(right)
	local mass = root.AssemblyMass
	local g = workspace.Gravity
	local sz = root.Size
	local Iyaw = mass * (sz.X ^ 2 + sz.Z ^ 2) / 12
	local onGround = grounded(root)
	local force, torque = Vector3.zero, Vector3.zero
	local braking = false
	local power = math.abs(throttle)

	if kind == "car" or kind == "tank" or kind == "sled" or kind == "train" then
		if onGround or kind == "train" then
			local a
			if throttle ~= 0 then
				local target = if throttle > 0 then throttle * phys.maxSpeed else throttle * phys.maxSpeed * 0.35
				a = math.clamp((target - fwd) * 3, -phys.accel * 1.8, phys.accel)
				braking = throttle < 0 and fwd > 3
			else
				a = math.clamp(-fwd * 0.8, -phys.accel * 0.5, phys.accel * 0.5) -- engine braking / parked
			end
			force += look * a * mass
			if kind ~= "train" then
				local grip = phys.grip or 1
				force += right * math.clamp(-lat * 8, -70 * grip, 70 * grip) * mass
				local speedFactor = if kind == "tank" then 1 else math.clamp(fwd / 20, -1, 1)
				local fade = 1 - 0.35 * math.clamp(math.abs(fwd) / phys.maxSpeed, 0, 1)
				local targetYaw = -steerIn * phys.turn * speedFactor * fade
				torque = up * math.clamp((targetYaw - w:Dot(up)) * 10, -14, 14) * Iyaw
			end
		end
	elseif kind == "plane" then
		local t = planeThrottle[model] or 0
		if driving then
			t = math.clamp(t + throttle * dt * 0.7, 0, 1)
		else
			t = math.max(0, t - dt * 0.5)
		end
		planeThrottle[model] = t
		power = t
		local speedF = math.clamp(fwd / phys.takeoff, 0, 1)
		if fwd < phys.maxSpeed then
			force += look * phys.accel * mass * t
		end
		force += Vector3.yAxis * mass * g * math.min(1, speedF ^ 2) * math.max(0, up.Y) -- lift
		force += -(v - look * fwd) * mass * 2.2 * speedF -- wings make the velocity follow the nose
		force += -v * mass * 0.1 -- drag
		if onGround and speedF < 0.55 then
			-- taxiing: steer like a car, brake when the engine is idle
			force += right * math.clamp(-lat * 6, -50, 50) * mass
			if t < 0.05 then
				force += look * math.clamp(-fwd * 1.2, -20, 20) * mass
			end
			local targetYaw = -steerIn * 0.9 * math.clamp(fwd / 15, -1, 1)
			torque = up * math.clamp((targetYaw - w:Dot(up)) * 8, -10, 10) * Iyaw
		else
			local auth = math.clamp(speedF, 0.15, 1) -- controls go soft in a stall
			local pitchIn = (if pitchUp then 1 else 0) - (if pitchDown then 1 else 0)
			local bank = -math.asin(math.clamp(right.Y, -1, 1)) -- + = right wing down
			local wantBank = steerIn * math.rad(55)
			local want = Vector3.new(
				pitchIn * phys.pitch * auth,
				-bank * phys.turn * 1.3 * auth,
				-math.clamp((wantBank - bank) * 2.5, -phys.roll, phys.roll) * auth
			)
			local wl = cf:VectorToObjectSpace(w)
			local I = Vector3.new(sz.Y ^ 2 + sz.Z ^ 2, sz.X ^ 2 + sz.Z ^ 2, sz.X ^ 2 + sz.Y ^ 2) * (mass / 12)
			torque = cf:VectorToWorldSpace((want - wl) * I * 6)
		end
	elseif kind == "heli" then
		if driving then
			local climbIn = (if pitchUp then 1 else 0) - (if pitchDown then 1 else 0)
			force += Vector3.yAxis * mass * (g + math.clamp((climbIn * phys.climb - v.Y) * 3, -60, 60))
			local flat = look * Vector3.new(1, 0, 1)
			flat = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)
			local hv = v * Vector3.new(1, 0, 1)
			force += clampMag((flat * throttle * phys.maxSpeed - hv) * 1.5, phys.accel) * mass
			local wantUp = (Vector3.yAxis + flat * throttle * 0.28).Unit
			local targetYaw = -steerIn * phys.turn
			torque = (up:Cross(wantUp) * 30 - (w - Vector3.yAxis * w.Y) * 6 + Vector3.yAxis * (targetYaw - w.Y) * 8) * Iyaw
			power = 0.6 + 0.4 * math.max(math.abs(throttle), math.abs(climbIn))
		else
			power = 0
		end
	end

	drive.Force = force
	steer.Torque = torque

	-- visuals: wheels, propellers, turret
	for i, wh in spec.wheels do
		local h = root:FindFirstChild("WheelHinge" .. i) :: HingeConstraint?
		if h then
			h.AngularVelocity = math.clamp(-fwd / wh.radius, -120, 120)
		end
	end
	for i in spec.spinners or {} do
		local h = root:FindFirstChild("Spinner" .. i) :: HingeConstraint?
		if h then
			h.AngularVelocity = if power > 0.02 or (driving and kind ~= "plane") then 10 + power * 34 else 0
		end
	end
	if spec.turret and driving then
		local h = root:FindFirstChild("TurretHinge") :: HingeConstraint?
		local cam = workspace.CurrentCamera
		if h and cam then
			local camLook = cam.CFrame.LookVector
			h.TargetAngle = math.deg(math.atan2(-camLook:Dot(right), camLook:Dot(look)))
		end
	end

	if driving then
		local c = Controller.current
		if not c or c.model ~= model then
			c = { model = model, spec = spec, key = key, kind = kind }
			Controller.current = c
			bindAir(kind == "plane" or kind == "heli")
		end
		c.speedMph = v.Magnitude * Config.STUDS_PER_SEC_TO_MPH
		c.speed = v.Magnitude
		c.throttle = power
		c.grounded = onGround
		c.braking = braking
		c.slip = math.abs(lat)
		c.altitude = root.Position.Y
	end
	model:SetAttribute("ClientPower", math.floor(power * 20 + 0.5) / 20) -- local only; read by AudioController
end

function Controller.init()
	folder = workspace:WaitForChild("Vehicles") :: Folder
	ContextActionService:BindAction("RCP_Horn", function(_, state)
		if state == Enum.UserInputState.Begin and Controller.current and Controller.onHorn then
			Controller.onHorn()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.H, Enum.KeyCode.ButtonY)
	folder.ChildRemoved:Connect(function(m)
		planeThrottle[m :: Model] = nil
	end)
	RunService.Heartbeat:Connect(function(dt)
		local char = player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		rayParams.FilterDescendantsInstances = { folder, char, workspace:FindFirstChild("Dummies") } :: { any }
		local stillDriving = false
		for _, model in folder:GetChildren() do
			if model:IsA("Model") then
				stepVehicle(model, dt, humanoid)
				if Controller.current and Controller.current.model == model then
					local seat = model:FindFirstChild("DriverSeat") :: VehicleSeat?
					stillDriving = seat ~= nil and humanoid ~= nil and seat.Occupant == humanoid
				end
			end
		end
		if Controller.current and not stillDriving then
			Controller.current = nil
			bindAir(false)
		end
	end)
end

return Controller
