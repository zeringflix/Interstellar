--!nonstrict
-- HUD + windows, laid out like the reference sandbox UI:
--   left column      SHOP / VEHICLES / SANDBOX tiles
--   top row          round buttons: Settings, Dummy customisation, Controls help
--   right column     pack tiles + round REVIVE / RESET buttons
--   bottom centre    the damage text bar (HitNotificationController)
--   bottom right     driving key binds while in a vehicle (phones / tablets: a slim strip under the top row)
-- Works with mouse, touch and gamepad (every control is a real button; B closes the open window).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Shared = game.ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Specs = require(Shared.VehicleSpecs)
local VehicleBuilder = require(Shared.VehicleBuilder)
local Gui = require(script.Parent.Gui)
local Settings = require(script.Parent.Settings)
local Audio = require(script.Parent.AudioController)
local Camera = require(script.Parent.CameraController)
local FirstPerson = require(script.Parent.FirstPersonController)
local Replay = require(script.Parent.ReplayController)
local Feed = require(script.Parent.HitNotificationController)
local Visuals = require(script.Parent.DummyVisuals)
local VehicleInput = require(script.Parent.VehicleInputController)

local UI = {}
UI.grabMode = false
local T = Gui.T
local player = Players.LocalPlayer
local screen: ScreenGui
local request: RemoteEvent
local mobile = false
local windows = {} :: { [string]: Frame }
local openName: string? = nil
local lastReport = nil
local reportBody: ScrollingFrame
local dummyType = "Noob"

local function send(...)
	request:FireServer(...)
end

-- unlock state, read from the attributes ProgressionService writes on the Player
local PAID, COST, LADDER_ORDER = {}, {}, {}
for _, p in Config.Progression.Paid do
	PAID[p.vehicle] = p
end
for i, step in Config.Progression.Ladder do
	COST[step[1]] = step[2]
	LADDER_ORDER[i] = step[1]
end
local function unlocked(key: string): boolean
	local list = player:GetAttribute("Unlocked")
	if typeof(list) ~= "string" then
		return key == LADDER_ORDER[1]
	end
	return table.find(string.split(list, ","), key) ~= nil
end
local function points(): number
	return player:GetAttribute("CrashPoints") or 0
end
local function comma(n: number): string
	local str = tostring(math.floor(n))
	return (str:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function buyPass(key: string)
	local p = PAID[key]
	if p and p.passId > 0 then
		MarketplaceService:PromptGamePassPurchase(player, p.passId)
	else
		UI.toast("Coming soon to the Shop")
	end
end

local function toggle(name: string?)
	local target = if openName == name then nil else name
	for n, p in windows do
		p.Visible = n == target
	end
	openName = target
	if target == "Vehicles" and UI.refreshVehiclesIfDirty then
		UI.refreshVehiclesIfDirty()
	end
	Audio.ui(if target then "uiOpen" else "uiClick", 0.4)
	if target and UserInputService.GamepadEnabled and not mobile then
		GuiService:Select(windows[target]) -- lets a controller move through the window
	end
end

local function window(name: string, title: string, color: string, icon: string, w: number, h: number): ScrollingFrame
	local win, body = Gui.window(title, color, icon, function()
		toggle(nil)
	end)
	win.Name = name
	win.Visible = false
	win.AnchorPoint = Vector2.new(0.5, 0.5)
	win.Position = UDim2.fromScale(0.5, 0.5)
	win.Size = if mobile then UDim2.new(0, math.min(w, 520), 0.84, 0) else UDim2.fromOffset(w, h)
	win.Parent = screen
	windows[name] = win
	return body
end

local function section(parent: Instance, text: string, order: number)
	Gui.label(text, 14, { TextColor3 = T.dim, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 22), Parent = parent })
end

-- row with a caption on the left and a control on the right (Settings / Sandbox style)
local function row(parent: Instance, text: string, order: number, sub: string?): Frame
	local r = Gui.make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, if sub then 62 else 46), LayoutOrder = order, Parent = parent })
	Gui.label(text, 20, { Position = UDim2.fromOffset(4, 0), Size = UDim2.new(1, -150, 0, 44), TextWrapped = true, Parent = r })
	if sub then
		Gui.label(sub, 12, { Position = UDim2.fromOffset(4, 40), Size = UDim2.new(1, -150, 0, 18), TextColor3 = T.dim, Parent = r })
	end
	return r
end

local function onOff(parent: Instance, text: string, key: string, order: number, sub: string?)
	local r = row(parent, text, order, sub)
	local b: TextButton
	local function paint()
		Gui.setText(b, if Settings.get(key) then "ON" else "OFF")
		Gui.recolor(b, if Settings.get(key) then "green" else "red")
	end
	b = Gui.pill("", "green", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 3), Size = UDim2.fromOffset(120, 40), TextSize = 20, Parent = r }, function()
		Settings.set(key, not Settings.get(key))
		paint()
		Audio.ui("uiClick")
	end)
	paint()
end

