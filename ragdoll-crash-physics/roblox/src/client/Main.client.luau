--!nonstrict
-- Client bootstrap: builds the ScreenGui, starts every controller and wires server events to them.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local Settings = require(script.Parent.Settings)
local Audio = require(script.Parent.AudioController)
local Camera = require(script.Parent.CameraController)
local VehicleInput = require(script.Parent.VehicleInputController)
local Visuals = require(script.Parent.DummyVisuals)
local Effects = require(script.Parent.EffectsController)
local Replay = require(script.Parent.ReplayController)
local Feed = require(script.Parent.HitNotificationController)
local Inspect = require(script.Parent.DummyInspectionController)
local UI = require(script.Parent.UIController)

local screen = Instance.new("ScreenGui")
screen.Name = "RagdollCrashPhysics"
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.DisplayOrder = 5
screen.Parent = player:WaitForChild("PlayerGui")
if mobile then
	local scale = Instance.new("UIScale")
	scale.Scale = math.clamp(workspace.CurrentCamera.ViewportSize.Y / 420, 0.75, 1)
	scale.Parent = screen
end

Audio.init()
Camera.init()
VehicleInput.init()
Visuals.init()
Effects.init()
Replay.init()
Feed.init(screen, mobile)
Inspect.init(screen, mobile, remotes)
UI.init(screen, mobile, remotes)

VehicleInput.onHorn = function()
	if VehicleInput.current then
		Audio.horn(VehicleInput.current.model)
	end
end

remotes.Impact.OnClientEvent:Connect(function(records)
	if typeof(records) ~= "table" then
		return
	end
	Feed.show(records)
	Effects.onImpacts(records)
	Replay.addEvents(records)
end)
remotes.Report.OnClientEvent:Connect(function(report)
	UI.showReport(report)
end)
Replay.onEvent = function(record)
	Feed.show({ record }, true)
end

-- Selecting and grabbing dummies -------------------------------------------------------------
local dummies = workspace:WaitForChild("Dummies")
local grabbing = false
local grabDistance = 20
local pressPos: Vector2? = nil
local pressTime = 0
local lastPointer = Vector2.zero

local function dummyAt(screenPos: Vector2): (Model?, number)
	local cam = workspace.CurrentCamera
	local ray = cam:ViewportPointToRay(screenPos.X, screenPos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { dummies }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 600, params)
	if hit then
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		while model and model.Parent ~= dummies do
			model = model:FindFirstAncestorOfClass("Model")
		end
		return model, hit.Distance
	end
	return nil, 0
end

local function isPointer(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not isPointer(input) or Replay.playing then
		return
	end
	local pos = UserInputService:GetMouseLocation()
	if input.UserInputType == Enum.UserInputType.Touch then
		pos = Vector2.new(input.Position.X, input.Position.Y) + game:GetService("GuiService"):GetGuiInset()
	end
	pressPos, pressTime, lastPointer = pos, os.clock(), pos
	if UI.grabMode then
		local model, dist = dummyAt(pos)
		if model then
			grabbing = true
			grabDistance = math.clamp(dist, 8, 60)
			Inspect.select(model)
			remotes.Request:FireServer("Grab", model:GetAttribute("DummyId"))
		end
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		lastPointer = UserInputService:GetMouseLocation()
	elseif input.UserInputType == Enum.UserInputType.Touch then
		lastPointer = Vector2.new(input.Position.X, input.Position.Y) + game:GetService("GuiService"):GetGuiInset()
	elseif input.UserInputType == Enum.UserInputType.MouseWheel and grabbing then
		grabDistance = math.clamp(grabDistance + input.Position.Z * 3, 8, 60)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not isPointer(input) then
		return
	end
	if grabbing then
		grabbing = false
		remotes.Request:FireServer("Release")
	elseif pressPos and not UI.grabMode and os.clock() - pressTime < 0.4 and (lastPointer - pressPos).Magnitude < 12 then
		local model = dummyAt(pressPos)
		if model then
			Inspect.select(model)
		end
	end
	pressPos = nil
end)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	if not grabbing then
		return
	end
	acc += dt
	if acc >= 1 / 15 then
		acc = 0
		local ray = workspace.CurrentCamera:ViewportPointToRay(lastPointer.X, lastPointer.Y)
		remotes.Request:FireServer("GrabMove", ray.Origin + ray.Direction * grabDistance)
	end
end)
