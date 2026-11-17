--!nonstrict
-- Builds a vehicle Model from VehicleSpecs (the same data the Blender meshes are made from).
-- visualOnly = true gives an anchored, constraint-free copy for menu ViewportFrames.
--
-- Physics layout of a live vehicle:
--   Root          invisible box carrying ALL the mass (density derived from spec.mass)
--   spec parts    Massless, welded to Root; the ones flagged collide are the crash surfaces
--   WheelCollider frictionless balls welded to Root - the vehicle slides on these and the
--                 client applies drive / grip forces (VehicleInputController), so handling is
--                 fully tunable and stable at high speed
--   Wheel visuals / propellers / rotors: light non-colliding parts on motor hinges
--   Turret        (tank) separate assembly on a servo hinge
local Specs = require(script.Parent.VehicleSpecs)
local MeshInfo = require(script.Parent.VehicleMeshInfo)
local Cockpit = require(script.Parent.Cockpit)

local Builder = {}

local MATERIAL = {
	body = Enum.Material.SmoothPlastic, glass = Enum.Material.Glass, light = Enum.Material.Neon,
	neon = Enum.Material.Neon, dark = Enum.Material.SmoothPlastic, metal = Enum.Material.Metal,
	rubber = Enum.Material.Rubber,
}
local NO_FRICTION = PhysicalProperties.new(0.7, 0, 0, 100, 1)
local BODY_PROPS = PhysicalProperties.new(0.7, 0.2, 0.15, 1, 1)
local FEATHER = PhysicalProperties.new(0.01, 0, 0, 1, 1)

local function v3(t)
	return Vector3.new(t[1], t[2], t[3])
end

local function axisCFrame(axis: string): CFrame
	if axis == "y" then
		return CFrame.Angles(0, 0, math.rad(90))
	elseif axis == "z" then
		return CFrame.Angles(0, math.rad(90), 0)
	end
	return CFrame.identity
end

local function makePart(p): BasePart
	local part: BasePart
	local size, cf = v3(p.size), CFrame.new(v3(p.pos))
	if p.shape == "wedge" then
		part = Instance.new("WedgePart")
		if p.face == "back" then
			cf *= CFrame.Angles(0, math.rad(180), 0)
		end
	elseif p.shape == "cyl" then
		local c = Instance.new("Part")
		c.Shape = Enum.PartType.Cylinder
		part = c
		-- Roblox cylinders run along the part's X axis.
		if p.axis == "y" then
			size = Vector3.new(size.Y, size.X, size.Z)
		elseif p.axis == "z" then
			size = Vector3.new(size.Z, size.Y, size.X)
		end
		cf *= axisCFrame(p.axis)
	else
		part = Instance.new("Part")
	end
	part.Name = p.name
	part.Size = size
	part.CFrame = cf
	part.Color = Color3.fromHex(p.color)
	part.Material = MATERIAL[p.mat] or Enum.Material.SmoothPlastic
	part.Transparency = if p.mat == "glass" then 0.45 else 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = p.collide
	part.Massless = true
	part.CustomPhysicalProperties = if p.mat == "rubber" then NO_FRICTION else BODY_PROPS
	part.CollisionGroup = "Vehicle"
	part.CastShadow = math.min(size.X, size.Y, size.Z) > 0.4
	return part
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = a, b
	w.Parent = b
end

local function hinge(root: BasePart, part: BasePart, pivot: Vector3, axis: string, name: string): HingeConstraint
	local a0 = Instance.new("Attachment")
	a0.Name = name .. "A0"
	a0.CFrame = root.CFrame:ToObjectSpace(CFrame.new(pivot) * axisCFrame(axis))
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = name .. "A1"
	a1.CFrame = part.CFrame:ToObjectSpace(CFrame.new(pivot) * axisCFrame(axis))
	a1.Parent = part
	local h = Instance.new("HingeConstraint")
	h.Name = name
	h.Attachment0, h.Attachment1 = a0, a1
	h.ActuatorType = Enum.ActuatorType.Motor
	h.MotorMaxTorque = 1e5
	h.AngularVelocity = 0
	h.Parent = root
	return h
