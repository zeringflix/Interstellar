--!nonstrict
-- Builds the blocky articulated dummy. Proportions are classic 2x2x1-torso Roblox (R6 silhouette)
-- but with 15 R15-named parts, so it has real elbows / knees for ragdolling and still plays the
-- stock R15 animations. Every joint gets a Motor6D (standing) AND a disabled physics constraint
-- (ragdoll); RagdollService swaps between them.
local Config = require(game.ReplicatedStorage.Shared.GameConfig)

local DummyRig = {}

-- name, size, centre (relative to torso centre), colour slot
local PARTS = {
	{ "LowerTorso", Vector3.new(2, 0.8, 1), Vector3.new(0, -0.6, 0), "torso" },
	{ "UpperTorso", Vector3.new(2, 1.2, 1), Vector3.new(0, 0.4, 0), "torso" },
	{ "Head", Vector3.new(1.25, 1.25, 1.25), Vector3.new(0, 1.625, 0), "head" },
	{ "LeftUpperArm", Vector3.new(1, 1, 1), Vector3.new(-1.5, 0.5, 0), "arms" },
	{ "LeftLowerArm", Vector3.new(1, 0.7, 1), Vector3.new(-1.5, -0.35, 0), "arms" },
	{ "LeftHand", Vector3.new(1, 0.3, 1), Vector3.new(-1.5, -0.85, 0), "arms" },
	{ "RightUpperArm", Vector3.new(1, 1, 1), Vector3.new(1.5, 0.5, 0), "arms" },
	{ "RightLowerArm", Vector3.new(1, 0.7, 1), Vector3.new(1.5, -0.35, 0), "arms" },
	{ "RightHand", Vector3.new(1, 0.3, 1), Vector3.new(1.5, -0.85, 0), "arms" },
	{ "LeftUpperLeg", Vector3.new(1, 1, 1), Vector3.new(-0.5, -1.5, 0), "legs" },
	{ "LeftLowerLeg", Vector3.new(1, 0.7, 1), Vector3.new(-0.5, -2.35, 0), "legs" },
	{ "LeftFoot", Vector3.new(1, 0.3, 1), Vector3.new(-0.5, -2.85, 0), "legs" },
	{ "RightUpperLeg", Vector3.new(1, 1, 1), Vector3.new(0.5, -1.5, 0), "legs" },
	{ "RightLowerLeg", Vector3.new(1, 0.7, 1), Vector3.new(0.5, -2.35, 0), "legs" },
	{ "RightFoot", Vector3.new(1, 0.3, 1), Vector3.new(0.5, -2.85, 0), "legs" },
}

local DOWN = CFrame.Angles(0, 0, math.rad(-90)) -- attachment X axis pointing down the limb
local UP = CFrame.Angles(0, 0, math.rad(90))

-- motor name, part0, part1, joint position, constraint kind, limits
local JOINTS = {
	{ "Root", "HumanoidRootPart", "LowerTorso", Vector3.new(0, -0.6, 0) },
	{ "Waist", "LowerTorso", "UpperTorso", Vector3.new(0, -0.2, 0), "ball", UP, 25, 20 },
	{ "Neck", "UpperTorso", "Head", Vector3.new(0, 1, 0), "ball", UP, 45, 50 },
	{ "LeftShoulder", "UpperTorso", "LeftUpperArm", Vector3.new(-1.25, 0.8, 0), "ball", DOWN, 110, 60 },
	{ "LeftElbow", "LeftUpperArm", "LeftLowerArm", Vector3.new(-1.5, 0, 0), "hinge", 0, 140 },
	{ "LeftWrist", "LeftLowerArm", "LeftHand", Vector3.new(-1.5, -0.7, 0), "ball", DOWN, 30, 20 },
	{ "RightShoulder", "UpperTorso", "RightUpperArm", Vector3.new(1.25, 0.8, 0), "ball", DOWN, 110, 60 },
	{ "RightElbow", "RightUpperArm", "RightLowerArm", Vector3.new(1.5, 0, 0), "hinge", 0, 140 },
	{ "RightWrist", "RightLowerArm", "RightHand", Vector3.new(1.5, -0.7, 0), "ball", DOWN, 30, 20 },
	{ "LeftHip", "LowerTorso", "LeftUpperLeg", Vector3.new(-0.5, -1, 0), "ball", DOWN, 75, 30 },
	{ "LeftKnee", "LeftUpperLeg", "LeftLowerLeg", Vector3.new(-0.5, -2, 0), "hinge", -140, 0 },
	{ "LeftAnkle", "LeftLowerLeg", "LeftFoot", Vector3.new(-0.5, -2.7, 0), "ball", DOWN, 30, 20 },
	{ "RightHip", "LowerTorso", "RightUpperLeg", Vector3.new(0.5, -1, 0), "ball", DOWN, 75, 30 },
	{ "RightKnee", "RightUpperLeg", "RightLowerLeg", Vector3.new(0.5, -2, 0), "hinge", -140, 0 },
	{ "RightAnkle", "RightLowerLeg", "RightFoot", Vector3.new(0.5, -2.7, 0), "ball", DOWN, 30, 20 },
}
local EXTRA_NO_COLLIDE = {
	{ "LeftUpperLeg", "RightUpperLeg" }, { "LeftUpperArm", "LowerTorso" }, { "RightUpperArm", "LowerTorso" },
	{ "LeftUpperLeg", "UpperTorso" }, { "RightUpperLeg", "UpperTorso" }, { "Head", "LowerTorso" },
	{ "LeftLowerArm", "UpperTorso" }, { "RightLowerArm", "UpperTorso" },
}

