-- lune run tools/bake_place.luau <in.rbxl> <out.rbxlx>
-- Takes the Rojo-built place and pre-builds the default map (Test Grounds) into Workspace, so the
-- map is visible and editable in Roblox Studio before pressing Play. The server reuses it at runtime.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Harness = require("../tests/harness")

local input, output = process.args[1], process.args[2]
local place = roblox.deserializePlace(fs.readFile(input))
local workspace = place:GetService("Workspace")
local lighting = place:GetService("Lighting")
if not workspace:FindFirstChildOfClass("Terrain") then
	roblox.Instance.new("Terrain").Parent = workspace
end
local Random = {}
function Random.new(seed)
	local state = seed or 1
	local r = {}
	local function nextf()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
	function r:NextNumber(a, b)
		return a + (b - a) * nextf()
	end
	function r:NextInteger(a, b)
		return a + math.floor(nextf() * (b - a + 1))
	end
	return r
end
local h = Harness.new(true, { workspace = workspace, Random = Random, services = { Lighting = lighting, RunService = {} } })
local MapService = h.require("server/MapService")
local map = MapService.build("Test Grounds")
map:SetAttribute("Prebuilt", "Test Grounds")
local spawn = map.Static:FindFirstChildOfClass("SpawnLocation")
-- keep Studio's default Baseplate / SpawnLocation out of the way
for _, c in workspace:GetChildren() do
	if (c.Name == "Baseplate" or c:IsA("SpawnLocation")) and c ~= spawn then
		c:Destroy()
	end
end
local n = 0
for _, d in map:GetDescendants() do
	if d:IsA("BasePart") then
		n += 1
	end
end
fs.writeFile(output, roblox.serializePlace(place, true))
print(string.format("baked %s: %d parts in Workspace.Map -> %s", MapService.current, n, output))
