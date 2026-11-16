--!nonstrict
-- Menus and HUD: a clean crash-test control panel. Left: VEHICLES / DUMMIES / TOOLS / MAP.
-- Top-right: settings, reset scene, replay, crash report. Bottom: contextual vehicle HUD.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Shared = game.ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Specs = require(Shared.VehicleSpecs)
local VehicleBuilder = require(Shared.VehicleBuilder)
local Gui = require(script.Parent.Gui)
local Settings = require(script.Parent.Settings)
local Audio = require(script.Parent.AudioController)
local Camera = require(script.Parent.CameraController)
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
local panels = {} :: { [string]: Frame }
local openName: string? = nil
local lastReport = nil
local reportBody: Frame
local dummyType = "Noob"

local function send(...)
	request:FireServer(...)
end

local function toggle(name: string?)
	local target = if openName == name then nil else name
	for n, p in panels do
		p.Visible = n == target
	end
	openName = target
	Audio.ui(if target then "uiOpen" else "uiClick", 0.4)
end

local function makePanel(name: string, titleText: string, width: number, height: number): Frame
	local p = Gui.panel({ Name = name, Visible = false, Parent = screen })
	if mobile then
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.Position = UDim2.fromScale(0.5, 0.5)
		p.Size = UDim2.new(0.86, 0, 0.82, 0)
	else
		p.Position = UDim2.fromOffset(176, 64)
		p.Size = UDim2.fromOffset(width, height)
	end
	Gui.label(titleText, 18, { Font = T.black, Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -70, 0, 24), Parent = p })
	Gui.button("✕", { Size = UDim2.fromOffset(34, 34), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Parent = p }, function()
		toggle(nil)
	end)
	local body = Gui.make("ScrollingFrame", { Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 50),
		Size = UDim2.new(1, -32, 1, -62), ScrollBarThickness = 5, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarImageColor3 = T.stroke, Parent = p })
	panels[name] = p
	return body
end

local function section(parent: Instance, text: string, order: number)
	Gui.label(text, 12, { TextColor3 = T.dim, Font = T.bold, LayoutOrder = order, Parent = parent })
end

-- Vehicles ---------------------------------------------------------------------------
local function statBar(parent: Instance, name: string, value: number, order: number)
	local row = Gui.make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 12), LayoutOrder = order, Parent = parent })
	Gui.label(name, 10, { Size = UDim2.new(0, 56, 1, 0), TextColor3 = T.dim, Parent = row })
	for i = 1, 5 do
		Gui.make("Frame", { Position = UDim2.new(0, 58 + (i - 1) * 15, 0.5, -3), Size = UDim2.fromOffset(12, 6),
			BackgroundColor3 = if i <= value then T.accent else T.panel, Parent = row }, { Gui.corner(2) })
	end
end

local function vehicleCard(parent: Instance, key: string, order: number)
	local spec = Specs.Vehicles[key]
	local card = Gui.make("Frame", { BackgroundColor3 = T.panel2, LayoutOrder = order, Parent = parent }, { Gui.corner(10), Gui.stroke() })
	-- a real in-game model in a ViewportFrame: the thumbnail always matches what spawns
	local vp = Gui.make("ViewportFrame", { Size = UDim2.new(1, -12, 0, 96), Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Color3.fromHex("#7fc0f0"), Ambient = Color3.fromRGB(190, 190, 190), LightDirection = Vector3.new(-1, -2, -1), Parent = card }, { Gui.corner(8) })
	task.spawn(function()
		local model = VehicleBuilder.build(key, true)
		model.Parent = vp
		local size = model:GetExtentsSize()
		local centre = model:GetBoundingBox().Position
		local cam = Instance.new("Camera")
		cam.FieldOfView = 30
		local dist = size.Magnitude * 1.05 / (2 * math.tan(math.rad(15)))
		cam.CFrame = CFrame.lookAt(centre + Vector3.new(-0.8, 0.45, -1).Unit * dist, centre)
		cam.Parent = vp
		vp.CurrentCamera = cam
	end)
	Gui.label(string.upper(spec.display), 14, { Font = T.black, Position = UDim2.fromOffset(10, 106), Size = UDim2.new(1, -20, 0, 18), Parent = card })
	Gui.label(spec.klass, 11, { TextColor3 = T.dim, Position = UDim2.fromOffset(10, 124), Size = UDim2.new(1, -20, 0, 14), Parent = card })
	local stats = Gui.make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 142), Size = UDim2.new(1, -20, 0, 44), Parent = card }, { Gui.list(3) })
	statBar(stats, "SPEED", spec.stats.speed, 1)
	statBar(stats, "WEIGHT", spec.stats.weight, 2)
	statBar(stats, "HANDLING", spec.stats.handling, 3)
	Gui.button("SPAWN", { Size = UDim2.new(1, -20, 0, 36), Position = UDim2.new(0, 10, 1, -44), BackgroundColor3 = T.accent, Parent = card }, function()
		send("SpawnVehicle", key)
		toggle(nil)
	end)
