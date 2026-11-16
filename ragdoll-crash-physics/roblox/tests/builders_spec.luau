-- lune run tests/builders_spec.luau
-- Runs the real VehicleBuilder / DummyRig code against Lune's implementation of the Roblox
-- Instance API (property names and types are validated against the Roblox reflection database),
-- then checks structural invariants. This cannot test physics - only Roblox Studio can.
local process = require("@lune/process")
local Harness = require("./harness")
local roblox = require("@lune/roblox")
-- engine-side methods Lune does not implement: stub them so the build code can run
roblox.implementMethod("Humanoid", "SetStateEnabled", function() end)
local h = Harness.new(true)
local Specs = h.require("shared/VehicleSpecs")
local Builder = h.require("shared/VehicleBuilder")
local Config = h.require("shared/GameConfig")
local DummyRig = h.require("server/DummyRig")
local AudioIds = h.require("shared/AudioIds")

local passed, failed = 0, 0
local function check(name: string, cond: any, detail: any?)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL", name, detail)
	end
end

for _, key in Specs.Order do
	local spec = Specs.Vehicles[key]
	local ok, model = pcall(Builder.build, key, false)
	check(key .. " builds", ok, model)
	if ok then
		local root = model.PrimaryPart
		check(key .. " has root", root and root.Name == "Root")
		check(key .. " has seat + force handles", model:FindFirstChild("DriverSeat") and root:FindFirstChild("Drive") and root:FindFirstChild("Steer"))
		local mass = root.Size.X * root.Size.Y * root.Size.Z * root.CustomPhysicalProperties.Density
		check(key .. " mass ~ spec", math.abs(mass - spec.mass) / spec.mass < 0.02, { mass, spec.mass })
		local colliders, wheels, lowest = 0, 0, math.huge
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				if d.CanCollide then
					colliders += 1
					lowest = math.min(lowest, d.CFrame.Position.Y - (if d.Name == "WheelCollider" then d.Size.Y / 2 else d.Size.Y / 2))
				end
				if d.Name == "WheelCollider" then
					wheels += 1
				end
				if d ~= root and d.Name ~= "WheelCollider" and not string.match(d.Name, "^Wheel%d") and d.Parent == model
					and not d.Massless and d.Name ~= (spec.turret and spec.turret[1] or "") and not string.match(d.Name, "PropHub") and d.Name ~= "RotorHub" and d.Name ~= "TailRotorHub" then
					check(key .. " stray mass on " .. d.Name, false)
				end
			end
		end
		check(key .. " wheel colliders", wheels == #spec.wheels, wheels)
		check(key .. " has crash surfaces", colliders >= 3, colliders)
		check(key .. " rests on the ground (lowest collider within 0.6 of y=0)", math.abs(lowest) < 0.6, lowest)
		check(key .. " seat inside bounds", math.abs(spec.seat[1]) < root.Size.X / 2 and math.abs(spec.seat[3] - root.CFrame.Position.Z) < root.Size.Z / 2)
		check(key .. " spawn zone exists", Config.Map.Spawns[spec.spawn] ~= nil, spec.spawn)
		check(key .. " audio mapped", AudioIds.Vehicle[key] and AudioIds.Engine[AudioIds.Vehicle[key].engine])
	end
	local okV, visual = pcall(Builder.build, key, true)
	check(key .. " preview builds", okV, visual)
	if okV then
		local loose = 0
		for _, d in visual:GetDescendants() do
			if d:IsA("BasePart") and not d.Anchored and d.Name ~= "Root" then
				loose += 1
			end
			check(key .. " preview has no constraints", not d:IsA("Constraint") and not d:IsA("VehicleSeat"))
		end
		check(key .. " preview fully anchored", loose == 0, loose)
	end
end

for typeName, t in Config.DummyTypes do
	local ok, model = pcall(DummyRig.build, typeName, 1)
	check(typeName .. " rig builds", ok, model)
	if ok then
		local motors, ragdollJoints, parts = 0, 0, 0
		local lowest, highest = math.huge, -math.huge
		for _, d in model:GetDescendants() do
			if d:IsA("Motor6D") then
				motors += 1
				local p0, p1 = d.Part0, d.Part1
				-- joint must coincide in world space when the rig is in its bind pose
				local w0, w1 = p0.CFrame * d.C0, p1.CFrame * d.C1
				check(typeName .. " joint aligned " .. d.Name, (w0.Position - w1.Position).Magnitude < 1e-3)
			elseif d:IsA("BallSocketConstraint") or d:IsA("HingeConstraint") then
				ragdollJoints += 1
				check(typeName .. " ragdoll joint starts disabled", d.Enabled == false)
				local a0, a1 = d.Attachment0, d.Attachment1
				check(typeName .. " attachments coincide " .. d.Name, ((a0.Parent.CFrame * a0.CFrame).Position - (a1.Parent.CFrame * a1.CFrame).Position).Magnitude < 1e-3)
			elseif d:IsA("BasePart") and d.Parent == model and d.Name ~= "HumanoidRootPart" then
				parts += 1
				lowest = math.min(lowest, d.CFrame.Position.Y - d.Size.Y / 2)
				highest = math.max(highest, d.CFrame.Position.Y + d.Size.Y / 2)
			end
		end
		check(typeName .. " 15 body parts", parts == 15, parts)
		check(typeName .. " 15 motors", motors == 15, motors)
		check(typeName .. " 14 ragdoll joints", ragdollJoints == 14, ragdollJoints)
		local hum = model:FindFirstChildOfClass("Humanoid")
		check(typeName .. " humanoid", hum ~= nil)
		check(typeName .. " feet at hip height below root", math.abs(-lowest - (hum.HipHeight + model.HumanoidRootPart.Size.Y / 2)) < 1e-3, lowest)
		check(typeName .. " height " .. string.format("%.2f", highest - lowest), math.abs((highest - lowest) - 5.25 * t.scale) < 0.01)
		check(typeName .. " classic colours", model.Head.Color == roblox.Color3.fromHex(t.colors.head) and model.UpperTorso.Color == roblox.Color3.fromHex(t.colors.torso))
	end
end

-- imported, textured meshes: VehicleBuilder must keep each mesh's SurfaceAppearance and hide the stand-in parts
do
	local dm = roblox.Instance.new("DataModel")
	local rs = dm:GetService("ReplicatedStorage")
	local lib = roblox.Instance.new("Folder")
	lib.Name = "VehicleMeshes"
	lib.Parent = rs
	local imported = roblox.Instance.new("Model") -- what Import 3D produces: a model holding the per-vehicle models
	imported.Name = "AllVehicles"
	imported.Parent = lib
	local sedan = roblox.Instance.new("Model")
	sedan.Name = "Sedan"
	sedan.Parent = imported
	for _, n in { "Sedan_Body", "Sedan_Trim", "Sedan_Glass", "Sedan_Wheel1" } do
		local mp = roblox.Instance.new("MeshPart")
		mp.Name = n
		mp.Parent = sedan
		if not string.find(n, "Glass") then
			local sa = roblox.Instance.new("SurfaceAppearance")
			sa.Parent = mp
		end
		local junk = roblox.Instance.new("Attachment")
		junk.Parent = mp
	end
	local h2 = Harness.new(true, { services = { ReplicatedStorage = rs } })
	local B2 = h2.require("shared/VehicleBuilder")
	local ok, model = pcall(B2.build, "Sedan", false)
	check("textured import: builds", ok, model)
	if ok then
		local body = model:FindFirstChild("Sedan_Body")
		check("textured import: mesh placed", body ~= nil and body:IsA("MeshPart"))
		check("textured import: SurfaceAppearance kept", body and body:FindFirstChildOfClass("SurfaceAppearance") ~= nil)
		check("textured import: stray children removed", body and body:FindFirstChildOfClass("Attachment") == nil)
		check("textured import: glass stays untextured glass", model.Sedan_Glass.Material == roblox.Enum.Material.Glass)
		check("textured import: wheel mesh welded to the wheel", model.Sedan_Wheel1:FindFirstChildOfClass("WeldConstraint") ~= nil)
		check("textured import: stand-in parts hidden", model.Root.Transparency == 1 and model.Body.Transparency == 1)
		check("textured import: flagged", model:GetAttribute("DetailedMesh") == true)
	end
end

print(string.format("builders_spec: %d passed, %d failed", passed, failed))
process.exit(if failed > 0 then 1 else 0)