end

-- Optional detailed meshes -----------------------------------------------------------------
-- If the Blender models have been imported (ReplicatedStorage.VehicleMeshes.<Key>, see docs/MODELS.md),
-- they replace the look of the part-built vehicle. The parts stay as the collision / physics body.
-- Roblox re-centres every imported mesh on its bounding box, so VehicleMeshInfo (generated from the
-- .blend files) records where each mesh's centre belongs relative to the vehicle origin, and its size.
local function applyMeshes(model: Model, key: string, root: BasePart, parts, wheelParts, spec, visualOnly: boolean?): boolean
	local library = game:GetService("ReplicatedStorage"):FindFirstChild("VehicleMeshes")
	local source = library and library:FindFirstChild(key, true) -- works whether the import sits in the folder or IS the folder
	local info = MeshInfo[key]
	if not source or not info then
		return false
	end
	local used = 0
	for _, src in source:GetDescendants() do
		local entry = src:IsA("MeshPart") and info[src.Name]
		if entry then
			local mesh = src:Clone() :: MeshPart
			for _, child in mesh:GetChildren() do -- keep the imported textures (SurfaceAppearance), drop anything else
				if not child:IsA("SurfaceAppearance") then
					child:Destroy()
				end
			end
			local textured = mesh:FindFirstChildOfClass("SurfaceAppearance") ~= nil
			mesh.Size = Vector3.new(entry[4], entry[5], entry[6])
			mesh.CFrame = CFrame.new(entry[1], entry[2], entry[3])
			mesh.CanCollide, mesh.CanQuery, mesh.CanTouch = false, false, false
			mesh.Massless = true
			mesh.CollisionGroup = "VehicleDecor"
			mesh.Anchored = visualOnly == true
			local kind = string.match(src.Name, "_(%a+)%d*$") or "Body"
			if kind == "Glass" then
				mesh.Material, mesh.Transparency = Enum.Material.Glass, 0.45
			elseif kind == "Lights" then
				mesh.Material = Enum.Material.Neon
			else
				-- textured meshes: the SurfaceAppearance supplies colour, roughness, metalness and normals
				mesh.Material = Enum.Material.SmoothPlastic
			end
			if not textured then
				mesh.Color = Color3.new(1, 1, 1) -- untextured imports carry their colours as vertex colours
			end
			mesh.Parent = model
			if not visualOnly then
				local index = tonumber(string.match(src.Name, "%d+$"))
				local target: BasePart = root
				if kind == "Wheel" and index and wheelParts[index] then
					target = wheelParts[index]
				elseif kind == "Spin" and index and spec.spinners and spec.spinners[index] then
					target = parts[spec.spinners[index].parts[1]]
				elseif kind == "Turret" and spec.turret then
					target = parts[spec.turret[1]]
				end
				local pivot = kind == "Steer" and Cockpit.pivot(spec.cockpit and spec.cockpit.control)
				if pivot then
					-- the steering wheel / yoke / T-bar turns about its column: the driver's client sets
					-- SteerJoint.Transform from the steering input (FirstPersonController)
					local joint = Instance.new("Motor6D")
					joint.Name = "SteerJoint"
					joint.Part0, joint.Part1 = root, mesh
					joint.C0 = root.CFrame:ToObjectSpace(pivot)
					joint.C1 = mesh.CFrame:ToObjectSpace(pivot)
					joint.Parent = root
				else
					weld(target, mesh)
				end
			end
			used += 1
		end
	end
	if used == 0 then
		return false
	end
	for _, d in model:GetDescendants() do -- hide the blocky stand-ins, keep them as colliders
		if d:IsA("BasePart") and not d:IsA("MeshPart") then
			d.Transparency = 1
			d.CastShadow = false
		end
	end
	model:SetAttribute("DetailedMesh", true)
	return true
end