end

local function buildVehicles()
	local body = makePanel("Vehicles", "VEHICLES", 560, 520)
	local tabs = Gui.make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = body }, { Gui.list(6, true) })
	local grid = Gui.make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, Parent = body },
		{ Gui.make("UIGridLayout", { CellSize = UDim2.fromOffset(if mobile then 150 else 166, 238), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local categories = { "Cars", "Heavy", "Military", "Aircraft", "Special" }
	local buttons = {}
	local function show(cat: string)
		for _, c in grid:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		for i, key in Specs.Order do
			if Specs.Vehicles[key].category == cat then
				vehicleCard(grid, key, i)
			end
		end
		for c, b in buttons do
			b.BackgroundColor3 = if c == cat then T.accent else T.panel2
		end
	end
	for i, cat in categories do
		buttons[cat] = Gui.button(string.upper(cat), { Size = UDim2.fromOffset(if mobile then 84 else 98, 34), TextSize = 12, LayoutOrder = i, Parent = tabs }, function()
			Audio.ui("uiClick")
			show(cat)
		end)
	end
	show("Cars")
end

-- Dummies ----------------------------------------------------------------------------
local function buildDummies()
	local body = makePanel("Dummies", "DUMMIES", 300, 520)
	Gui.list(8).Parent = body
	section(body, "SPAWN IN FRONT OF YOU", 1)
	local typeNames = { "Noob", "Crash", "Heavy", "Light", "Armored" }
	local typeButton: TextButton
	typeButton = Gui.button("TYPE: CLASSIC NOOB", { LayoutOrder = 2, Parent = body }, function()
		dummyType = typeNames[(table.find(typeNames, dummyType) :: number) % #typeNames + 1]
		typeButton.Text = "TYPE: " .. (if dummyType == "Noob" then "CLASSIC NOOB" else Config.DummyTypes[dummyType].display)
		Audio.ui("uiClick")
	end)
	for i, n in { 1, 5, 10 } do
		Gui.button(string.format("SPAWN %d DUMM%s", n, if n == 1 then "Y" else "IES"), { LayoutOrder = 2 + i, BackgroundColor3 = T.accent, Parent = body }, function()
			send("SpawnDummies", n, dummyType)
		end)
	end
	Gui.button("REMOVE SELECTED DUMMY", { LayoutOrder = 6, Parent = body }, function()
		local m = Visuals.selected
		if m then
			Audio.ui("uiDelete")
			send("DummyAction", m:GetAttribute("DummyId"), "Delete")
		end
	end)
	Gui.button("RESET ALL DUMMIES", { LayoutOrder = 7, Parent = body }, function()
		Audio.ui("resetScene")
		send("ResetDummies")
	end)
	section(body, "PRESETS (replaces the current dummies)", 8)
	for i, def in { { "Line", "DUMMY LINE" }, { "Bowling", "DUMMY BOWLING" }, { "Crowd", "DUMMY CROWD" }, { "Tower", "DUMMY TOWER" },
		{ "Crossing", "CRASH TEST CROSSING" }, { "Types", "ONE OF EACH TYPE" }, { "Showcase", "WHOLE MAP SHOWCASE" } } do
		Gui.button(def[2], { LayoutOrder = 8 + i, Parent = body }, function()
			Audio.ui("uiSelect")
			send("Preset", def[1])
			toggle(nil)
		end)
	end
end

-- Tools ------------------------------------------------------------------------------
local function buildTools()
	local body = makePanel("Tools", "TOOLS", 300, 440)
	Gui.list(8).Parent = body
	section(body, "DUMMY TOOLS", 1)
	local grab: TextButton
	grab = Gui.button("GRAB TOOL: OFF", { LayoutOrder = 2, Parent = body }, function()
		UI.grabMode = not UI.grabMode
		grab.Text = "GRAB TOOL: " .. (if UI.grabMode then "ON  (hold a dummy and drag)" else "OFF")
		grab.BackgroundColor3 = if UI.grabMode then T.accent else T.panel2
		Audio.ui("uiSelect")
	end)
	section(body, "VEHICLE", 3)
	Gui.button("RESET VEHICLE", { LayoutOrder = 4, Parent = body }, function()
		Audio.ui("resetScene")
		send("ResetVehicle")
	end)
	Gui.button("DELETE VEHICLE", { LayoutOrder = 5, Parent = body }, function()
		Audio.ui("uiDelete")
		send("DeleteVehicle")
	end)
	section(body, "CAMERA", 6)
	Gui.button("FOLLOW VEHICLE / PLAYER", { LayoutOrder = 7, Parent = body }, function()
		Camera.setMode("Vehicle")
	end)
	Gui.button("FOLLOW SELECTED DUMMY", { LayoutOrder = 8, Parent = body }, function()
		local m = Visuals.selected
		if m and m:FindFirstChild("UpperTorso") then
			Camera.setMode("Dummy", m.UpperTorso)
		else
			UI.toast("Select a dummy first")
		end
	end)
	if not mobile then
		Gui.button("FREE CAMERA  (WASD + Q/E)", { LayoutOrder = 9, Parent = body }, function()
			Camera.setMode(if Camera.mode == "Free" then "Vehicle" else "Free")
			toggle(nil)
		end)
	end
end

-- Map -----------------------------------------------------------------------------------
local function buildMap()
	local body = makePanel("Map", "MAP — TEST ZONES", 300, 420)
	Gui.list(8).Parent = body
	for i, zone in Config.Map.Zones do
		Gui.button(string.upper(zone[1]), { LayoutOrder = i, Parent = body }, function()
			Audio.ui("uiSelect")
			send("Teleport", i)
			toggle(nil)
		end)
	end
end

-- Settings ---------------------------------------------------------------------------------
local function buildSettings()
	local body = makePanel("Settings", "SETTINGS", 340, 520)
	Gui.list(8).Parent = body
	local order = 0
	local function row(text: string): Frame
		order += 1
		local r = Gui.make("Frame", { BackgroundColor3 = T.panel2, Size = UDim2.new(1, -8, 0, 42), LayoutOrder = order, Parent = body }, { Gui.corner(8) })
		Gui.label(text, 13, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.55, 0, 1, 0), Parent = r })
		return r
	end
	local function cycle(text: string, key: string, after: ((any) -> ())?)
		local r = row(text)
		local b: TextButton
		b = Gui.button(string.upper(tostring(Settings.get(key))), { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(120, 30), TextSize = 12, BackgroundColor3 = T.panel, Parent = r }, function()
			local opts = Settings.options[key]
			local v = opts[(table.find(opts, Settings.get(key)) :: number) % #opts + 1]
			Settings.set(key, v)
			b.Text = string.upper(v)
			Audio.ui("uiClick")
			if after then
				after(v)
			end
		end)
	end
	local function switch(text: string, key: string)
		local r = row(text)
		local b: TextButton
		local function paint()
			b.Text = if Settings.get(key) then "ON" else "OFF"
			b.BackgroundColor3 = if Settings.get(key) then T.accent else T.panel
		end
		b = Gui.button("", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(72, 30), TextSize = 12, Parent = r }, function()
			Settings.set(key, not Settings.get(key))
			paint()
			Audio.ui("uiClick")
		end)
		paint()
	end
	local function volume(text: string, key: string)
		local r = row(text)
		local value = Gui.label("", 12, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -46, 0.5, 0), Size = UDim2.fromOffset(44, 30),
			TextXAlignment = Enum.TextXAlignment.Center, Parent = r })
		local function paint()
			value.Text = string.format("%d%%", math.floor(Settings.get(key) * 100 + 0.5))
		end
		for _, def in { { "–", -0.1, -96 }, { "+", 0.1, -6 } } do
			Gui.button(def[1], { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, def[3], 0.5, 0), Size = UDim2.fromOffset(34, 30), BackgroundColor3 = T.panel, Parent = r }, function()
				Settings.set(key, math.clamp(math.floor((Settings.get(key) + def[2]) * 10 + 0.5) / 10, 0, 1))
				paint()
				Audio.ui("uiClick")
			end)
		end
		paint()
	end
	cycle("Graphics Quality", "Graphics")
	switch("Impact Effects", "ImpactEffects")
	switch("Floating Status Text", "StatusText")
	switch("Damage Notifications", "Notifications")
	switch("Camera Shake", "CameraShake")
	volume("Master Volume", "MasterVolume")
	volume("SFX Volume", "SfxVolume")
	volume("Music Volume", "MusicVolume")
	cycle("Replay Quality", "ReplayQuality")
	cycle("Dummy Physics Limit", "DummyLimit", function(v)
		send("SetDummyLimit", v, mobile)
	end)
