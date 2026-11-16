-- A small stand-in for the Roblox engine so the real game scripts can execute under Lune.
-- Instances, properties and datatypes are Lune's real implementations (validated against the
-- Roblox reflection database). What is faked here: signals, services, and engine-side methods.
-- There is NO physics: velocities only change when game code changes them.
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Mock = {}
Mock.clock = 1000
Mock.fired = {} :: { { remote: string, kind: string, args: { any } } }
Mock.impulses = 0

local function signal()
	local s = { handlers = {} }
	function s:Connect(fn)
		table.insert(s.handlers, fn)
		return { Disconnect = function()
			local i = table.find(s.handlers, fn)
			if i then
				table.remove(s.handlers, i)
			end
		end }
	end
	function s:Once(fn)
		return s:Connect(fn)
	end
	function s:Wait()
		return 1 / 60
	end
	function s:Fire(...)
		for _, fn in table.clone(s.handlers) do
			fn(...)
		end
	end
	return s
end
Mock.signal = signal

-- Lune hands out a fresh userdata wrapper per access, so per-instance mock state is keyed by an id attribute.
local store = {} :: { [number]: { [string]: any } }
local nextId = 0
local function idOf(inst): number
	local id = inst:GetAttribute("__mock")
	if not id then
		nextId += 1
		id = nextId
		inst:SetAttribute("__mock", id)
	end
	return id
end
local function slot(inst, key: string, make: (() -> any)?)
	local id = idOf(inst)
	local t = store[id]
	if not t then
		t = {}
		store[id] = t
	end
	if t[key] == nil and make then
		t[key] = make()
	end
	return t[key]
end
local function setSlot(inst, key: string, value)
	slot(inst, "_", function()
		return true
	end)
	store[idOf(inst)][key] = value
end
Mock.slot, Mock.setSlot = slot, setSlot

local function event(class: string, name: string)
	roblox.implementProperty(class, name, function(inst)
		return slot(inst, "ev_" .. name, signal)
	end)
end
local function prop(class: string, name: string, default: any)
	roblox.implementProperty(class, name, function(inst)
		local v = slot(inst, "p_" .. name)
		if v == nil then
			return if type(default) == "function" then default(inst) else default
		end
		return v
	end, function(inst, value)
		setSlot(inst, "p_" .. name, value)
	end)
end
local function method(class: string, name: string, fn)
	roblox.implementMethod(class, name, fn)
end