DummyRig.HIP_HEIGHT = 2 -- root bottom (-1) to sole (-3), before scale

local function noCollide(a: BasePart, b: BasePart)
	local n = Instance.new("NoCollisionConstraint")
	n.Part0, n.Part1 = a, b
	n.Parent = a
end

local function buildBlocky(typeName: string, id: number): Model
	local t = Config.DummyTypes[typeName] or Config.DummyTypes.Noob
	local s = t.scale
	local model = Instance.new("Model")
	model.Name = "Dummy" .. id
	local props = PhysicalProperties.new(t.density, 0.5, 0.15, 1, 1)
	local parts: { [string]: BasePart } = {}

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1) * s
	root.Transparency = 1
	root.CanCollide = false
	root.RootPriority = 127
	root.CustomPhysicalProperties = props
	root.CollisionGroup = "Dummy"
	root.Parent = model
	parts.HumanoidRootPart = root

	for _, def in PARTS do
		local p = Instance.new("Part")
		p.Name = def[1]
		p.Size = def[2] * s
		p.CFrame = CFrame.new(def[3] * s)
		p.Color = Color3.fromHex(t.colors[def[4]])
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.CustomPhysicalProperties = props
		p.CollisionGroup = "Dummy"
		p.Parent = model
		parts[def[1]] = p
	end

	for _, j in JOINTS do
		local p0, p1 = parts[j[2]], parts[j[3]]
		local world = CFrame.new(j[4] * s)
		local m = Instance.new("Motor6D")
		m.Name = j[1]
		m.Part0, m.Part1 = p0, p1
		m.C0, m.C1 = p0.CFrame:ToObjectSpace(world), p1.CFrame:ToObjectSpace(world)
		m.Parent = p1
		if j[5] then
			local orient = if j[5] == "ball" then j[6] else CFrame.identity
			local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
			a0.Name, a1.Name = j[1] .. "RigAttachment0", j[1] .. "RigAttachment1"
			a0.CFrame = p0.CFrame:ToObjectSpace(world * orient)
			a1.CFrame = p1.CFrame:ToObjectSpace(world * orient)
			a0.Parent, a1.Parent = p0, p1
			local c
			if j[5] == "ball" then
				local b = Instance.new("BallSocketConstraint")
				b.LimitsEnabled, b.UpperAngle = true, j[7]
				b.TwistLimitsEnabled, b.TwistLowerAngle, b.TwistUpperAngle = true, -j[8], j[8]
				b.MaxFrictionTorque = 6 * s -- a little joint stiffness so limbs don't flop like string
				c = b
			else
				local h = Instance.new("HingeConstraint")
				h.LimitsEnabled, h.LowerAngle, h.UpperAngle = true, j[6], j[7]
				c = h
			end
			c.Name = j[1] .. "Ragdoll"
			c.Attachment0, c.Attachment1 = a0, a1
			c.Enabled = false
			c.Parent = p1
			noCollide(p0, p1)
		end
	end
	for _, pair in EXTRA_NO_COLLIDE do
		noCollide(parts[pair[1]], parts[pair[2]])
	end

	if t.markings then -- crash-test target discs
		for _, spec in { { "UpperTorso", Enum.NormalId.Front }, { "Head", Enum.NormalId.Left }, { "Head", Enum.NormalId.Right } } do
			local g = Instance.new("SurfaceGui")
			g.Name = "TestMark"
			g.Face = spec[2]
			g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			g.PixelsPerStud = 40
			g.Parent = parts[spec[1]]
			local outer = Instance.new("Frame")
			outer.AnchorPoint, outer.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
			outer.Size = UDim2.fromOffset(30, 30)
			outer.BackgroundColor3 = Color3.fromHex("#ffd21a")
			outer.Parent = g
			Instance.new("UICorner", outer).CornerRadius = UDim.new(1, 0)
			for q = 0, 1 do
				local quad = Instance.new("Frame")
				quad.Size = UDim2.fromScale(0.5, 0.5)
				quad.Position = UDim2.fromScale(q * 0.5, q * 0.5)
				quad.BackgroundColor3 = Color3.fromHex("#111111")
				quad.BorderSizePixel = 0
				quad.Parent = outer
			end
		end
	end
	if t.armorKit then
		for _, a in { { "UpperTorso", Vector3.new(2.25, 1.3, 1.25), "#2b2e31" }, { "Head", Vector3.new(1.4, 0.75, 1.4), "#2b2e31", Vector3.new(0, 0.38, 0) } } do
			local host = parts[a[1]]
			local plate = Instance.new("Part")
			plate.Name = "Armor"
			plate.Size = a[2] * s
			plate.CFrame = host.CFrame * CFrame.new((a[4] or Vector3.zero) * s)
			plate.Color = Color3.fromHex(a[3])
			plate.Material = Enum.Material.Metal
			plate.Massless, plate.CanCollide = true, false
			plate.CollisionGroup = "Dummy"
			plate.Parent = host
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = host, plate
			w.Parent = plate
		end
	end

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.AutomaticScalingEnabled = false
	hum.HipHeight = DummyRig.HIP_HEIGHT * s
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.MaxHealth, hum.Health = 1e6, 1e6 -- real health lives in DamageService
	hum.WalkSpeed = 8
	hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	hum.Parent = model
	Instance.new("Animator", hum)

	model.PrimaryPart = root
	model:SetAttribute("DummyId", id)
	model:SetAttribute("DummyType", typeName)
	model:SetAttribute("Display", t.display)
	model:SetAttribute("Scale", s)
	model:SetAttribute("Body", "Blocky")
	return model
