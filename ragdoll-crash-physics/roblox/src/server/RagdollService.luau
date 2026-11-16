--!nonstrict
-- Swaps a dummy between animated (Motor6D) and physical (BallSocket / Hinge) joints.
local RagdollService = {}

local UPPER_BODY = { Neck = true, LeftShoulder = true, LeftElbow = true, LeftWrist = true,
	RightShoulder = true, RightElbow = true, RightWrist = true }

local function eachJoint(model: Model, fn: (Motor6D, Constraint, BasePart) -> ())
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Name ~= "Root" then
			local c = (d.Parent :: Instance):FindFirstChild(d.Name .. "Ragdoll")
			if c then
				fn(d, c :: Constraint, d.Parent :: BasePart)
			end
		end
	end
end

local function serverOwn(model: Model)
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and not p.Anchored then
			pcall(function()
				p:SetNetworkOwner(nil)
			end)
		end
	end
end
RagdollService.serverOwn = serverOwn

function RagdollService.isRagdolled(model: Model): boolean
	return model:GetAttribute("Ragdoll") == true
end

-- Full ragdoll: every limb becomes its own physics body.
function RagdollService.enable(model: Model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	model:SetAttribute("Ragdoll", true)
	model:SetAttribute("Stagger", false)
	hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	hum.PlatformStand = true
	hum.AutoRotate = false
	hum:ChangeState(Enum.HumanoidStateType.Physics)
	eachJoint(model, function(motor, constraint, part)
		constraint.Enabled = true
		motor.Enabled = false
		part.CanCollide = true
	end)
	local lower = model:FindFirstChild("LowerTorso") :: BasePart?
	if lower then
		lower.CanCollide = true
	end
	serverOwn(model)
end

-- Stagger: arms and head go physical while the legs keep balancing.
function RagdollService.stagger(model: Model)
	if RagdollService.isRagdolled(model) then
		return
	end
	model:SetAttribute("Stagger", true)
	eachJoint(model, function(motor, constraint)
		if UPPER_BODY[motor.Name] then
			constraint.Enabled = true
			motor.Enabled = false
		end
	end)
end

function RagdollService.endStagger(model: Model)
	if model:GetAttribute("Stagger") ~= true or RagdollService.isRagdolled(model) then
		return
	end
	model:SetAttribute("Stagger", false)
	eachJoint(model, function(motor, constraint)
		motor.Enabled = true
		constraint.Enabled = false
	end)
end

-- Stand the dummy back up where its torso currently lies. Returns false if no ground was found.
function RagdollService.disable(model: Model, hipHeight: number): boolean
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local lower = model:FindFirstChild("LowerTorso") :: BasePart?
	if not (hum and root and lower) then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local origin = lower.Position + Vector3.new(0, 3, 0)
	local hit = workspace:Raycast(origin, Vector3.new(0, -40, 0), params)
	if not hit then
		return false
	end
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.1 then
		look = Vector3.new(0, 0, -1)
	end
	local pos = hit.Position + Vector3.new(0, hipHeight + root.Size.Y / 2 + 0.2, 0)
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			p.AssemblyLinearVelocity, p.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		end
	end
	root.CFrame = CFrame.lookAt(pos, pos + look.Unit)
	eachJoint(model, function(motor, constraint)
		motor.Enabled = true
		constraint.Enabled = false
	end)
	model:SetAttribute("Ragdoll", false)
	model:SetAttribute("Stagger", false)
	hum.PlatformStand = false
	hum.AutoRotate = true
	hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
	hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	serverOwn(model)
	return true
end

return RagdollService