local function cycle(parent: Instance, text: string, key: string, order: number, color: string, after: ((any) -> ())?)
	local r = row(parent, text, order)
	local b: TextButton
	b = Gui.pill(string.upper(tostring(Settings.get(key))), color, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 3), Size = UDim2.fromOffset(140, 40), TextSize = 18, Parent = r }, function()
		local opts = Settings.options[key]
		local v = opts[(table.find(opts, Settings.get(key)) :: number) % #opts + 1]
		Settings.set(key, v)
		Gui.setText(b, string.upper(v))
		Audio.ui("uiClick")
		if after then
			after(v)
		end
	end)
end

local function volume(parent: Instance, text: string, key: string, order: number)
	local r = row(parent, text, order)
	local value = Gui.label("", 18, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -52, 0, 3), Size = UDim2.fromOffset(56, 40), TextXAlignment = Enum.TextXAlignment.Center, Parent = r })
	local function paint()
		value.Text = string.format("%d%%", math.floor(Settings.get(key) * 100 + 0.5))
	end
	for _, def in { { "-", -0.1, -112 }, { "+", 0.1, -4 } } do
		Gui.pill(def[1], "grey", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, def[3], 0, 3), Size = UDim2.fromOffset(44, 40), TextSize = 22, Parent = r }, function()
			Settings.set(key, math.clamp(math.floor((Settings.get(key) + def[2]) * 10 + 0.5) / 10, 0, 1))
			paint()
			Audio.ui("uiClick")
		end)
	end
	paint()
end

-- Vehicles ("Weapons" in the reference: category list on the left, cards on the right) ------------
local function vehicleCard(parent: Instance, key: string, order: number)
	local spec = Specs.Vehicles[key]
	local card = Gui.make("Frame", { BackgroundColor3 = T.panel2, BackgroundTransparency = 0.15, LayoutOrder = order, Parent = parent }, { Gui.corner(6), Gui.stroke(T.stroke, 3) })
	Gui.label(spec.display, 17, { Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, Parent = card })
	-- the real in-game model in a ViewportFrame, so the picture always matches what spawns
	local vp = Gui.make("ViewportFrame", { Size = UDim2.new(1, -12, 0, 84), Position = UDim2.fromOffset(6, 28), BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 200, 200), LightDirection = Vector3.new(-1, -2, -1), Parent = card })
	task.spawn(function()
		local model = VehicleBuilder.build(key, true)
		model.Parent = vp
		local size = model:GetExtentsSize()
		local centre = model:GetBoundingBox().Position
		local cam = Instance.new("Camera")
		cam.FieldOfView = 30
		cam.CFrame = CFrame.lookAt(centre + Vector3.new(-0.8, 0.45, -1).Unit * (size.Magnitude * 1.05 / (2 * math.tan(math.rad(15)))), centre)
		cam.Parent = vp
		vp.CurrentCamera = cam
	end)
	Gui.label(spec.klass, 11, { Position = UDim2.fromOffset(0, 112), Size = UDim2.new(1, 0, 0, 16), TextColor3 = T.dim, TextXAlignment = Enum.TextXAlignment.Center, Parent = card })
	local btnProps = { Size = UDim2.new(1, -14, 0, 38), Position = UDim2.new(0, 7, 1, -45), TextSize = 20, Parent = card }
	if unlocked(key) then
		Gui.pill("SPAWN", "green", btnProps, function()
			send("SpawnVehicle", key)
			toggle(nil)
		end)
	elseif PAID[key] then
		vp.ImageColor3 = Color3.fromRGB(150, 150, 160)
		Gui.pill(if PAID[key].passId > 0 then "R$ " .. PAID[key].price else "SOON", if PAID[key].passId > 0 then "purple" else "grey", btnProps, function()
			buyPass(key)
		end)
		Gui.label("ROBUX", 13, { Position = UDim2.fromOffset(10, 28), Size = UDim2.fromOffset(60, 16), TextColor3 = Color3.fromHex("#c89bff"), Parent = card })
	else
		vp.ImageColor3 = Color3.fromRGB(70, 70, 80) -- locked: darkened silhouette
		local need = COST[key] or 0
		local bar = Gui.make("Frame", { Position = UDim2.new(0, 7, 1, -58), Size = UDim2.new(1, -14, 0, 8), BackgroundColor3 = T.panel, Parent = card }, { Gui.corner(4) })
		Gui.make("Frame", { Size = UDim2.fromScale(math.clamp(points() / math.max(need, 1), 0, 1), 1), BackgroundColor3 = T.warn, Parent = bar }, { Gui.corner(4) })
		Gui.pill("LOCKED  " .. comma(need), "grey", btnProps, function()
			UI.toast(string.format("Unlocks at %s crash points - crash into dummies to earn them", comma(need)))
		end)
	end
end

