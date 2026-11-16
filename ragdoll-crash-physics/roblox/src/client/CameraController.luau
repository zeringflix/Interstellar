--!nonstrict
-- Camera modes (Follow Vehicle / Follow Dummy / Free) and a short, decaying impact shake.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Settings = require(script.Parent.Settings)

local Camera = {}
Camera.mode = "Vehicle"
local player = Players.LocalPlayer
local shake = 0
local freePart: Part? = nil
local rng = Random.new()

local function controls()
	local ok, module = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
	end)
	return if ok then module else nil
end

local function humanoid(): Humanoid?
	return player.Character and player.Character:FindFirstChildOfClass("Humanoid")
end

function Camera.shake(amount: number)
	if Settings.get("CameraShake") then
		shake = math.min(1.2, math.max(shake, amount))
	end
end

-- Push the default camera out so a whole bus / plane fits on screen.
function Camera.frameVehicle(model: Model)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local d = math.clamp(root.Size.Magnitude * 0.9 + 12, 22, 110)
	player.CameraMaxZoomDistance = 260
	player.CameraMinZoomDistance = d
	task.delay(0.1, function()
		player.CameraMinZoomDistance = 0.5
	end)
end

function Camera.setMode(mode: string, target: Instance?)
	local cam = workspace.CurrentCamera
	if freePart then
		freePart:Destroy()
		freePart = nil
		local c = controls()
		if c then
			c:Enable()
		end
	end
	Camera.mode = mode
	cam.CameraType = Enum.CameraType.Custom
	if mode == "Dummy" and target then
		cam.CameraSubject = target
	elseif mode == "Free" then
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.Transparency = true, false, false, 1
		p.Size = Vector3.one
		p.CFrame = CFrame.new(cam.Focus.Position)
		p.Parent = cam
		freePart = p
		cam.CameraSubject = p
		local c = controls()
		if c then
			c:Disable()
		end
	else
		Camera.mode = "Vehicle"
		cam.CameraSubject = humanoid()
	end
end

function Camera.init()
	player.CameraMaxZoomDistance = 260
	player.CharacterAdded:Connect(function()
		task.wait(0.2)
		if Camera.mode == "Vehicle" then
			Camera.setMode("Vehicle")
		end
	end)
	RunService:BindToRenderStep("RCP_Camera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local cam = workspace.CurrentCamera
		if freePart then
			local m = Vector3.zero
			local function key(k: Enum.KeyCode): number
				return if UserInputService:IsKeyDown(k) then 1 else 0
			end
			m += cam.CFrame.LookVector * (key(Enum.KeyCode.W) - key(Enum.KeyCode.S))
			m += cam.CFrame.RightVector * (key(Enum.KeyCode.D) - key(Enum.KeyCode.A))
			m += Vector3.yAxis * (key(Enum.KeyCode.E) - key(Enum.KeyCode.Q))
			local speed = if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then 160 else 60
			freePart.CFrame += m * speed * dt
		elseif Camera.mode == "Dummy" and (not cam.CameraSubject or not cam.CameraSubject.Parent) then
			Camera.setMode("Vehicle")
		end
		if shake > 0.01 then
			local a = shake * 0.035
			cam.CFrame *= CFrame.Angles(rng:NextNumber(-a, a), rng:NextNumber(-a, a), rng:NextNumber(-a, a) * 0.5)
			shake *= math.exp(-dt * 7) -- gone in about half a second
		end
	end)
end

return Camera
