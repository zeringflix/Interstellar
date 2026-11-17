--!nonstrict
-- First-person driving view: the player's own point of view from the driver's seat.
--
--   * Toggle with the VIEW button on the driving HUD, V on a keyboard or R3 on a gamepad. The choice
--     is remembered (Settings.FirstPerson) and comes back every time the player gets in a vehicle.
--   * The camera sits at the cockpit eye point of the vehicle (VehicleSpecs.cockpit.eye, researched
--     per vehicle), looks out of the windscreen, and can look around: hold right mouse and move,
--     drag on the right of a touch screen, or use the right stick. It drifts back to straight ahead.
--   * The avatar is fitted to the seat locally so its head lands at the eye point (Roblox avatars sit
--     much taller than a person, and every avatar is different), its head and hats are hidden, the
--     rest of the body stays visible, and on R15 avatars IKControls put both hands on the steering
--     wheel / yoke / handlebars / levers, following the wheel as it turns.
--   * The steering control turns with the steering input (SteerJoint, built by VehicleBuilder).
--   * Glass is made almost clear for the driver (LocalTransparencyModifier) so the windscreen and
--     windows are easy to see through; other players see the normal tinted glass.
--   * Everything is client-side and undone on exit: leaving the seat, dying, a replay or a different
--     camera mode all switch back to the normal camera.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Shared = game.ReplicatedStorage:WaitForChild("Shared")
local Specs = require(Shared.VehicleSpecs)
local Cockpit = require(Shared.Cockpit)
local Settings = require(script.Parent.Settings)
local Camera = require(script.Parent.CameraController)

local FP = {}
FP.active = false
FP.onChanged = nil :: ((boolean) -> ())?
FP.GLASS_CLEAR = 0.8 -- 0.45 glass + 0.55 * 0.8 = 89% see-through for the driver
FP.FOV = 74

local player = Players.LocalPlayer
local state = nil :: any
local yaw, pitch, lastLook = 0, 0, 0
local mouseLook = false
local touchLook: InputObject? = nil
local lastVel: Vector3? = nil
local headOffset = Vector3.zero
local MAX_YAW, MIN_PITCH, MAX_PITCH = math.rad(125), math.rad(-60), math.rad(40)

function FP.enabled(): boolean
	return Settings.get("FirstPerson") == true
end

local function now(): number
	return os.clock()
end

local function driverSeat(): (Model?, VehicleSeat?, Humanoid?)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if seat and seat.Name == "DriverSeat" and seat:IsA("VehicleSeat") and (seat :: VehicleSeat).Occupant == hum and seat.Parent and seat.Parent:IsA("Model") then
		return seat.Parent :: Model, seat :: VehicleSeat, hum
	end
	return nil, nil, hum
end

local function replayPlaying(): boolean
	local ok, Replay = pcall(require, script.Parent.ReplayController)
	return ok and Replay.playing == true
end

-- parts of the avatar the driver must not see: the head, the face, hats and hair
local function onHead(part: Instance, head: BasePart?): boolean
	if part == head then
		return true
	end
	local acc = part:FindFirstAncestorOfClass("Accessory")
	if acc then
		local handle = acc:FindFirstChild("Handle")
		local w = handle and handle:FindFirstChildWhichIsA("JointInstance")
		if w and (w.Part0 == head or w.Part1 == head) then
			return true
		end
		local att = handle and handle:FindFirstChildOfClass("Attachment")
		return att ~= nil and head ~= nil and head:FindFirstChild(att.Name) ~= nil
	end
	return false
end

local function setBody(char: Model?, visible: boolean)
	if not char then
		return
	end
	local head = char:FindFirstChild("Head")
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			local hide = visible and onHead(if d:IsA("Decal") then d.Parent else d, head)
			d.LocalTransparencyModifier = if hide then 1 else 0
		end
	end
end