-- Hand grips for the first-person view: attachments on the steering mesh (so the hands turn with
-- it) or on the root when the vehicle has no detailed meshes.
local function addGrips(model: Model, root: BasePart, key: string, spec)
	local grips = Cockpit.grips(spec.cockpit and spec.cockpit.control)
	if not grips then
		return
	end
	local steer = model:FindFirstChild(key .. "_Steer")
	local holder: BasePart = if steer and steer:IsA("BasePart") and root:FindFirstChild("SteerJoint") then steer else root
	for name, p in { RCP_GripR = grips.right, RCP_GripL = grips.left } do
		local a = Instance.new("Attachment")
		a.Name = name
		a.CFrame = holder.CFrame:ToObjectSpace(CFrame.new(p))
		a.Parent = holder
	end
end

function Builder.getSpec(key: string)
	return Specs.Vehicles[key]
end

function Builder.build(key: string, visualOnly: boolean?): Model
	local spec = Specs.Vehicles[key]
	assert(spec, "unknown vehicle " .. tostring(key))
	local model = Instance.new("Model")
	model.Name = key

	local parts: { [string]: BasePart } = {}
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, p in spec.parts do
		local part = makePart(p)
		parts[p.name] = part
		if p.collide then
			local half = v3(p.size) / 2
			lo, hi = lo:Min(v3(p.pos) - half), hi:Max(v3(p.pos) + half)
		end
	end
	for _, w in spec.wheels do
		local r = Vector3.new(w.width / 2, w.radius, w.radius)
		lo, hi = lo:Min(v3(w.pos) - r), hi:Max(v3(w.pos) + r)
	end

	-- Root: carries the mass, defines the crash-query box.
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = (hi - lo):Max(Vector3.new(2, 1, 2))
	root.CFrame = CFrame.new((lo + hi) / 2)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CollisionGroup = "Vehicle"
	local volume = root.Size.X * root.Size.Y * root.Size.Z
	root.CustomPhysicalProperties = PhysicalProperties.new(math.clamp(spec.mass / volume, 0.01, 100), 0.2, 0.1, 1, 1)
	root.PivotOffset = root.CFrame:Inverse() -- model pivot = ground point under the vehicle centre
	root.Parent = model
	model.PrimaryPart = root

	local special: { [string]: boolean } = {}
	for _, sp in spec.spinners or {} do
		for _, n in sp.parts do
			special[n] = true
		end
	end
	for _, n in spec.turret or {} do
		special[n] = true
	end

	for name, part in parts do
		part.Parent = model
		if visualOnly then
			part.Anchored = true
		elseif not special[name] then
			weld(root, part)
		end
	end

	-- Wheels
	local wheelParts = {}
	for i, w in spec.wheels do
		local wheel = Instance.new("Part")
		wheel.Shape = Enum.PartType.Cylinder
		wheel.Name = "Wheel" .. i
		wheel.Size = Vector3.new(w.width, w.radius * 2, w.radius * 2)
		wheel.CFrame = CFrame.new(v3(w.pos))
		wheel.Color = Color3.fromHex("#17181b")
		wheel.Material = Enum.Material.Rubber
		wheel.CanCollide = false
		wheel.CollisionGroup = "VehicleDecor"
		wheel.CustomPhysicalProperties = FEATHER
		wheel.Parent = model
		wheelParts[i] = wheel
		local rim = Instance.new("Part")
		rim.Shape = Enum.PartType.Cylinder
		rim.Name = "Rim"
		rim.Size = Vector3.new(w.width + 0.08, w.radius * 1.15, w.radius * 1.15)
		rim.CFrame = wheel.CFrame
		rim.Color = Color3.fromHex("#c9cdd3")
		rim.Material = Enum.Material.Metal
		rim.CanCollide = false
		rim.Massless = true
		rim.Parent = wheel
		local spoke = Instance.new("Part") -- a bar across the rim so the spin is visible
		spoke.Name = "Spoke"
		spoke.Size = Vector3.new(w.width + 0.14, w.radius * 1.1, w.radius * 0.22)
		spoke.CFrame = wheel.CFrame
		spoke.Color = Color3.fromHex("#30333a")
		spoke.CanCollide = false
		spoke.Massless = true
		spoke.Parent = wheel
		if visualOnly then
			wheel.Anchored, rim.Anchored, spoke.Anchored = true, true, true
		else
			weld(wheel, rim)
			weld(wheel, spoke)
			hinge(root, wheel, v3(w.pos), "x", "WheelHinge" .. i)
			local ball = Instance.new("Part")
			ball.Shape = Enum.PartType.Ball
			ball.Name = "WheelCollider"
			ball.Size = Vector3.one * w.radius * 2
			ball.CFrame = wheel.CFrame
			ball.Transparency = 1
			ball.Massless = true
			ball.CustomPhysicalProperties = NO_FRICTION
			ball.CollisionGroup = "Vehicle"
			ball.CanQuery = false
			ball.Parent = model
			weld(root, ball)
		end
	end

	if visualOnly then
		applyMeshes(model, key, root, parts, wheelParts, spec, true)
		return model
	end

	-- Propellers / rotors
	for i, sp in spec.spinners or {} do
		local hub = parts[sp.parts[1]]
		for j, n in sp.parts do
			local part = parts[n]
			part.CanCollide = false
			part.CollisionGroup = "VehicleDecor"
			part.Massless = j > 1
			part.CustomPhysicalProperties = FEATHER
			if j > 1 then
				weld(hub, part)
			end
		end
		hinge(root, hub, v3(sp.pivot), sp.axis, "Spinner" .. i)
	end

	-- Tank turret on a servo
	if spec.turret then
		local ring = parts[spec.turret[1]]
		for j, n in spec.turret do
			local part = parts[n]
			part.CollisionGroup = "VehicleDecor"
			part.Massless = j > 1
			if j > 1 then
				weld(ring, part)
			end
		end
		local h = hinge(root, ring, v3(spec.turretPivot), "y", "TurretHinge")
		h.ActuatorType = Enum.ActuatorType.Servo
		h.ServoMaxTorque = 1e7
		h.AngularSpeed = 1.2
		h.TargetAngle = 0
	end

	-- Headlights
	for name, part in parts do
		if string.find(name, "Headlight") or name == "Headlamp" then
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Front
			light.Range = 60
			light.Brightness = 2
			light.Angle = 70
			light.Parent = part
		end
	end

	-- Driver seat (input only; the legacy VehicleSeat motors are disabled)
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.6, 2)
	seat.CFrame = CFrame.new(v3(spec.seat))
	seat.Transparency = 1
	seat.CanCollide = false
	seat.Massless = true
	seat.MaxSpeed, seat.Torque, seat.TurnSpeed = 0, 0, 0
	seat.HeadsUpDisplay = false
	seat.CollisionGroup = "VehicleDecor"
	seat.Parent = model
	weld(root, seat)

	-- Force handles the client drives.
	local center = Instance.new("Attachment")
	center.Name = "Center"
	center.Parent = root
	local drive = Instance.new("VectorForce")
	drive.Name = "Drive"
	drive.Attachment0 = center
	drive.RelativeTo = Enum.ActuatorRelativeTo.World
	drive.ApplyAtCenterOfMass = true
	drive.Force = Vector3.zero
	drive.Parent = root
	local steer = Instance.new("Torque")
	steer.Name = "Steer"
	steer.Attachment0 = center
	steer.RelativeTo = Enum.ActuatorRelativeTo.World
	steer.Torque = Vector3.zero
	steer.Parent = root

	applyMeshes(model, key, root, parts, wheelParts, spec, false)
	addGrips(model, root, key, spec)
	model:SetAttribute("VehicleKey", key)
	model:SetAttribute("Kind", spec.phys.kind)
	model:SetAttribute("Display", spec.display)
	model:SetAttribute("Impact", spec.impact)
	return model
end

return Builder