local function buildVehicles()
	local body = window("Vehicles", "Vehicles", "red", "car", 760, 520)
	body.ScrollingEnabled = false
	body.AutomaticCanvasSize = Enum.AutomaticSize.None
	local tabW = if mobile then 108 else 150
	local tabs = Gui.panel({ Size = UDim2.new(0, tabW, 1, 0), Parent = body }, { Gui.list(4), Gui.padding(4) })
	local heading = Gui.label("CARS", 26, { Position = UDim2.fromOffset(tabW + 16, 0), Size = UDim2.new(1, -tabW - 16, 0, 32), Parent = body })
	local gridHolder = Gui.make("ScrollingFrame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(tabW + 12, 38), Size = UDim2.new(1, -tabW - 12, 1, -38),
		ScrollBarThickness = 6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = body },
		{ Gui.make("UIGridLayout", { CellSize = UDim2.fromOffset(if mobile then 132 else 172, 196), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
			Gui.padding(4) })
	local buttons = {}
	local show
	show = function(cat: string)
		for _, c in gridHolder:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		for i, key in Specs.Order do
			if Specs.Vehicles[key].category == cat then
				vehicleCard(gridHolder, key, i)
			end
		end
		heading.Text = string.upper(cat)
		for c, b in buttons do
			Gui.recolor(b, if c == cat then "orange" else "grey")
		end
	end
	for i, cat in { "Cars", "Heavy", "Military", "Aircraft", "Special" } do
		buttons[cat] = Gui.pill(cat, "grey", { Size = UDim2.new(1, 0, 0, 46), TextSize = if mobile then 17 else 22, LayoutOrder = i, Parent = tabs }, function()
			Audio.ui("uiClick")
			show(cat)
		end)
	end
	local current, dirty = "Cars", false
	local plain = show
	show = function(cat: string)
		current, dirty = cat, false
		plain(cat)
	end
	show("Cars")
	local function refresh()
		if windows.Vehicles and windows.Vehicles.Visible then
			show(current)
		else
			dirty = true
		end
	end
	player:GetAttributeChangedSignal("Unlocked"):Connect(refresh)
	player:GetAttributeChangedSignal("CrashPoints"):Connect(refresh)
	UI.refreshVehiclesIfDirty = function()
		if dirty then
			show(current)
		end
	end
end

-- Sandbox ------------------------------------------------------------------------------------------
local function buildSandbox()
	local body = window("Sandbox", "Sandbox", "green", "sandbox", 520, 520)
	Gui.list(6).Parent = body
	local function action(text: string, color: string, order: number, fn: () -> ())
		return Gui.pill(text, color, { Size = UDim2.new(1, -8, 0, 42), TextSize = 18, LayoutOrder = order, Parent = body }, fn)
	end
	local r = row(body, "Slow motion replay", 1, "Watch the last 10 seconds at 0.25x")
	Gui.pill("PLAY", "green", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 3), Size = UDim2.fromOffset(120, 40), TextSize = 20, Parent = r }, function()
		if Replay.available() < 1.5 then
			UI.toast("Nothing to replay yet")
		else
			toggle(nil)
			task.spawn(Replay.play)
		end
	end)
	r = row(body, "Grab tool", 2, "Hold a dummy and drag it around")
	local grab: TextButton
	grab = Gui.pill("OFF", "red", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 3), Size = UDim2.fromOffset(120, 40), TextSize = 20, Parent = r }, function()
		UI.grabMode = not UI.grabMode
		Gui.setText(grab, if UI.grabMode then "ON" else "OFF")
		Gui.recolor(grab, if UI.grabMode then "green" else "red")
		Audio.ui("uiSelect")
	end)
	section(body, "DUMMIES", 10)
	local spawnRow = Gui.make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 42), LayoutOrder = 11, Parent = body }, { Gui.list(6, true) })
	for i, n in { 1, 5, 10 } do
		Gui.pill("SPAWN " .. n, "blue", { Size = UDim2.new(1 / 3, -4, 1, 0), TextSize = 17, LayoutOrder = i, Parent = spawnRow }, function()
			send("SpawnDummies", n, dummyType)
		end)
	end
	action("RESET ALL DUMMIES", "orange", 12, function()
		Audio.ui("resetScene")
		send("ResetDummies")
	end)
	action("REMOVE SELECTED DUMMY", "grey", 13, function()
		local m = Visuals.selected
		if m then
			Audio.ui("uiDelete")
			send("DummyAction", m:GetAttribute("DummyId"), "Delete")
		else
			UI.toast("Click a dummy first")
		end
	end)
	section(body, "PRESETS", 20)
	local grid = Gui.make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 138), LayoutOrder = 21, Parent = body },
		{ Gui.make("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 40), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
	for i, def in { { "Line", "Dummy Line" }, { "Bowling", "Bowling" }, { "Crowd", "Crowd" }, { "Tower", "Tower" }, { "Crossing", "Rail Crossing" }, { "Showcase", "Whole Map" } } do
		Gui.pill(def[2], "purple", { TextSize = 16, LayoutOrder = i, Parent = grid }, function()
			Audio.ui("uiSelect")
			send("Preset", def[1])
			toggle(nil)
		end)
	end
	section(body, "EVENTS", 30)
	local events = Gui.make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 90), LayoutOrder = 31, Parent = body },
		{ Gui.make("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 40), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
	for i, def in { { "DummyRain", "Dummy Rain" }, { "ZeroG", "Zero-G" }, { "Blast", "Blast" }, { "ReviveAll", "Revive All" } } do
		Gui.pill(def[2], "orange", { TextSize = 16, LayoutOrder = i, Parent = events }, function()
			Audio.ui("uiSelect")
			send("Event", def[1])
		end)
	end
	section(body, "MAP", 40)
	local maps = Gui.make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 42), LayoutOrder = 41, Parent = body }, { Gui.list(6, true) })
	for i, name in Config.Map.Names do
		Gui.pill(name, "blue", { Size = UDim2.new(1 / #Config.Map.Names, -4, 1, 0), TextSize = 15, LayoutOrder = i, Parent = maps }, function()
			Audio.ui("uiSelect")
			send("LoadMap", name)
			toggle(nil)
		end)
	end
	section(body, "TELEPORT", 50)
	for i, zone in Config.Map.Zones do
		action(zone[1], "grey", 50 + i, function()
			send("Teleport", i)
			toggle(nil)
		end)
	end
	section(body, "SCENE", 70)
	action("RESET SCENE", "red", 71, function()
		Audio.ui("resetScene")
		send("ResetScene")
		UI.toast("Scene reset")
	end)
	action("CRASH REPORT", "blue", 72, function()
		toggle("Report")
		UI.fillReport()
	end)
	action("CAMERA: FOLLOW SELECTED DUMMY", "grey", 73, function()
		local m = Visuals.selected
		if Camera.mode == "Dummy" or not m then
			Camera.setMode("Vehicle")
		elseif m:FindFirstChild("UpperTorso") then
			Camera.setMode("Dummy", m.UpperTorso)
		end
	end)
	if not mobile then
		action("CAMERA: FREE FLY (WASD + Q/E)", "grey", 74, function()
			Camera.setMode(if Camera.mode == "Free" then "Vehicle" else "Free")
			toggle(nil)
		end)
	end
end

-- Shop ------------------------------------------------------------------------------------------------
local function buildShop()
	local body = window("Shop", "Shop", "red", "shop", 620, 500)
	Gui.list(8).Parent = body
	Gui.label("ROBUX VEHICLES", 16, { LayoutOrder = 0, TextColor3 = T.dim, Parent = body })
	for i, item in Config.Shop do
		local spec = Specs.Vehicles[item.vehicle]
		local card = Gui.panel({ Size = UDim2.new(1, -8, 0, 110), LayoutOrder = i, Parent = body })
		local vp = Gui.make("ViewportFrame", { Size = UDim2.fromOffset(150, 96), Position = UDim2.fromOffset(6, 7), BackgroundTransparency = 1,
			Ambient = Color3.fromRGB(200, 200, 200), LightDirection = Vector3.new(-1, -2, -1), Parent = card })
		task.spawn(function()
			local model = VehicleBuilder.build(item.vehicle, true)
			model.Parent = vp
			local size = model:GetExtentsSize()
			local centre = model:GetBoundingBox().Position
			local cam = Instance.new("Camera")
			cam.FieldOfView = 30
			cam.CFrame = CFrame.lookAt(centre + Vector3.new(-0.8, 0.45, -1).Unit * (size.Magnitude * 1.05 / (2 * math.tan(math.rad(15)))), centre)
			cam.Parent = vp
			vp.CurrentCamera = cam
		end)
		Gui.label(string.upper(spec.display), 22, { Position = UDim2.fromOffset(166, 8), Size = UDim2.new(1, -320, 0, 28), TextColor3 = Color3.fromHex("#ffb02e"), Parent = card })
		Gui.label(spec.klass .. "  -  yours forever, on every map", 13, { Position = UDim2.fromOffset(166, 40), Size = UDim2.new(1, -320, 0, 52),
			TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Parent = card })
		local owned = unlocked(item.vehicle)
		local btn = Gui.pill(if owned then "OWNED" elseif item.id > 0 then "R$ " .. item.price else "SOON", if owned then "green" elseif item.id > 0 then "purple" else "grey",
			{ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(134, 46), TextSize = 20, Parent = card }, function()
				if unlocked(item.vehicle) then
					send("SpawnVehicle", item.vehicle)
					toggle(nil)
				else
					buyPass(item.vehicle)
				end
			end)
		player:GetAttributeChangedSignal("Unlocked"):Connect(function()
			if unlocked(item.vehicle) then
				Gui.setText(btn, "SPAWN")
				Gui.recolor(btn, "green")
			end
		end)
	end
end

-- Settings ---------------------------------------------------------------------------------------------
local function buildSettings()
	local body = window("Settings", "Settings", "blue", "gear", 520, 500)
	Gui.list(4).Parent = body
	cycle(body, "Weather", "Weather", 1, "orange")
	onOff(body, "Sound Effects", "SoundEffects", 2)
	onOff(body, "Blood", "BloodText", 3, "Bleeding and blood % wording")
	onOff(body, "Damage Indicators", "Notifications", 4, "The text bar at the bottom")
	onOff(body, "Dummy Name Tags", "StatusText", 5)
	onOff(body, "Impact Effects", "ImpactEffects", 6, "Explosions, sparks, dust")
	onOff(body, "Camera Shake", "CameraShake", 7)
	cycle(body, "Graphics", "Graphics", 8, "blue")
	volume(body, "Master Volume", "MasterVolume", 9)
	volume(body, "Music Volume", "MusicVolume", 10)
	cycle(body, "Replay Quality", "ReplayQuality", 11, "blue")
	cycle(body, "Dummy Limit", "DummyLimit", 12, "blue", function(v)
		send("SetDummyLimit", v, mobile)
	end)
end

-- Dummy customisation ("NPC Customization") -----------------------------------------------------------------
local function buildDummy()
	local body = window("Dummy", "Dummy Customization", "green", "dummy", 560, 380)
	Gui.list(8).Parent = body
	local r = row(body, "Body Type", 1)
	local holder = Gui.make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 3), Size = UDim2.fromOffset(if mobile then 300 else 360, 40), Parent = r }, { Gui.list(4, true) })
	local pills = {}
	local current = Config.DummyBody
	for i, def in { { "Man", "Man" }, { "Robloxian2", "Robloxian 2.0" }, { "Blocky", "Blocky" } } do
		pills[def[1]] = Gui.pill(def[2], if def[1] == current then "green" else "red", { Size = UDim2.new(1 / 3, -3, 1, 0), TextSize = if mobile then 13 else 15, LayoutOrder = i, Parent = holder }, function()
			current = def[1]
			for k, p in pills do
				Gui.recolor(p, if k == current then "green" else "red")
			end
			Audio.ui("uiSelect")
			send("SetBody", def[1])
		end)
	end
	r = row(body, "Dummy Type", 2, "Used by the SPAWN buttons in Sandbox")
	local names = { "Noob", "Crash", "Heavy", "Light", "Armored" }
	local tb: TextButton
	tb = Gui.pill("DUMMY", "blue", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 3), Size = UDim2.fromOffset(190, 40), TextSize = 16, Parent = r }, function()
		dummyType = names[(table.find(names, dummyType) :: number) % #names + 1]
		Gui.setText(tb, Config.DummyTypes[dummyType].display)
		Audio.ui("uiClick")
	end)
	Gui.label("All dummies are grey test dummies with the animated Man face.\nThe face reacts to every hit: shock, pain, dizzy, knocked out.", 14,
		{ LayoutOrder = 3, Size = UDim2.new(1, -8, 0, 60), TextWrapped = true, TextColor3 = T.dim, TextYAlignment = Enum.TextYAlignment.Top, Parent = body })