local function setGlass(model: Model, clear: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Material == Enum.Material.Glass then
			d.LocalTransparencyModifier = if clear then FP.GLASS_CLEAR else 0
		end
	end
end

-- Seat the avatar so its head is at the eye height (local only: other players are unaffected).
local function fitToSeat()
	if not state or state.fitted then
		return
	end
	local char = player.Character
	local head = char and char:FindFirstChild("Head") :: BasePart?
	local weld = state.seat:FindFirstChild("SeatWeld") :: Weld?
	if not (head and weld and weld:IsA("Weld")) then
		return
	end
	local local_ = state.model:GetPivot():PointToObjectSpace(head.Position)
	local dy = math.clamp(local_.Y - state.eye.Y, -2.5, 2.5)
	state.weld, state.weldC0 = weld, weld.C0
	weld.C0 = weld.C0 * CFrame.new(0, -dy, 0)
	state.fitted = true
end

local function addHands(char: Model)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end
	for side, grip in { Right = "RCP_GripR", Left = "RCP_GripL" } do
		local target = state.model:FindFirstChild(grip, true)
		local upper = char:FindFirstChild(side .. "UpperArm")
		local hand = char:FindFirstChild(side .. "Hand")
		if target and upper and hand then
			local ik = Instance.new("IKControl")
			ik.Name = "RCP_Hand" .. side
			ik.Type = Enum.IKControlType.Position
			ik.ChainRoot = upper
			ik.EndEffector = hand
			ik.Target = target
			ik.Weight = 1
			ik.Priority = 1
			ik.Parent = hum
			table.insert(state.iks, ik)
		end
	end
end

local function enter(model: Model, seat: VehicleSeat)
	local key = model:GetAttribute("VehicleKey")
	local spec = key and Specs.Vehicles[key]
	local eye = spec and Cockpit.eye(spec)
	if not eye then
		return
	end
	local cam = workspace.CurrentCamera
	state = { model = model, seat = seat, spec = spec, eye = eye, iks = {}, fov = cam.FieldOfView, enteredAt = now(),
		joint = model.PrimaryPart and model.PrimaryPart:FindFirstChild("SteerJoint"), steer = 0,
		lock = Cockpit.LOCK[spec.cockpit.control.type] or 0, basePitch = math.rad((spec.cockpit.pitch or -8) * 0.6) }
	yaw, pitch, lastVel, headOffset = 0, 0, nil, Vector3.zero
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = FP.FOV
	setGlass(model, true)
	if player.Character then
		addHands(player.Character)
	end
	FP.active = true
	if FP.onChanged then
		FP.onChanged(true)
	end
end

local function exit()
	if not state then
		return
	end
	local s = state
	state = nil
	FP.active = false
	for _, ik in s.iks do
		ik:Destroy()
	end
	if s.weld and s.weldC0 and s.weld.Parent then
		s.weld.C0 = s.weldC0
	end
	if s.joint and s.joint.Parent then
		s.joint.Transform = CFrame.identity
	end
	if s.model.Parent then
		setGlass(s.model, false)
	end
	setBody(player.Character, false)
	local cam = workspace.CurrentCamera
	cam.FieldOfView = s.fov
	cam.CameraType = Enum.CameraType.Custom
	if Camera.mode == "Vehicle" then
		Camera.setMode("Vehicle")
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	mouseLook, touchLook = false, nil
	if FP.onChanged then
		FP.onChanged(false)
	end
end

function FP.setEnabled(on: boolean)
	Settings.set("FirstPerson", on == true)
	if not on then
		exit()
	end
end

function FP.toggle()
	FP.setEnabled(not FP.enabled())
end

-- the camera: eye point in the vehicle, free look, a little head movement from acceleration
local function update(dt: number)
	local model, seat = driverSeat()
	local want = FP.enabled() and model ~= nil and Camera.mode == "Vehicle" and not replayPlaying()
	if state and (not want or state.model ~= model or not state.model.Parent) then
		exit()
	end
	if not want then
		return
	end
	if not state then
		enter(model :: Model, seat :: VehicleSeat)
		if not state then
			return
		end
	end
	if not state.fitted and now() - state.enteredAt > 0.25 then
		fitToSeat()
	end
	-- look input: gamepad right stick here, mouse and touch through the input events below
	for _, inp in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if inp.KeyCode == Enum.KeyCode.Thumbstick2 and inp.Position.Magnitude > 0.18 then
			yaw -= inp.Position.X * 2.4 * dt
			pitch += inp.Position.Y * 1.8 * dt
			lastLook = now()
		end
	end
	if now() - lastLook > 1.5 and not mouseLook and not touchLook then
		local k = 1 - math.exp(-3 * dt)
		yaw -= yaw * k
		pitch -= pitch * k
	end
	yaw = math.clamp(yaw, -MAX_YAW, MAX_YAW)
	pitch = math.clamp(pitch, MIN_PITCH, MAX_PITCH)
	-- head sways a little against acceleration (braking leans you forward, bumps lift you)
	local root = state.model.PrimaryPart
	local pivot = state.model:GetPivot()
	if root then
		local v = root.AssemblyLinearVelocity
		if lastVel and dt > 0 then
			local a = pivot:VectorToObjectSpace((v - lastVel) / dt)
			local target = Vector3.new(-a.X, -a.Y, -a.Z) * 0.0025
			if target.Magnitude > 0.18 then
				target = target.Unit * 0.18
			end
			headOffset = headOffset:Lerp(target, math.min(1, dt * 6))
		end
		lastVel = v
	end
	local cam = workspace.CurrentCamera
	if cam.CameraType ~= Enum.CameraType.Scriptable then -- something reset the camera mid-drive: take it back
		cam.CameraType = Enum.CameraType.Scriptable
	end
	local eyeCF = pivot * CFrame.new(state.eye + headOffset) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(state.basePitch + pitch, 0, 0)
	cam.CFrame = eyeCF
	cam.Focus = eyeCF
	-- the steering control follows the steering input
	if state.joint and state.joint.Parent and state.lock > 0 then
		local s = state.seat.SteerFloat
		if s == 0 then
			s = state.seat.Steer
		end
		state.steer += (math.clamp(s, -1, 1) - state.steer) * math.min(1, dt * 8)
		state.joint.Transform = CFrame.Angles(0, 0, -state.steer * state.lock)
	end
end

function FP.init()
	if Settings.values.FirstPerson == nil then
		Settings.values.FirstPerson = false
	end
	ContextActionService:BindAction("RCP_FirstPerson", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			local model = driverSeat()
			if model then
				FP.toggle()
				return Enum.ContextActionResult.Sink
			end
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.V, Enum.KeyCode.ButtonR3)
	RunService:BindToRenderStep("RCP_FirstPerson", Enum.RenderPriority.Camera.Value, update)
	-- after the default camera scripts: keep the head hidden and the body visible
	RunService:BindToRenderStep("RCP_FirstPersonBody", Enum.RenderPriority.Camera.Value + 2, function()
		if state then
			setBody(player.Character, true)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not state then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			mouseLook = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		elseif input.UserInputType == Enum.UserInputType.Touch and not processed then
			local vp = workspace.CurrentCamera.ViewportSize
			if input.Position.X > vp.X * 0.4 then
				touchLook = input
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			mouseLook = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		elseif input == touchLook then
			touchLook = nil
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not state then
			return
		end
		if (input.UserInputType == Enum.UserInputType.MouseMovement and mouseLook) or input == touchLook then
			local k = if input.UserInputType == Enum.UserInputType.Touch then 0.006 else 0.0045
			yaw -= input.Delta.X * k
			pitch -= input.Delta.Y * k
			lastLook = now()
		end
	end)
	player.CharacterAdded:Connect(function()
		exit()
	end)
end

return FP
