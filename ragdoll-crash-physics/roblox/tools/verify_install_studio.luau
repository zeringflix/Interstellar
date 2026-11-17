-- RAGDOLL CRASH PHYSICS - install check for Roblox Studio.
-- Paste this whole file into Studio's Command Bar (View > Command Bar) and press Enter while in
-- EDIT mode (not while playing). It prints "INSTALL OK" or every problem it finds, one per line.
-- It changes nothing.
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local SP = game:GetService("StarterPlayer")
local problems, notes = {}, {}
local function bad(msg)
	table.insert(problems, msg)
end
local function note(msg)
	table.insert(notes, msg)
end
local function child(parent, name, label)
	local c = parent and parent:FindFirstChild(name)
	if not c then
		bad("missing " .. label)
	end
	return c
end

-- 1. scripts, in the containers Rojo put them in
local shared = child(RS, "Shared", "ReplicatedStorage.Shared")
for _, n in { "AudioIds", "Cockpit", "DamageModel", "GameConfig", "VehicleBuilder", "VehicleMeshInfo", "VehicleSpecs" } do
	child(shared, n, "ReplicatedStorage.Shared." .. n)
end
local server = child(SSS, "Server", "ServerScriptService.Server")
for _, n in { "Main", "CrashReportService", "DummyRig", "DummyService", "ImpactService", "MapService", "ProgressionService",
	"RagdollService", "ScenarioService", "SceneResetService", "VehicleService" } do
	child(server, n, "ServerScriptService.Server." .. n)
end
local sps = child(SP, "StarterPlayerScripts", "StarterPlayer.StarterPlayerScripts")
local client = child(sps, "Client", "StarterPlayer.StarterPlayerScripts.Client")
for _, n in { "Main", "AudioController", "CameraController", "DummyInspectionController", "DummyVisuals", "EffectsController",
	"FirstPersonController", "Gui", "HitNotificationController", "ReplayController", "Settings", "UIAssets", "UIController",
	"VehicleInputController" } do
	child(client, n, "StarterPlayer.StarterPlayerScripts.Client." .. n)
end
child(workspace, "Map", "Workspace.Map (the baked Test Grounds map)")
local lib = child(RS, "VehicleMeshes", "ReplicatedStorage.VehicleMeshes (folder for the imported models)")

-- 2. imported vehicle meshes: every mesh the game expects, by exact name, with its textures
if shared and shared:FindFirstChild("VehicleMeshInfo") and shared:FindFirstChild("VehicleSpecs") and lib then
	local info = require(shared.VehicleMeshInfo)
	local specs = require(shared.VehicleSpecs)
	local okVehicles, meshCount = 0, 0
	for _, key in specs.Order do
		local model = lib:FindFirstChild(key, true)
		if not model then
			bad(key .. ": no model named '" .. key .. "' anywhere inside ReplicatedStorage.VehicleMeshes (import AllVehicles.glb or " .. key .. ".glb)")
			continue
		end
		local missing, untextured = {}, {}
		for meshName in pairs(info[key] or {}) do
			local m = model:FindFirstChild(meshName, true)
			if not (m and m:IsA("MeshPart")) then
				table.insert(missing, meshName)
			else
				meshCount += 1
				local plain = string.find(meshName, "_Glass") or string.find(meshName, "_Lights")
				if not plain and not m:FindFirstChildOfClass("SurfaceAppearance") then
					table.insert(untextured, meshName)
				end
			end
		end
		table.sort(missing)
		table.sort(untextured)
		if #missing > 0 then
			bad(key .. ": missing meshes (renamed or not imported): " .. table.concat(missing, ", "))
		end
		if #untextured > 0 then
			bad(key .. ": meshes without a SurfaceAppearance (re-import with textures on): " .. table.concat(untextured, ", "))
		end
		local ctl = specs.Vehicles[key].cockpit and specs.Vehicles[key].cockpit.control
		if ctl and (ctl.type == "wheel" or ctl.type == "yoke" or ctl.type == "bars") and not model:FindFirstChild(key .. "_Steer", true) then
			bad(key .. ": no " .. key .. "_Steer mesh, so the steering wheel cannot turn or be held in first person")
		end
		if #missing == 0 and #untextured == 0 then
			okVehicles += 1
		end
	end
	note(string.format("vehicles complete: %d of %d (%d meshes found)", okVehicles, #specs.Order, meshCount))
end

-- 3. settings worth knowing about
if shared and shared:FindFirstChild("GameConfig") then
	local Config = require(shared.GameConfig)
	local P = Config.Progression
	if P then
		for _, p in P.Paid do
			if p.passId == 0 then
				note(p.vehicle .. " game pass id is 0: it shows SOON until you paste its pass id into GameConfig.Progression.Paid")
			end
		end
		if P.StudioUnlockAll then
			note("StudioUnlockAll is true (fine for testing in Studio; it never applies in live servers)")
		end
	end
end
local ok, avatar = pcall(function()
	return SP.GameSettingsAvatar
end)
if ok and avatar == Enum.GameAvatarType.R6 then
	note("Avatar type is R6: first person still works, but only R15 avatars put their hands on the steering wheel (Game Settings > Avatar)")
end

for _, n in notes do
	print("[RCP check] note: " .. n)
end
if #problems == 0 then
	print("[RCP check] INSTALL OK")
else
	for _, p in problems do
		warn("[RCP check] PROBLEM: " .. p)
	end
	warn(string.format("[RCP check] %d problem(s) found", #problems))
end