end
DummyRig.buildBlocky = buildBlocky

-- ---------------------------------------------------------------------------------------------
-- Catalog-avatar dummies (default): a real R15 rig with the Robloxian 2.0 (or Man) body and the
-- animatable Man head, all grey. Built once per dummy type, then cloned for every spawn.
-- Ragdoll joints are made from the rig's own <Joint>RigAttachment pairs.
local BALL = { -- UpperAngle (cone about the sideways axis), twist lower / upper (swing forward / back)
	Neck = { 40, -40, 40 }, Waist = { 20, -30, 20 }, Shoulder = { 80, -160, 60 }, Hip = { 40, -95, 40 },
	Wrist = { 20, -30, 30 }, Ankle = { 20, -30, 30 },
}
local HINGE = { Elbow = { 0, 140 }, Knee = { -140, 0 } }

local function addRagdollJoints(model: Model, stiffness: number)
	for _, m in model:GetDescendants() do
		if m:IsA("Motor6D") and m.Name ~= "Root" and m.Part0 and m.Part1 then
			local p0, p1 = m.Part0 :: BasePart, m.Part1 :: BasePart
			local a0 = p0:FindFirstChild(m.Name .. "RigAttachment")
			local a1 = p1:FindFirstChild(m.Name .. "RigAttachment")
			if a0 and a1 and a0:IsA("Attachment") and a1:IsA("Attachment") then
				local kind = string.gsub(string.gsub(m.Name, "^Left", ""), "^Right", "")
				local c: Constraint
				if HINGE[kind] then
					local h = Instance.new("HingeConstraint")
					h.LimitsEnabled, h.LowerAngle, h.UpperAngle = true, HINGE[kind][1], HINGE[kind][2]
					c = h
				else
					local lim = BALL[kind] or BALL.Wrist
					local b = Instance.new("BallSocketConstraint")
					b.LimitsEnabled, b.UpperAngle = true, lim[1]
					b.TwistLimitsEnabled, b.TwistLowerAngle, b.TwistUpperAngle = true, lim[2], lim[3]
					b.MaxFrictionTorque = stiffness
					c = b
				end
				c.Name = m.Name .. "Ragdoll"
				c.Attachment0, c.Attachment1 = a0, a1
				c.Enabled = false
				c.Parent = p1
				noCollide(p0, p1)
			end
		end
	end
	for _, pair in EXTRA_NO_COLLIDE do
		local a, b = model:FindFirstChild(pair[1]), model:FindFirstChild(pair[2])
		if a and b then
			noCollide(a :: BasePart, b :: BasePart)
		end
	end
