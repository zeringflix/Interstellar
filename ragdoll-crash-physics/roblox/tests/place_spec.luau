-- lune run tests/place_spec.luau : checks the finished place file RagdollCrashPhysics.rbxlx
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Harness = require("./harness")
local place = roblox.deserializePlace(fs.readFile("../RagdollCrashPhysics.rbxlx"))
local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then passed += 1 else failed += 1 print("FAIL", name, detail) end
end
local ws = place:GetService("Workspace")
local rs = place:GetService("ReplicatedStorage")
local sss = place:GetService("ServerScriptService")
local sps = place:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local map = ws:FindFirstChild("Map")
check("map is pre-built in Workspace", map and map:GetAttribute("Prebuilt") == "Test Grounds" and map:FindFirstChild("Static") and map:FindFirstChild("Props"))
check("no default baseplate left", ws:FindFirstChild("Baseplate") == nil)
check("server bootstrap is a Script", sss:FindFirstChild("Server") and sss.Server:FindFirstChild("Main") and sss.Server.Main.ClassName == "Script")
check("client bootstrap is a LocalScript", sps and sps:FindFirstChild("Client") and sps.Client:FindFirstChild("Main") and sps.Client.Main.ClassName == "LocalScript")
local mods = 0
for _, d in place:GetDescendants() do
	if d:IsA("ModuleScript") then mods += 1 end
end
check("all modules present (30)", mods == 30, mods)
check("VehicleMeshes folder ready for the imported models", rs:FindFirstChild("VehicleMeshes") ~= nil)
check("streaming on", ws.StreamingEnabled == true)
local lawn, tiles, roads = 0, 0, 0
for _, d in map:GetDescendants() do
	if d.Name == "Lawn" then lawn += 1 elseif d.Name == "Tile" then tiles += 1 elseif string.find(d.Name, "Road") or string.find(d.Name, "Avenue") or string.find(d.Name, "Link") then roads += 1 end
end
check("concrete floor tiles + only a few lawns", tiles > 50 and lawn <= 6, { tiles, lawn })
check("road network", roads >= 6, roads)
check("dead-end railway", map.Static:FindFirstChild("BufferBeam") and map.Static:FindFirstChild("RailAnchor"))
-- the server reuses the baked map instead of rebuilding it
local h = Harness.new(true, { workspace = ws, services = { Lighting = place:GetService("Lighting"), RunService = {} } })
local MapService = h.require("server/MapService")
local n0 = #map:GetDescendants()
local m2, anchor = MapService.build("Test Grounds")
check("runtime reuses the baked map", m2 == map and #map:GetDescendants() == n0 and anchor and anchor.Name == "RailAnchor")
check("quick-spawn stations found on the baked map", #MapService.stations == 4, #MapService.stations)
print(string.format("place_spec: %d passed, %d failed", passed, failed))
process.exit(if failed > 0 then 1 else 0)
