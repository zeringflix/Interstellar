-- Minimal module loader so game modules (which use `require(script.Parent.X)`) run under Lune.
-- With `useRoblox` the real Roblox datatypes / Instance classes from @lune/roblox are injected,
-- so builders are checked against the actual Roblox API reflection database.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Harness = {}
local cache = {}
local ROOT = "src"
local DIRS = { Shared = "shared", Server = "server", Client = "client" }

local function node(path: string)
	return setmetatable({ __path = path }, {
		__index = function(self, key)
			if key == "Parent" then
				return node((string.gsub(path, "/[^/]+$", "")))
			end
			return node(path .. "/" .. key)
		end,
	})
end

function Harness.new(useRoblox: boolean, extraGlobals: { [string]: any }?)
	local env = {}
	local game = { ReplicatedStorage = { Shared = node(ROOT .. "/shared") } }
	function game:GetService(name)
		return (extraGlobals and extraGlobals.services and extraGlobals.services[name]) or game[name] or {}
	end
	local function load(path: string)
		if cache[path] ~= nil and not useRoblox then
			return cache[path]
		end
		local file
		for _, ext in { ".luau", ".server.luau", ".client.luau" } do
			if fs.isFile(path .. ext) then
				file = path .. ext
			end
		end
		assert(file, "module not found: " .. path)
		-- Lune copies the environment table, so globals must be real keys (no metatable fallback)
		local e = { script = node(path), game = game }
		for k, v in env do
			e[k] = v
		end
		e.require = function(target)
			return load(target.__path)
		end
		local fn = luau.load(fs.readFile(file), { debugName = file, environment = e })
		local result = fn()
		cache[path] = result
		return result
	end
	if useRoblox then
		cache = {}
		local roblox = require("@lune/roblox")
		for _, name in { "Instance", "Vector3", "Vector2", "CFrame", "Color3", "Enum", "PhysicalProperties", "UDim", "UDim2",
			"NumberRange", "NumberSequence", "NumberSequenceKeypoint", "ColorSequence", "Random", "TweenInfo", "Rect" } do
			env[name] = (roblox :: any)[name]
		end
	end
	for k, v in extraGlobals or {} do
		env[k] = v
	end
	env.game = game
	Harness.game = game
	return { require = function(rel: string)
		return load(ROOT .. "/" .. rel)
	end, env = env, game = game }
end

return Harness