end

local function buildAvatar(typeName: string): Model?
	local t = Config.DummyTypes[typeName] or Config.DummyTypes.Noob
	local body = Config.Bodies[Config.DummyBody]
	if not body or Config.DummyBody == "Blocky" then
		return nil
	end
	local ok, model = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		desc.Torso, desc.RightArm, desc.LeftArm = body.Torso, body.RightArm, body.LeftArm
		desc.LeftLeg, desc.RightLeg = body.LeftLeg, body.RightLeg
		desc.Head = Config.MAN_DYNAMIC_HEAD
		local grey = Color3.fromHex(t.colors.head)
		desc.HeadColor, desc.TorsoColor = grey, grey
		desc.LeftArmColor, desc.RightArmColor, desc.LeftLegColor, desc.RightLegColor = grey, grey, grey, grey
		desc.HeightScale, desc.WidthScale, desc.DepthScale, desc.HeadScale = t.scale, t.scale, t.scale, t.scale
		return game:GetService("Players"):CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model or not model:FindFirstChild("UpperTorso") or not model:FindFirstChild("HumanoidRootPart") then
		return nil
	end
	local props = PhysicalProperties.new(t.density, 0.5, 0.15, 1, 1)
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Accessory") or d:IsA("Clothing") or d:IsA("ShirtGraphic") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CustomPhysicalProperties = props
			d.CollisionGroup = "Dummy"
			d.Color = Color3.fromHex(t.colors.head)
			d.Anchored = false
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	root.RootPriority = 127
	model.PrimaryPart = root
	addRagdollJoints(model, 6 * t.scale)
	if t.armorKit then
		local torso = model:FindFirstChild("UpperTorso") :: BasePart
		local plate = Instance.new("Part")
		plate.Name = "Armor"
		plate.Size = torso.Size + Vector3.new(0.25, 0.1, 0.25)
		plate.CFrame = torso.CFrame
		plate.Color = Color3.fromHex("#2b2e31")
		plate.Material = Enum.Material.Metal
		plate.Massless, plate.CanCollide = true, false
		plate.CollisionGroup = "Dummy"
		plate.Parent = torso
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = torso, plate
		w.Parent = plate
	end
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.MaxHealth, hum.Health = 1e6, 1e6
	hum.WalkSpeed = 8
	hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	if not hum:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = hum
	end
	model:SetAttribute("Scale", t.scale)
	model:SetAttribute("Body", Config.DummyBody)
	model:SetAttribute("DummyType", typeName)
	model:SetAttribute("Display", t.display)
	return model
end

local templates = {} :: { [string]: Model | boolean }

-- Yields the first time a type is requested (the avatar is fetched from Roblox); instant afterwards.
function DummyRig.build(typeName: string, id: number): Model
	local key = Config.DummyBody .. ":" .. typeName
	if templates[key] == nil then
		templates[key] = buildAvatar(typeName) or false
	end
	local template = templates[key]
	if template then
		local model = (template :: Model):Clone()
		model.Name = "Dummy" .. id
		model:SetAttribute("DummyId", id)
		return model
	end
	return buildBlocky(typeName, id) -- offline / asset failure fallback: the part-built blocky dummy
end

return DummyRig
