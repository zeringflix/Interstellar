--!nonstrict
-- Click / tap a dummy to inspect it. Everything shown is read from attributes that only the
-- server writes (DummyService.publish), so the panel can never disagree with the simulation.
local RunService = game:GetService("RunService")
local Shared = game.ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local DamageModel = require(Shared.DamageModel)
local Gui = require(script.Parent.Gui)
local Visuals = require(script.Parent.DummyVisuals)
local Camera = require(script.Parent.CameraController)
local Audio = require(script.Parent.AudioController)

local Inspect = {}
local panel: Frame
local title, statusL, healthL, lastL: TextLabel
local healthFill: Frame
local rows = {} :: { [string]: TextLabel }
local scan = {} :: { [string]: Frame }
local request: RemoteEvent

local function condColor(cond: number): Color3
	if cond >= 85 then
		return Color3.fromHex("#4cd787")
	elseif cond >= 60 then
		return Color3.fromHex("#d6e04a")
	elseif cond >= 35 then
		return Color3.fromHex("#ffb84d")
	elseif cond > 10 then
		return Color3.fromHex("#ff7a45")
	end
	return Color3.fromHex("#b03a3a")
end

local function refresh()
	local m = Visuals.selected
	if not m or not m.Parent then
		panel.Visible = false
		return
	end
	panel.Visible = true
	local t = Config.DummyTypes[m:GetAttribute("DummyType")] or Config.DummyTypes.Noob
	local status = m:GetAttribute("Status") or "HEALTHY"
	title.Text = string.format("%s #%02d", m:GetAttribute("Display") or "DUMMY", m:GetAttribute("DummyId") or 0)
	statusL.Text = "Status: " .. status
	statusL.TextColor3 = Color3.fromHex(Config.StatusColors[m:GetAttribute("StatusPrimary") or "HEALTHY"] or "#ffffff")
	local hp = m:GetAttribute("Health") or 0
	healthL.Text = string.format("Health: %d / %d", hp, t.health)
	healthFill.Size = UDim2.fromScale(math.clamp(hp / t.health, 0, 1), 1)
	healthFill.BackgroundColor3 = condColor(hp / t.health * 100)
	for _, r in DamageModel.REGIONS do
		local cond = m:GetAttribute("Cond" .. r) or 100
		rows[r].Text = string.format("%s: %s", string.gsub(DamageModel.REGION_LABEL[r], "(%a)(%a*)", function(a, b)
			return a .. string.lower(b)
		end), DamageModel.regionLabel(cond / 100))
		rows[r].TextColor3 = if cond >= 85 then Gui.T.dim else condColor(cond)
		scan[r].BackgroundColor3 = condColor(cond)
	end
	local src = m:GetAttribute("LastSource")
	lastL.Text = if src and src ~= "" then string.format("Last Impact: %s\nLast Impact Speed: %d MPH", src, m:GetAttribute("LastSpeedMph") or 0)
		else "Last Impact: none"
end

function Inspect.select(model: Model?)
	Visuals.select(model)
	if model then
		Audio.ui("uiSelect", 0.4)
	end
	refresh()
end

function Inspect.init(screen: ScreenGui, mobile: boolean, remotes: Instance)
	request = remotes:WaitForChild("Request") :: RemoteEvent
	local w = if mobile then 210 else 250
	panel = Gui.panel({ Name = "Inspection", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, if mobile then -150 else -16),
		Size = UDim2.fromOffset(w, 372), Visible = false, Parent = screen }, { Gui.padding(12) })
	title = Gui.label("DUMMY", 17, { Font = Gui.T.black, Parent = panel })
	Gui.button("✕", { Size = UDim2.fromOffset(26, 26), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, -2), Parent = panel }, function()
		Inspect.select(nil)
	end)
	statusL = Gui.label("", 14, { Position = UDim2.fromOffset(0, 26), Font = Gui.T.bold, Parent = panel })
	healthL = Gui.label("", 13, { Position = UDim2.fromOffset(0, 48), Parent = panel })
	local bar = Gui.make("Frame", { Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 8), BackgroundColor3 = Gui.T.panel2, Parent = panel }, { Gui.corner(4) })
	healthFill = Gui.make("Frame", { Size = UDim2.fromScale(1, 1), Parent = bar }, { Gui.corner(4) })

	-- Body scan: a tiny blocky dummy whose parts take the colour of each region's condition.
	local body = Gui.make("Frame", { Position = UDim2.fromOffset(0, 88), Size = UDim2.fromOffset(74, 118), BackgroundTransparency = 1, Parent = panel })
	local function blockPart(name: string, x: number, y: number, sx: number, sy: number)
		scan[name] = Gui.make("Frame", { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(sx, sy), Parent = body }, { Gui.corner(3), Gui.stroke(Gui.T.panel, 1) })
	end
	blockPart("Head", 24, 0, 26, 24)
	blockPart("Torso", 18, 26, 38, 42)
	blockPart("RightArm", 0, 26, 16, 42) -- the dummy faces the viewer, so its right arm is on our left
	blockPart("LeftArm", 58, 26, 16, 42)
	blockPart("RightLeg", 18, 70, 18, 44)
	blockPart("LeftLeg", 38, 70, 18, 44)
	local list = Gui.make("Frame", { Position = UDim2.fromOffset(84, 88), Size = UDim2.new(1, -84, 0, 118), BackgroundTransparency = 1, Parent = panel }, { Gui.list(1) })
	for _, r in DamageModel.REGIONS do
		rows[r] = Gui.label("", 11, { Size = UDim2.new(1, 0, 0, 18), TextWrapped = true, Parent = list })
	end
	lastL = Gui.label("", 12, { Position = UDim2.fromOffset(0, 212), Size = UDim2.new(1, 0, 0, 34), TextColor3 = Gui.T.dim,
		TextYAlignment = Enum.TextYAlignment.Top, Parent = panel })

	local grid = Gui.make("Frame", { Position = UDim2.fromOffset(0, 254), Size = UDim2.new(1, 0, 0, 92), BackgroundTransparency = 1, Parent = panel },
		{ Gui.make("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 42), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local function action(text: string, color: Color3, i: number, fn: () -> ())
		Gui.button(text, { LayoutOrder = i, TextSize = 13, BackgroundColor3 = color, Parent = grid }, function()
			Audio.ui("uiClick")
			fn()
		end)
	end
	local function send(what: string)
		local m = Visuals.selected
		if m then
			request:FireServer("DummyAction", m:GetAttribute("DummyId"), what)
		end
	end
	action("REVIVE", Color3.fromHex("#1f7a4d"), 1, function()
		send("Revive")
	end)
	action("RESET", Gui.T.panel2, 2, function()
		send("Reset")
		Inspect.select(nil)
	end)
	action("DELETE", Color3.fromHex("#7a2b2b"), 3, function()
		Audio.ui("uiDelete")
		send("Delete")
		Inspect.select(nil)
	end)
	action("FOLLOW CAMERA", Color3.fromHex("#245a9c"), 4, function()
		local m = Visuals.selected
		if Camera.mode == "Dummy" then
			Camera.setMode("Vehicle")
		elseif m and m:FindFirstChild("UpperTorso") then
			Camera.setMode("Dummy", m.UpperTorso)
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc > 0.15 then
			acc = 0
			if panel.Visible or Visuals.selected then
				refresh()
			end
		end
	end)
end

return Inspect
