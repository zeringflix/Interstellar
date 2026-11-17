-- lune run tests/verify_install_spec.luau
-- Runs tools/verify_install_studio.luau (the Studio command-bar install check) against the real
-- place file: once with every vehicle mesh "imported" (built from VehicleMeshInfo), expecting
-- INSTALL OK, and once with one mesh renamed and one texture missing, expecting both reported.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL", name, detail)
	end
end

local source = fs.readFile("tools/verify_install_studio.luau")

local function run(place)
	local out = {}
	local cache = {}
	local function req(mod)
		if cache[mod] then
			return cache[mod]
		end
		local fn = luau.load(mod.Source, { debugName = mod.Name, environment = { script = mod, require = req, game = place, workspace = place:GetService("Workspace"), Enum = roblox.Enum } })
		cache[mod] = fn()
		return cache[mod]
	end
	local fakeGame = setmetatable({}, { __index = function(_, k)
		if k == "GetService" then
			return function(_, name)
				if name == "StarterPlayer" then -- Lune does not know GameSettingsAvatar: answer R15
					local sp = place:GetService("StarterPlayer")
					return setmetatable({}, { __index = function(_, key)
						if key == "GameSettingsAvatar" then
							return roblox.Enum.GameAvatarType.R15
						end
						local v = sp[key]
						if type(v) == "function" then
							return function(_, ...)
								return v(sp, ...)
							end
						end
						return v
					end })
				end
				return place:GetService(name)
			end
		end
		return place[k]
	end })
	local env = { game = fakeGame, workspace = place:GetService("Workspace"), Enum = roblox.Enum, require = req,
		print = function(s)
			table.insert(out, s)
		end, warn = function(s)
			table.insert(out, s)
		end }
	setmetatable(env, { __index = _G })
	luau.load(source, { debugName = "verify_install_studio", environment = env })()
	return table.concat(out, "\n")
end

local function freshPlace()
	return roblox.deserializePlace(fs.readFile("../RagdollCrashPhysics.rbxlx"))
end

-- import every mesh the game expects, the way Import 3D lays them out
local function importAll(place)
	local rs = place:GetService("ReplicatedStorage")
	local info = luau.load(rs.Shared.VehicleMeshInfo.Source)()
	local all = roblox.Instance.new("Model")
	all.Name = "AllVehicles"
	for key, meshes in info do
		local m = roblox.Instance.new("Model")
		m.Name = key
		for name in meshes do
			local mp = roblox.Instance.new("MeshPart")
			mp.Name = name
			if not (string.find(name, "_Glass") or string.find(name, "_Lights")) then
				roblox.Instance.new("SurfaceAppearance").Parent = mp
			end
			mp.Parent = m
		end
		m.Parent = all
	end
	all.Parent = rs.VehicleMeshes
	return all
end

local p1 = freshPlace()
local before = run(p1)
check("without the import: every vehicle is reported missing", select(2, string.gsub(before, "no model named", "")) == 17, before)
check("without the import: no INSTALL OK", not string.find(before, "INSTALL OK"))
importAll(p1)
local good = run(p1)
check("full import: INSTALL OK", string.find(good, "INSTALL OK") ~= nil, good)
check("full import: 17 of 17 vehicles complete", string.find(good, "vehicles complete: 17 of 17") ~= nil, good)
check("notes the game pass ids still to fill in", string.find(good, "game pass id is 0") ~= nil)

local p2 = freshPlace()
local all = importAll(p2)
all.Sedan.Sedan_Steer.Name = "Sedan_Steer.001"
all.Tank.Tank_Body:FindFirstChildOfClass("SurfaceAppearance"):Destroy()
local broken = run(p2)
check("renamed mesh reported", string.find(broken, "Sedan: missing meshes") ~= nil and string.find(broken, "Sedan_Steer") ~= nil, broken)
check("missing steering mesh explained", string.find(broken, "no Sedan_Steer mesh") ~= nil, broken)
check("untextured mesh reported", string.find(broken, "Tank: meshes without a SurfaceAppearance") ~= nil, broken)
check("problems counted, no INSTALL OK", string.find(broken, "problem%(s%) found") ~= nil and not string.find(broken, "INSTALL OK"))
print(string.format("verify_install_spec: %d passed, %d failed", passed, failed))
process.exit(if failed > 0 then 1 else 0)