function Mock.install()
	for _, e in { "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "Destroying", "AttributeChanged", "Changed" } do
		event("Instance", e)
	end
	event("GuiButton", "Activated")
	event("ProximityPrompt", "Triggered")
	event("RemoteEvent", "OnServerEvent")
	event("RemoteEvent", "OnClientEvent")
	event("BindableEvent", "Event")
	event("Player", "CharacterAdded")
	method("Instance", "WaitForChild", function(self, name)
		return self:FindFirstChild(name)
	end)
	method("Instance", "GetAttributeChangedSignal", function(self, name)
		return slot(self, "attr_" .. name, signal)
	end)
	method("Instance", "GetPropertyChangedSignal", function(self, name)
		return slot(self, "propsig_" .. name, signal)
	end)
	method("BindableEvent", "Fire", function(self, ...)
		slot(self, "ev_Event", signal):Fire(...)
	end)
	for _, kind in { "FireServer", "FireAllClients", "FireClient" } do
		method("RemoteEvent", kind, function(self, ...)
			table.insert(Mock.fired, { remote = self.Name, kind = kind, args = { ... } })
		end)
	end
	-- parts
	prop("BasePart", "AssemblyLinearVelocity", roblox.Vector3.zero)
	prop("BasePart", "AssemblyAngularVelocity", roblox.Vector3.zero)
	prop("BasePart", "LocalTransparencyModifier", 0)
	roblox.implementProperty("BasePart", "AssemblyMass", function(self)
		local d = self.CustomPhysicalProperties
		return self.Size.X * self.Size.Y * self.Size.Z * (if d then d.Density else 0.7)
	end)
	roblox.implementProperty("BasePart", "AssemblyRootPart", function(self)
		return self
	end)
	roblox.implementProperty("BasePart", "Position", function(self)
		return self.CFrame.Position
	end, function(self, v)
		self.CFrame = self.CFrame.Rotation + v
	end)
	method("BasePart", "SetNetworkOwner", function() end)
	method("BasePart", "GetMass", function(self)
		return self.AssemblyMass
	end)
	method("BasePart", "ApplyImpulse", function(self, impulse)
		Mock.impulses += 1
		self.AssemblyLinearVelocity += impulse / self.AssemblyMass
	end)
	method("BasePart", "ApplyAngularImpulse", function()
		Mock.impulses += 1
	end)
	roblox.implementProperty("Attachment", "WorldPosition", function(self)
		local parent = self.Parent
		return if parent and parent:IsA("BasePart") then (parent.CFrame * self.CFrame).Position else self.CFrame.Position
	end, function(self, v)
		self.CFrame = roblox.CFrame.new(v)
	end)
	roblox.implementProperty("Attachment", "Position", function(self)
		return self.CFrame.Position
	end, function(self, v)
		self.CFrame = roblox.CFrame.new(v)
	end)
	-- models
	local function pivot(self)
		local pp = self.PrimaryPart
		return if pp then pp.CFrame * pp.PivotOffset else roblox.CFrame.new()
	end
	method("PVInstance", "GetPivot", pivot)
	method("PVInstance", "PivotTo", function(self, target)
		local delta = target * pivot(self):Inverse()
		for _, d in self:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = delta * d.CFrame
			end
		end
	end)
	local function bounds(self)
		local lo, hi = roblox.Vector3.new(1e9, 1e9, 1e9), roblox.Vector3.new(-1e9, -1e9, -1e9)
		for _, d in self:GetDescendants() do
			if d:IsA("BasePart") then
				local p, h = d.CFrame.Position, roblox.Vector3.one * (d.Size.Magnitude / 2)
				lo, hi = lo:Min(p - h), hi:Max(p + h)
			end
		end
		return lo, hi
	end
	method("Model", "GetExtentsSize", function(self)
		local lo, hi = bounds(self)
		return hi - lo
	end)
	method("Model", "GetBoundingBox", function(self)
		local lo, hi = bounds(self)
		return roblox.CFrame.new((lo + hi) / 2), hi - lo
	end)
	-- humanoids / seats / misc
	method("Humanoid", "SetStateEnabled", function() end)
	method("Humanoid", "ChangeState", function(self, state)
		setSlot(self, "state", state)
	end)
	method("Humanoid", "GetState", function(self)
		return slot(self, "state") or roblox.Enum.HumanoidStateType.Running
	end)
	method("Humanoid", "MoveTo", function() end)
	prop("Humanoid", "MoveDirection", roblox.Vector3.zero)
	prop("Humanoid", "SeatPart", nil)
	method("Animator", "LoadAnimation", function()
		return { Looped = false, IsPlaying = false, Play = function() end, Stop = function() end }
	end)
	prop("VehicleSeat", "Occupant", nil)
	prop("VehicleSeat", "ThrottleFloat", 0)
	prop("VehicleSeat", "SteerFloat", 0)
	method("VehicleSeat", "Sit", function(self, hum)
		self.Occupant = hum
		slot(self, "propsig_Occupant", signal):Fire()
	end)
	method("ParticleEmitter", "Emit", function() end)
	method("Sound", "Play", function() end)
	method("Camera", "WorldToViewportPoint", function(self, p)
		return roblox.Vector3.new(400 + p.X, 300 + p.Y, 50), true
	end)
	method("Camera", "ViewportPointToRay", function(self)
		return { Origin = self.CFrame.Position, Direction = self.CFrame.LookVector }
	end)
	prop("Camera", "ViewportSize", roblox.Vector2.new(1280, 720))
	prop("Camera", "CameraSubject", nil)
	prop("Camera", "Focus", roblox.CFrame.new())
	prop("Workspace", "CurrentCamera", nil)
end

-- Builds the fake `game`, services and globals. side = "server" | "client".
function Mock.world()
	local dm = roblox.Instance.new("DataModel")
	local workspace = dm:GetService("Workspace")
	roblox.Instance.new("Terrain").Parent = workspace
	local camera = roblox.Instance.new("Camera")
	camera.Parent = workspace
	workspace.CurrentCamera = camera
	local replicated = dm:GetService("ReplicatedStorage")

	-- overlap / raycast emulation with real geometry (oriented box vs part centre, flat ground at y = 0)
	roblox.implementMethod("Workspace", "GetPartBoundsInBox", function(_, cf, size, params)
		local out = {}
		for _, root in (params and params.FilterDescendantsInstances) or {} do
			for _, d in root:GetDescendants() do
				if d:IsA("BasePart") then
					local l = cf:PointToObjectSpace(d.CFrame.Position)
					local h = size / 2 + d.Size / 2
					if math.abs(l.X) <= h.X and math.abs(l.Y) <= h.Y and math.abs(l.Z) <= h.Z then
						table.insert(out, d)
					end
				end
			end
		end
		return out
	end)
	roblox.implementMethod("Workspace", "Raycast", function(_, origin, dir)
		if dir.Y < 0 and origin.Y + dir.Y <= 0 then
			local t = origin.Y / -dir.Y
			return { Position = origin + dir * t, Distance = (dir * t).Magnitude, Instance = workspace, Normal = roblox.Vector3.yAxis }
		end
		return nil
	end)

	local heartbeat, renderStepped = signal(), signal()
	local renderSteps = {}
	local players = { PlayerAdded = signal(), PlayerRemoving = signal(), list = {}, LocalPlayer = nil :: any }
	function players:GetPlayers()
		return players.list
	end
	function players:GetPlayerByUserId(id)
		for _, p in players.list do
			if p.UserId == id then
				return p
			end
		end
		return nil
	end
	local function params()
		return { FilterDescendantsInstances = {}, FilterType = nil }
	end
	local services = {
		Players = players,
		RunService = { Heartbeat = heartbeat, RenderStepped = renderStepped, PreSimulation = signal(),
			BindToRenderStep = function(_, name, _, fn)
				renderSteps[name] = fn
			end },
		PhysicsService = { RegisterCollisionGroup = function() end, CollisionGroupSetCollidable = function() end },
		ReplicatedStorage = replicated,
		Lighting = dm:GetService("Lighting"),
		SoundService = dm:GetService("SoundService"),
		Debris = { AddItem = function() end },
		TweenService = { Create = function()
			return { Play = function() end, Completed = signal() }
		end },
		ContextActionService = { BindAction = function() end, UnbindAction = function() end, SetTitle = function() end, SetPosition = function() end },
		UserInputService = { TouchEnabled = false, KeyboardEnabled = true, InputBegan = signal(), InputChanged = signal(), InputEnded = signal(),
			IsKeyDown = function()
				return false
			end, GetMouseLocation = function()
				return roblox.Vector2.new(640, 360)
			end },
		GuiService = { GetGuiInset = function()
			return roblox.Vector2.new(0, 36)
		end },
	}
	local globals = {
		workspace = workspace, services = services, task = {
			spawn = function(fn, ...)
				return fn(...)
			end,
			defer = function(fn, ...)
				return fn(...)
			end,
			delay = function() end, -- timers never fire in tests
			wait = function()
				return nil -- also ends `while task.wait(n) do` watchdog loops immediately
			end,
		},
		os = { clock = function()
			return Mock.clock
		end, time = os.time },
		OverlapParams = { new = params }, RaycastParams = { new = params },
		TweenInfo = { new = function(...)
			return { ... }
		end },
		Random = { new = function(seed)
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
		end },
		warn = function(...)
			print("WARN", ...)
			Mock.warnings = (Mock.warnings or 0) + 1
		end,
	}
	for _, name in { "Instance", "Vector3", "Vector2", "CFrame", "Color3", "Enum", "PhysicalProperties", "UDim", "UDim2",
		"NumberRange", "NumberSequence", "NumberSequenceKeypoint", "ColorSequence", "Rect" } do
		globals[name] = (roblox :: any)[name]
	end
	services.ServerScriptService = dm:GetService("ServerScriptService")
	local game = { Players = players, ReplicatedStorage = replicated }
	function game:GetService(name)
		return services[name] or error("mock: no service " .. name)
	end
	globals.game = game

	-- Mirror the Rojo tree with real ModuleScript instances so `script.Parent.X` / WaitForChild work.
	local pathOf, cache = {}, {}
	local function mount(parent, dir: string, folderName: string)
		local folder = roblox.Instance.new("Folder")
		folder.Name = folderName
		folder.Parent = parent
		for _, file in fs.readDir(dir) do
			local name = string.gsub(string.gsub(string.gsub(file, "%.server%.luau$", ""), "%.client%.luau$", ""), "%.luau$", "")
			local ms = roblox.Instance.new("ModuleScript")
			ms.Name = name
			ms.Parent = folder
			pathOf[idOf(ms)] = dir .. "/" .. file
		end
		return folder
	end
	local function load(ms)
		local id = idOf(ms)
		if cache[id] ~= nil then
			return cache[id]
		end
		local path = pathOf[id] or error("mock: cannot require " .. tostring(ms))
		local e = { script = ms, require = load }
		for k, v in globals do
			e[k] = v
		end
		local result = luau.load(fs.readFile(path), { debugName = path, environment = e })()
		cache[id] = if result == nil then true else result
		return result
	end
	local shared = mount(replicated, "src/shared", "Shared")
	local server = mount(services.ServerScriptService, "src/server", "Server")
	local client = mount(dm:GetService("StarterPlayer"), "src/client", "Client")
	return { workspace = workspace, services = services, heartbeat = heartbeat, renderStepped = renderStepped,
		renderSteps = renderSteps, players = players, camera = camera, dm = dm, replicated = replicated,
		shared = shared, server = server, client = client, require = load, globals = globals }
end

-- A fake player with a minimal character.
function Mock.player(world, userId: number)
	local char = roblox.Instance.new("Model")
	char.Name = "Player"
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = roblox.CFrame.new(12, 3, 52)
	root.Parent = char
	char.PrimaryPart = root
	local hum = roblox.Instance.new("Humanoid")
	hum.Parent = char
	char.Parent = world.workspace
	local gui = roblox.Instance.new("Folder")
	gui.Name = "PlayerGui"
	local scripts = roblox.Instance.new("Folder")
	scripts.Name = "PlayerScripts"
	local p = { UserId = userId, Name = "Tester", Character = char, CharacterAdded = signal(), CameraMaxZoomDistance = 100, CameraMinZoomDistance = 0.5 }
	function p:WaitForChild(name)
		return if name == "PlayerGui" then gui else scripts
	end
	function p:FindFirstChild(name)
		return if name == "PlayerGui" then gui else nil
	end
	table.insert(world.players.list, p)
	return p, gui
end

return Mock