end

-- Crash report -------------------------------------------------------------------------------------------------
function UI.fillReport()
	for _, c in reportBody:GetChildren() do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
	local r = lastReport
	if not r then
		Gui.label("No crash recorded yet. Hit a dummy!", 16, { TextColor3 = T.dim, Parent = reportBody })
	else
		section(reportBody, "LAST CRASH", 1)
		for i, l in { { "Vehicle", r.vehicle }, { "Impact Speed", r.mph .. " MPH" }, { "Dummies Hit", r.hit }, { "Down", r.down }, { "Knocked Out", r.unconscious },
			{ "Dead", r.dead }, { "Chain Reactions", r.chain }, { "Props Knocked Over", r.props } } do
			local line = Gui.make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 24), LayoutOrder = 1 + i, Parent = reportBody })
			Gui.label(l[1], 16, { TextColor3 = T.dim, Size = UDim2.new(0.6, 0, 1, 0), Parent = line })
			Gui.label(tostring(l[2]), 16, { Position = UDim2.fromScale(0.6, 0), Size = UDim2.new(0.4, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, Parent = line })
		end
		local total = string.format("%d", r.score):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
		Gui.label("CRASH SCORE  " .. total, 22, { TextColor3 = Color3.fromHex("#ffd24a"), LayoutOrder = 20, Size = UDim2.new(1, 0, 0, 34), Parent = reportBody })
	end
	section(reportBody, "EVENT LOG (newest first)", 30)
	for i, e in Feed.log do
		if i > 30 then
			break
		end
		Gui.label(string.format("#%02d  %s: %s, %s", e.id, e.part or e.region, e.injury or e.severity, string.lower(e.condition or e.status)), 13,
			{ LayoutOrder = 30 + i, Parent = reportBody })
	end
end

function UI.showReport(report)
	lastReport = report
	Audio.ui("report", 0.4)
	if openName == "Report" then
		UI.fillReport()
	end
end

-- Toast ---------------------------------------------------------------------------------------------------------
local toastLabel: TextLabel
local toastToken = 0
function UI.toast(text: string)
	toastToken += 1
	local my = toastToken
	toastLabel.Text = text
	toastLabel.Visible = true
	task.delay(3, function()
		if my == toastToken then
			toastLabel.Visible = false
		end
	end)
end

-- Key binds ---------------------------------------------------------------------------------------------------------
local BINDS = {
	car = { { "W", "Accelerate" }, { "S", "Brake / Reverse" }, { "A D", "Steer" }, { "H", "Horn" }, { "V", "First person" }, { "Space", "Get out" } },
	tank = { { "W S", "Drive" }, { "A D", "Pivot turn" }, { "Mouse", "Aim turret" }, { "V", "First person" }, { "Space", "Get out" } },
	train = { { "W", "Throttle" }, { "S", "Brake" }, { "H", "Whistle" }, { "V", "First person" }, { "Space", "Get out" } },
	sled = { { "W", "Ignite" }, { "S", "Brake" }, { "V", "First person" }, { "Space", "Bail out" } },
	plane = { { "W S", "Engine power" }, { "A D", "Bank / turn" }, { "E", "Pull up" }, { "Q", "Nose down" }, { "V", "First person" }, { "Space", "Eject" } },
	heli = { { "W S", "Forward / back" }, { "A D", "Turn" }, { "E", "Climb" }, { "Q", "Descend" }, { "V", "First person" }, { "Space", "Get out" } },
}
local PAD = { W = "RT", S = "LT", ["W S"] = "RT LT", ["A D"] = "L Stick", E = "RB", Q = "LB", H = "Y", Space = "A", Mouse = "R Stick", V = "R3" }
local TOUCH = {
	car = "Stick: drive + steer   |   Jump: get out", tank = "Stick: drive + pivot   |   Camera aims the turret", train = "Stick up / down: throttle",
	sled = "Stick up: ignite", plane = "Stick: power + bank   |   UP / DOWN buttons: pitch", heli = "Stick: move + turn   |   UP / DOWN buttons: climb",
}

function UI.init(screenGui: ScreenGui, isMobile: boolean, remotes: Instance)
	screen, mobile = screenGui, isMobile
	request = remotes:WaitForChild("Request") :: RemoteEvent
	local tile = if mobile then 76 else 104

	-- crash points + next unlock, under the title
	local pts = Gui.label("", if mobile then 12 else 15, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 58), Size = UDim2.fromOffset(420, 20),
		TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromHex("#ffd24a"), Parent = screen })
	local function paintPoints()
		local nextKey
		for _, k in LADDER_ORDER do
			if not unlocked(k) then
				nextKey = k
				break
			end
		end
		pts.Text = comma(points()) .. " CRASH POINTS" .. (if nextKey then string.format("   |   next: %s at %s", Specs.Vehicles[nextKey].display, comma(COST[nextKey])) else "   |   every unlockable vehicle unlocked")
	end
	paintPoints()
	player:GetAttributeChangedSignal("CrashPoints"):Connect(paintPoints)
	player:GetAttributeChangedSignal("Unlocked"):Connect(paintPoints)

	-- left column: SHOP / VEHICLES / SANDBOX
	local left = Gui.make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, if mobile then 62 else 120), Size = UDim2.fromOffset(tile, tile * 3 + 20), Parent = screen }, { Gui.list(8) })
	for i, def in { { "Shop", "shop" }, { "Vehicles", "car" }, { "Sandbox", "sandbox" } } do
		local b = Gui.make("TextButton", { Text = "", LayoutOrder = i, Size = UDim2.fromOffset(tile, tile), BackgroundColor3 = T.panel, BackgroundTransparency = 0.2, Parent = left },
			{ Gui.corner(8), Gui.stroke(T.stroke, 4) })
		local ic = Gui.icon(def[2], tile * 0.52, nil, b)
		ic.AnchorPoint = Vector2.new(0.5, 0)
		ic.Position = UDim2.new(0.5, 0, 0, tile * 0.1)
		Gui.label(def[1], if mobile then 13 else 17, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, Parent = b })
		b.Activated:Connect(function()
			toggle(def[1])
		end)
	end

	-- top row: round buttons
	local top = Gui.make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(190, 52), Parent = screen },
		{ Gui.list(10, true, Enum.HorizontalAlignment.Center) })
	local controlsVisible = true
	for i, def in { { "Settings", "gear" }, { "Dummy", "dummy" }, { "Controls", "pad" } } do
		local b = Gui.make("TextButton", { Text = "", LayoutOrder = i, Size = UDim2.fromOffset(50, 50), BackgroundColor3 = Color3.fromHex("#141b29"), Parent = top }, { Gui.corner(25) })
		local ic = Gui.icon(def[2], 28, nil, b)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		b.Activated:Connect(function()
			if def[1] == "Controls" then
				controlsVisible = not controlsVisible
				Audio.ui("uiClick")
			else
				toggle(def[1])
			end
		end)
	end

	-- right column: pack tiles + round buttons
	local right = Gui.make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, if mobile then 62 else 76),
		Size = UDim2.fromOffset(if mobile then 124 else 164, 240), Parent = screen }, { Gui.list(8, false, Enum.HorizontalAlignment.Right) })
	for i = 1, math.min(3, #Config.Shop) do
		local item = Config.Shop[i]
		local b = Gui.make("TextButton", { Text = "", LayoutOrder = i, Size = UDim2.new(1, 0, 0, if mobile then 44 else 54), BackgroundColor3 = T.panel2, BackgroundTransparency = 0.25, Parent = right },
			{ Gui.corner(6), Gui.stroke(T.stroke, 4) })
		Gui.label(Specs.Vehicles[item.vehicle].display, if mobile then 12 else 15, { Size = UDim2.new(1, 0, 0.55, 0), TextXAlignment = Enum.TextXAlignment.Center, Parent = b })
		Gui.label(if item.id > 0 then "R$ " .. item.price else "SOON", if mobile then 12 else 15, { Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0.5, 0),
			TextColor3 = Color3.fromHex("#3cff55"), TextXAlignment = Enum.TextXAlignment.Center, Parent = b })
		b.Activated:Connect(function()
			toggle("Shop")
		end)
	end
	local rounds = Gui.make("Frame", { BackgroundTransparency = 1, LayoutOrder = 9, Size = UDim2.new(1, 0, 0, 64), Parent = right }, { Gui.list(8, true, Enum.HorizontalAlignment.Right) })
	for i, def in { { "Revive", "revive", function()
		send("Event", "ReviveAll")
	end }, { "Reset", "reset", function()
		Audio.ui("resetScene")
		send("ResetScene")
	end } } do
		local b = Gui.make("TextButton", { Text = "", LayoutOrder = i, Size = UDim2.fromOffset(60, 60), BackgroundColor3 = Color3.fromHex("#141b29"), BackgroundTransparency = 0.25, Parent = rounds },
			{ Gui.corner(30), Gui.stroke(Color3.fromHex("#c9d2e3"), 2) })
		Gui.label(def[1], 13, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Parent = b })
		b.Activated:Connect(def[3])
	end

	buildShop()
	buildVehicles()
	buildSandbox()
	buildSettings()
	buildDummy()
	reportBody = window("Report", "Crash Report", "blue", "replay", 460, 500)
	Gui.list(4).Parent = reportBody

	toastLabel = Gui.label("", 18, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 84), Size = UDim2.fromOffset(460, 30),
		TextXAlignment = Enum.TextXAlignment.Center, Visible = false, Parent = screen })

	-- replay banner
	local banner = Gui.panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 100), Size = UDim2.fromOffset(340, 58), Visible = false, Parent = screen })
	local bannerText = Gui.label("REPLAY", 16, { Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -150, 0, 24), Parent = banner })
	local barBack = Gui.make("Frame", { Position = UDim2.fromOffset(12, 38), Size = UDim2.new(1, -24, 0, 8), BackgroundColor3 = T.panel2, Parent = banner }, { Gui.corner(4) })
	local barFill = Gui.make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.good, Parent = barBack }, { Gui.corner(4) })
	local speedButton: TextButton
	speedButton = Gui.pill("0.25x", "blue", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -70, 0, 4), Size = UDim2.fromOffset(64, 28), TextSize = 14, Parent = banner }, function()
		Replay.speed = if Replay.speed == 0.25 then 0.5 elseif Replay.speed == 0.5 then 1 else 0.25
		Gui.setText(speedButton, Replay.speed .. "x")
	end)
	Gui.pill("EXIT", "red", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 4), Size = UDim2.fromOffset(58, 28), TextSize = 14, Parent = banner }, Replay.stop)
	Replay.onState = function(playing, t, dur)
		banner.Visible = playing
		if playing then
			bannerText.Text = string.format("SLOW MOTION  %.1f / %.1fs", t, dur)
			barFill.Size = UDim2.fromScale(math.clamp(t / math.max(dur, 0.01), 0, 1), 1)
		end
	end

	-- driving HUD: speed + key binds. Desktop / console: bottom right. Touch: slim strip under the top row.
	local hud = Gui.panel({ Name = "DriveHud", Visible = false, Parent = screen })
	local speed = Gui.label("0", 30, { Size = UDim2.fromOffset(70, 34), TextXAlignment = Enum.TextXAlignment.Right, Parent = hud })
	local unit = Gui.label("MPH", 13, { TextColor3 = T.dim, Size = UDim2.fromOffset(40, 16), Parent = hud })
	local nameLabel = Gui.label("", 15, { Size = UDim2.fromOffset(200, 20), Parent = hud })
	local extra = Gui.label("", 12, { TextColor3 = Color3.fromHex("#9fd0ff"), Size = UDim2.fromOffset(200, 16), Parent = hud })
	local binds = Gui.make("Frame", { BackgroundTransparency = 1, Parent = hud }, { Gui.list(4) })
	local touchLine = Gui.label("", 12, { TextColor3 = T.dim, TextXAlignment = Enum.TextXAlignment.Center, Parent = hud })
	local resetBtn = Gui.pill("RESET VEHICLE", "orange", { TextSize = 13, Parent = hud }, function()
		Audio.ui("resetScene")
		send("ResetVehicle")
	end)
	-- first-person toggle: the driver's own point of view from the seat
	local viewBtn: TextButton
	local function paintView()
		Gui.setText(viewBtn, if FirstPerson.enabled() then "THIRD PERSON" else "FIRST PERSON")
	end
	viewBtn = Gui.pill("FIRST PERSON", "blue", { Name = "ViewToggle", TextSize = 13, Parent = hud }, function()
		Audio.ui("uiClick")
		FirstPerson.toggle()
		paintView()
	end)
	paintView()
	FirstPerson.onChanged = function()
		paintView()
	end
	Settings.Changed:Connect(function(key)
		if key == "FirstPerson" then
			paintView()
		end
	end)
	if mobile then
		hud.AnchorPoint = Vector2.new(0.5, 0)
		hud.Position = UDim2.new(0.5, 0, 0, 62)
		hud.Size = UDim2.fromOffset(420, 52)
		speed.Position, speed.Size, speed.TextSize = UDim2.fromOffset(4, 2), UDim2.fromOffset(52, 28), 24
		unit.Position = UDim2.fromOffset(60, 10)
		nameLabel.Position, nameLabel.Size = UDim2.fromOffset(98, 4), UDim2.fromOffset(190, 18)
		extra.Visible, binds.Visible = false, false
		touchLine.Position, touchLine.Size = UDim2.fromOffset(6, 30), UDim2.new(1, -12, 0, 18)
		resetBtn.AnchorPoint, resetBtn.Position, resetBtn.Size = Vector2.new(1, 0), UDim2.new(1, -6, 0, 4), UDim2.fromOffset(116, 24)
		viewBtn.AnchorPoint, viewBtn.Position, viewBtn.Size = Vector2.new(1, 0), UDim2.new(1, -128, 0, 4), UDim2.fromOffset(110, 24)
		nameLabel.Size = UDim2.fromOffset(110, 18)
	else
		hud.AnchorPoint = Vector2.new(1, 1)
		hud.Position = UDim2.new(1, -14, 1, -14)
		hud.Size = UDim2.fromOffset(250, 288)
		viewBtn.AnchorPoint, viewBtn.Position, viewBtn.Size = Vector2.new(0, 1), UDim2.new(0, 10, 1, -42), UDim2.new(1, -20, 0, 28)
		speed.Position = UDim2.fromOffset(8, 6)
		unit.Position = UDim2.fromOffset(84, 20)
		nameLabel.Position = UDim2.fromOffset(12, 42)
		extra.Position = UDim2.fromOffset(12, 62)
		binds.Position, binds.Size = UDim2.fromOffset(12, 84), UDim2.new(1, -24, 0, 144)
		touchLine.Visible = false
		resetBtn.AnchorPoint, resetBtn.Position, resetBtn.Size = Vector2.new(0, 1), UDim2.new(0, 10, 1, -8), UDim2.new(1, -20, 0, 28)
	end

	local function fillBinds(kind: string)
		for _, c in binds:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		local pad = UserInputService:GetLastInputType().Name:find("Gamepad") ~= nil
		for i, b in BINDS[kind] or BINDS.car do
			local line = Gui.make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = i, Parent = binds })
			local key = if pad then (PAD[b[1]] or b[1]) else b[1]
			local cap = Gui.make("Frame", { BackgroundColor3 = Color3.fromHex("#eef1f6"), Size = UDim2.fromOffset(math.max(26, #key * 9 + 12), 20), Parent = line }, { Gui.corner(4), Gui.stroke(T.stroke, 2) })
			Gui.label(key, 12, { NoOutline = true, TextColor3 = Color3.fromHex("#141b29"), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Parent = cap })
			Gui.label(b[2], 13, { Position = UDim2.fromOffset(84, 0), Size = UDim2.new(1, -84, 1, 0), Parent = line })
		end
		touchLine.Text = TOUCH[kind] or TOUCH.car
	end

	local lastModel, lastPad = nil, nil
	RunService.RenderStepped:Connect(function()
		local c = VehicleInput.current
		hud.Visible = c ~= nil and controlsVisible and not Replay.playing
		if not c then
			lastModel = nil
			return
		end
		local pad = UserInputService:GetLastInputType().Name:find("Gamepad") ~= nil
		if c.model ~= lastModel or pad ~= lastPad then
			if c.model ~= lastModel then
				Camera.frameVehicle(c.model)
			end
			lastModel, lastPad = c.model, pad
			nameLabel.Text = c.spec.display
			fillBinds(c.kind)
		end
		speed.Text = tostring(math.floor((c.speedMph or 0) + 0.5))
		if c.kind == "plane" then
			extra.Text = string.format("Power %d%%  |  Alt %d ft", (c.throttle or 0) * 100, math.max(0, (c.altitude or 0) * 0.92))
		elseif c.kind == "heli" then
			extra.Text = string.format("Alt %d ft", math.max(0, (c.altitude or 0) * 0.92))
		else
			extra.Text = if c.grounded then c.spec.klass else "Airborne"
		end
	end)

	remotes:WaitForChild("Notice").OnClientEvent:Connect(function(text)
		if typeof(text) == "string" then
			UI.toast(text)
		end
	end)
	if mobile then
		Settings.set("Graphics", "Medium")
		Settings.set("ReplayQuality", "Low")
		send("SetDummyLimit", "Automatic", true)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.ButtonB and openName then
			toggle(nil)
		end
	end)
end

return UI