end

-- Crash report -----------------------------------------------------------------------------
local function fillReport()
	for _, c in reportBody:GetChildren() do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
	local r = lastReport
	if not r then
		Gui.label("No crash recorded yet. Hit a dummy!", 13, { TextColor3 = T.dim, Parent = reportBody })
	else
		section(reportBody, "LAST CRASH", 1)
		local lines = {
			{ "Vehicle", r.vehicle }, { "Impact Speed", r.mph .. " MPH" }, { "Dummies Hit", r.hit }, { "Dummies Down", r.down },
			{ "Unconscious", r.unconscious }, { "Dead", r.dead }, { "Chain Reactions", r.chain }, { "Props Knocked Over", r.props },
		}
		for i, l in lines do
			local row = Gui.make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 20), LayoutOrder = 1 + i, Parent = reportBody })
			Gui.label(l[1], 13, { TextColor3 = T.dim, Size = UDim2.new(0.6, 0, 1, 0), Parent = row })
			Gui.label(tostring(l[2]), 13, { Font = T.bold, Position = UDim2.fromScale(0.6, 0), Size = UDim2.new(0.4, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, Parent = row })
		end
		local total = string.format("%d", r.score):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
		Gui.label("TOTAL CRASH SCORE   " .. total, 17, { Font = T.black, TextColor3 = T.accent, LayoutOrder = 20, Size = UDim2.new(1, 0, 0, 30), Parent = reportBody })
		Gui.label("Sandbox score from verified impacts — not a medical measure.", 10, { TextColor3 = T.dim, LayoutOrder = 21, Parent = reportBody })
	end
	section(reportBody, "EVENT LOG (newest first)", 30)
	for i, e in Feed.log do
		if i > 30 then
			break
		end
		Gui.label(string.format("#%02d  %s  %s  -%d  →  %s", e.id, e.region, e.severity, e.damage, e.status), 11,
			{ LayoutOrder = 30 + i, TextColor3 = T.text, Parent = reportBody })
	end
end

function UI.showReport(report)
	lastReport = report
	Audio.ui("report", 0.4)
	UI.toast(string.format("CRASH REPORT: %d hit · score %d  (open REPORT)", report.hit, report.score))
	if openName == "Report" then
		fillReport()
	end
end

-- Toasts --------------------------------------------------------------------------------------
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

-- HUD --------------------------------------------------------------------------------------------
local HINTS = {
	car = "W/S drive · A/D steer · H horn · Space exit", tank = "W/S drive · A/D pivot · camera aims turret · Space exit",
	sled = "W launch · Space exit", train = "W/S throttle · H horn · Space exit",
	plane = "W/S engine power · A/D bank · E pull up · Q nose down · Space eject",
	heli = "W/S forward/back · A/D turn · E climb · Q descend · Space exit",
}
local MOBILE_HINTS = { plane = "Stick: power + bank · UP / DOWN buttons: pitch", heli = "Stick: move + turn · UP / DOWN buttons: climb" }

local function nearestZone(): string
	local char = player.Character
	local pos = char and char:GetPivot().Position
	if not pos then
		return ""
	end
	local best, bestD = "", math.huge
	for _, z in Config.Map.Zones do
		local d = (Vector3.new(z[2], 0, z[3]) - pos * Vector3.new(1, 0, 1)).Magnitude
		if d < bestD then
			best, bestD = z[1], d
		end
	end
	return string.upper(best)
end

function UI.init(screenGui: ScreenGui, isMobile: boolean, remotes: Instance)
	screen, mobile = screenGui, isMobile
	request = remotes:WaitForChild("Request") :: RemoteEvent

	-- top centre title
	local top = Gui.panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(if mobile then 230 else 300, 44), Parent = screen })
	Gui.label("RAGDOLL CRASH PHYSICS", if mobile then 13 else 16, { Font = T.black, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 20), Parent = top })
	local zoneLabel = Gui.label("", 11, { TextColor3 = T.accent, Font = T.bold, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 14), Parent = top })

	-- left menu
	local left = Gui.make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, if mobile then 60 else 64), Size = UDim2.fromOffset(150, 240), Parent = screen }, { Gui.list(8) })
	for i, def in { { "VEHICLES", "Vehicles", T.accent }, { "DUMMIES", "Dummies", T.panel }, { "TOOLS", "Tools", T.panel }, { "MAP", "Map", T.panel } } do
		Gui.button(def[1], { LayoutOrder = i, Size = UDim2.fromOffset(if mobile then 112 else 150, if mobile then 44 else 46), BackgroundColor3 = def[3], TextSize = 15, Parent = left }, function()
			toggle(def[2])
		end)
	end

	-- top right
	local right = Gui.make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(360, 40), Parent = screen },
		{ Gui.list(6, true, Enum.HorizontalAlignment.Right) })
	local replayButton
	for i, def in { { "REPORT", "Report" }, { "REPLAY", "Replay" }, { "RESET SCENE", "Reset" }, { "SETTINGS", "Settings" } } do
		local b = Gui.button(def[1], { LayoutOrder = i, Size = UDim2.fromOffset(if mobile then 70 else 84, 38), TextSize = if mobile then 10 else 11, Parent = right }, function()
			if def[2] == "Reset" then
				Audio.ui("resetScene")
				send("ResetScene")
				UI.toast("Scene reset")
			elseif def[2] == "Replay" then
				if Replay.playing then
					Replay.stop()
				elseif Replay.available() < 1.5 then
					UI.toast("Nothing to replay yet")
				else
					toggle(nil)
					task.spawn(Replay.play)
				end
			else
				toggle(def[2])
				if def[2] == "Report" then
					fillReport()
				end
			end
		end)
		if def[2] == "Replay" then
			replayButton = b
		end
	end

	buildVehicles()
	buildDummies()
	buildTools()
	buildMap()
	buildSettings()
	reportBody = makePanel("Report", "CRASH REPORT", 340, 520)
	Gui.list(4).Parent = reportBody

	-- toast
	toastLabel = Gui.label("", 14, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 60), Size = UDim2.fromOffset(420, 30),
		BackgroundTransparency = 0.15, BackgroundColor3 = T.panel, TextXAlignment = Enum.TextXAlignment.Center, Font = T.bold, Visible = false, Parent = screen })
	Gui.corner(8).Parent = toastLabel

	-- replay banner
	local banner = Gui.panel({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -120), Size = UDim2.fromOffset(330, 54), Visible = false, Parent = screen })
	local bannerText = Gui.label("REPLAY", 14, { Font = T.black, Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -150, 0, 20), Parent = banner })
	local barBack = Gui.make("Frame", { Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -28, 0, 6), BackgroundColor3 = T.panel2, Parent = banner }, { Gui.corner(3) })
	local barFill = Gui.make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.accent, Parent = barBack }, { Gui.corner(3) })
	local speedButton: TextButton
	speedButton = Gui.button("0.25x", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -66, 0, 4), Size = UDim2.fromOffset(60, 26), TextSize = 12, Parent = banner }, function()
		Replay.speed = if Replay.speed == 0.25 then 0.5 elseif Replay.speed == 0.5 then 1 else 0.25
		speedButton.Text = Replay.speed .. "x"
	end)
	Gui.button("EXIT", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 4), Size = UDim2.fromOffset(54, 26), TextSize = 12, BackgroundColor3 = Color3.fromHex("#7a2b2b"), Parent = banner }, Replay.stop)
	Replay.onState = function(playing, t, dur)
		banner.Visible = playing
		replayButton.Text = if playing then "STOP" else "REPLAY"
		if playing then
			bannerText.Text = string.format("SLOW-MOTION REPLAY  %.1fs / %.1fs", t, dur)
			barFill.Size = UDim2.fromScale(math.clamp(t / math.max(dur, 0.01), 0, 1), 1)
		end
	end

	-- bottom HUD
	local hud = Gui.panel({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, if mobile then -8 else -14), Size = UDim2.fromOffset(if mobile then 300 else 470, 62), Parent = screen })
	local speed = Gui.label("0", 28, { Font = T.black, Position = UDim2.fromOffset(14, 4), Size = UDim2.fromOffset(74, 34), TextXAlignment = Enum.TextXAlignment.Right, Parent = hud })
	Gui.label("MPH", 11, { TextColor3 = T.dim, Font = T.bold, Position = UDim2.fromOffset(94, 18), Size = UDim2.fromOffset(34, 14), Parent = hud })
	local nameLabel = Gui.label("", 13, { Font = T.bold, Position = UDim2.fromOffset(134, 6), Size = UDim2.new(1, -260, 0, 18), Parent = hud })
	local extra = Gui.label("", 11, { TextColor3 = T.accent, Font = T.bold, Position = UDim2.fromOffset(134, 22), Size = UDim2.new(1, -260, 0, 14), Parent = hud })
	local hint = Gui.label("", 10, { TextColor3 = T.dim, Position = UDim2.fromOffset(14, 42), Size = UDim2.new(1, -28, 0, 14), Parent = hud })
	Gui.button("RESET VEHICLE", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6), Size = UDim2.fromOffset(112, 32), TextSize = 11, BackgroundColor3 = T.accent, Parent = hud }, function()
		Audio.ui("resetScene")
		send("ResetVehicle")
	end)
	local walkHint = Gui.label(if mobile then "Tap VEHICLES to spawn · walk to a car and press Drive" else "VEHICLES to spawn · walk to a car and press E to drive · click a dummy to inspect", 11,
		{ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(460, 18), TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = T.text, TextStrokeTransparency = 0.4, Parent = screen })

	local lastModel = nil
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		local c = VehicleInput.current
		hud.Visible = c ~= nil
		walkHint.Visible = c == nil and not Replay.playing
		if c then
			speed.Text = tostring(math.floor((c.speedMph or 0) + 0.5))
			if c.model ~= lastModel then
				lastModel = c.model
				nameLabel.Text = string.upper(c.spec.display)
				hint.Text = (mobile and MOBILE_HINTS[c.kind]) or (if mobile then "Stick to drive · Jump to exit" else HINTS[c.kind])
				Camera.frameVehicle(c.model)
			end
			if c.kind == "plane" then
				extra.Text = string.format("POWER %d%%  ·  ALT %d", (c.throttle or 0) * 100, math.max(0, (c.altitude or 0) * 0.28 * 3.28))
			elseif c.kind == "heli" then
				extra.Text = string.format("ALT %d FT", math.max(0, (c.altitude or 0) * 0.28 * 3.28))
			else
				extra.Text = if c.grounded then c.spec.klass else "AIRBORNE"
			end
		else
			lastModel = nil
		end
		acc += dt
		if acc > 0.5 then
			acc = 0
			zoneLabel.Text = nearestZone()
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
	-- close menus with B / Escape-like back on gamepad
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.ButtonB and openName then
			toggle(nil)
		end
	end)
end

return UI
