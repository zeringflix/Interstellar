--!nonstrict
-- Client-side dummy presentation: the animated face and the floating status label.
--
-- FACE: every dummy wears a procedurally drawn face in the style of Roblox's "Man" face
-- (flat heavy brows, half-lidded eyes, long smirk with a cheek line). It is built from Frames on a
-- SurfaceGui so it can be ANIMATED: it blinks while healthy and morphs between expressions as the
-- server-side damage state changes (attribute "Face", written only by DummyService):
--   Normal -> Surprised (the instant it is hit) -> Dizzy (staggering / tumbling) -> Hurt (damaged)
--   -> Unconscious (eyes shut) -> Dead (X eyes).
-- LABEL: BillboardGui showing "DUMMY #04 / DOWN · BLEEDING", coloured by the primary status.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game.ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Settings = require(script.Parent.Settings)

local Visuals = {}
Visuals.selected = nil :: Model?
local faces = {} :: { [Model]: any }
local INK = Color3.fromHex("#111111")
local rng = Random.new()

-- Expression parameters on a 200 x 200 canvas.
-- brow = { y, tilt (deg, + = inner end lower -> stern), raise }, lid = fraction of the eye covered,
-- pupil = scale, mouth = three control points of a quadratic curve, open = size of an open mouth.
local EXPR = {
	Normal = { browY = 62, tilt = 7, lid = 0.38, pupil = 1, mouth = { 56, 152, 112, 162, 150, 134 }, open = 0, cheek = 1 },
	Surprised = { browY = 44, tilt = -9, lid = 0, pupil = 0.6, mouth = { 84, 152, 100, 152, 116, 152 }, open = 34, cheek = 0 },
	Dizzy = { browY = 54, tilt = -14, lid = 0.15, pupil = 0.8, mouth = { 62, 150, 100, 166, 140, 146 }, open = 0, cheek = 0, spin = true, wobble = true },
	Hurt = { browY = 58, tilt = -16, lid = 0.5, pupil = 0.9, mouth = { 62, 156, 100, 138, 140, 156 }, open = 0, cheek = 0 },
	Unconscious = { browY = 60, tilt = -6, lid = 1, pupil = 1, mouth = { 78, 150, 100, 153, 122, 150 }, open = 0, cheek = 0 },
	Dead = { browY = 56, tilt = -4, lid = 0, pupil = 0, mouth = { 70, 152, 100, 150, 130, 152 }, open = 0, cheek = 0, x = true },
}
local EYE_X = { 62, 138 }
local EYE_Y, EYE_W, EYE_H = 90, 46, 22
local SEGMENTS = 8

local draw

local function frame(parent: Instance, color: Color3, round: number?): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(round, 0)
		c.Parent = f
	end
	f.Parent = parent
	return f
end

local function buildFace(model: Model)
	local head = model:WaitForChild("Head", 5) :: BasePart?
	if not head then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(200, 200)
	gui.LightInfluence = 1
	gui.Parent = head
	local f = { gui = gui, head = head, brows = {}, eyes = {}, mouth = {}, cur = table.clone(EXPR.Normal), from = nil,
		target = "Normal", t = 1, nextBlink = os.clock() + rng:NextNumber(1, 5), blink = 0 }
	f.cur.mouth = table.clone(EXPR.Normal.mouth)
	for i = 1, 2 do
		f.brows[i] = frame(gui, INK, 0.5)
		f.brows[i].Size = UDim2.fromOffset(58, 10)
		local eye = frame(gui, Color3.new(1, 1, 1), 0.45)
		eye.Size = UDim2.fromOffset(EYE_W, EYE_H)
		eye.Position = UDim2.fromOffset(EYE_X[i], EYE_Y)
		eye.ClipsDescendants = true
		local pupil = frame(eye, INK, 1)
		local lid = frame(eye, head.Color) -- upper eyelid in skin colour: this is what makes the stare half-lidded
		lid.AnchorPoint = Vector2.new(0.5, 0)
		lid.Position = UDim2.fromScale(0.5, 0)
		local line = frame(gui, INK, 0.5) -- lash line that rides the lid's lower edge
		line.Size = UDim2.fromOffset(EYE_W + 6, 5)
		local x1, x2 = frame(gui, INK, 0.5), frame(gui, INK, 0.5)
		for _, x in { x1, x2 } do
			x.Size = UDim2.fromOffset(36, 7)
			x.Position = UDim2.fromOffset(EYE_X[i], EYE_Y)
			x.Visible = false
		end
		x1.Rotation, x2.Rotation = 45, -45
		f.eyes[i] = { eye = eye, pupil = pupil, lid = lid, line = line, x = { x1, x2 } }
	end
	for i = 1, SEGMENTS do
		f.mouth[i] = frame(gui, INK, 0.5)
	end
	f.open = frame(gui, INK, 0.5)
	f.cheek = frame(gui, INK, 0.5)
	f.cheek.Size = UDim2.fromOffset(5, 44)
	f.cheek.Position = UDim2.fromOffset(166, 138)
	f.cheek.Rotation = 14
	faces[model] = f
	draw(f, os.clock())
	Visuals.setFace(model, model:GetAttribute("Face") or "Normal")
	model:GetAttributeChangedSignal("Face"):Connect(function()
		Visuals.setFace(model, model:GetAttribute("Face") or "Normal")
	end)
	return f
end

function Visuals.setFace(model: Model, name: string)
	local f = faces[model]
	if not f or not EXPR[name] or f.target == name then
		return
	end
	f.target = name
	f.from = table.clone(f.cur)
	f.from.mouth = table.clone(f.cur.mouth)
	f.t = 0
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function draw(f, now: number)
	local c, e = f.cur, EXPR[f.target]
	local lidNow = math.max(c.lid, f.blink)
	for i = 1, 2 do
		local side = if i == 1 then 1 else -1
		local brow, eye = f.brows[i], f.eyes[i]
		local wob = if e.wobble then math.sin(now * 7 + i * 2) * 3 else 0
		brow.Position = UDim2.fromOffset(EYE_X[i], c.browY + wob)
		brow.Rotation = c.tilt * side
		eye.lid.Size = UDim2.new(1, 0, lidNow, 0)
		eye.line.Position = UDim2.fromOffset(EYE_X[i], EYE_Y - EYE_H / 2 + EYE_H * lidNow)
		eye.line.Visible = not e.x or f.t < 1
		local ps = 18 * c.pupil
		eye.pupil.Size = UDim2.fromOffset(ps, ps)
		local ox, oy = 0, 2
		if e.spin then
			ox, oy = math.cos(now * 9 + i) * 9, math.sin(now * 9 + i) * 4 + 2
		end
		eye.pupil.Position = UDim2.new(0.5, ox, 0.5, oy)
		local showX = e.x and f.t >= 0.5
		eye.eye.Visible = not showX
		eye.line.Visible = not showX
		eye.x[1].Visible, eye.x[2].Visible = showX, showX
	end
	local m = c.mouth
	local wave = if e.wobble then math.sin(now * 6) * 5 else 0
	local px, py
	for i = 0, SEGMENTS do
		local t = i / SEGMENTS
		local a, b = (1 - t) * (1 - t), 2 * (1 - t) * t
		local x = a * m[1] + b * m[3] + t * t * m[5]
		local y = a * m[2] + b * (m[4] + wave) + t * t * m[6]
		if i > 0 then
			local seg = f.mouth[i]
			local dx, dy = x - px, y - py
			seg.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + 5, 6)
			seg.Position = UDim2.fromOffset((x + px) / 2, (y + py) / 2)
			seg.Rotation = math.deg(math.atan2(dy, dx))
			seg.Visible = c.open < 12
		end
		px, py = x, y
	end
	f.open.Visible = c.open >= 4
	f.open.Size = UDim2.fromOffset(c.open * 0.85, c.open)
	f.open.Position = UDim2.fromOffset(100, 152)
	f.cheek.BackgroundTransparency = 1 - c.cheek
end

local function stepFace(f, dt: number, now: number)
	local e = EXPR[f.target]
	local animating = false
	if f.t < 1 then
		f.t = math.min(1, f.t + dt / (if f.target == "Surprised" then 0.08 else 0.28))
		local k = 1 - (1 - f.t) ^ 3
		for _, key in { "browY", "tilt", "lid", "pupil", "open", "cheek" } do
			f.cur[key] = lerp(f.from[key], e[key], k)
		end
		for i = 1, 6 do
			f.cur.mouth[i] = lerp(f.from.mouth[i], e.mouth[i], k)
		end
		animating = true
	end
	-- blinking only while the eyes are open and the dummy is calm
	if f.target == "Normal" or f.target == "Hurt" then
		if now >= f.nextBlink then
			local phase = (now - f.nextBlink) / 0.16
			if phase >= 1 then
				f.blink = 0
				f.nextBlink = now + rng:NextNumber(2, 6)
			else
				f.blink = math.sin(phase * math.pi)
			end
			animating = true
		end
	else
		f.blink = 0
	end
	if animating or e.spin or e.wobble then
		draw(f, now)
	end
end

-- Labels ---------------------------------------------------------------------------
local labels = {} :: { [Model]: { gui: BillboardGui, name: TextLabel, status: TextLabel } }

local function buildLabel(model: Model)
	local head = model:WaitForChild("Head", 5) :: BasePart?
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "StatusLabel"
	gui.Adornee = head
	gui.Size = UDim2.fromScale(9, 2.1)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.3, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 150
	gui.Parent = head
	local function text(y: number, h: number, bold: boolean): TextLabel
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, h)
		t.Position = UDim2.fromScale(0, y)
		t.TextScaled = true
		t.Font = if bold then Enum.Font.GothamBlack else Enum.Font.GothamBold
		t.TextColor3 = Color3.new(1, 1, 1)
		t.TextStrokeTransparency = 0.15
		t.TextStrokeColor3 = Color3.fromHex("#15171c")
		t.Parent = gui
		return t
	end
	local l = { gui = gui, name = text(0, 0.42, false), status = text(0.42, 0.58, true) }
	labels[model] = l
	local function refresh()
		l.name.Text = string.format("%s #%02d", model:GetAttribute("Display") or "DUMMY", model:GetAttribute("DummyId") or 0)
		l.status.Text = model:GetAttribute("Status") or "HEALTHY"
		l.status.TextColor3 = Color3.fromHex(Config.StatusColors[model:GetAttribute("StatusPrimary") or "HEALTHY"] or "#ffffff")
	end
	refresh()
	model:GetAttributeChangedSignal("Status"):Connect(refresh)
end

local function declutter()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local show = Settings.get("StatusText")
	local range = if Settings.get("Graphics") == "Low" then 90 else 150
	local list = {}
	for model, l in labels do
		l.gui.MaxDistance = range
		local head = l.gui.Adornee :: BasePart?
		if not show or not head then
			l.gui.Enabled = false
			continue
		end
		local sp, onScreen = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 2.3, 0))
		if onScreen then
			table.insert(list, { l = l, x = sp.X, y = sp.Y, d = if model == Visuals.selected then -1 else sp.Z })
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	local kept = {}
	for _, it in list do
		local ok = true
		for _, k in kept do
			if math.abs(k.x - it.x) < 70 and math.abs(k.y - it.y) < 30 then
				ok = false
				break
			end
		end
		it.l.gui.Enabled = ok
		if ok then
			table.insert(kept, it)
		end
	end
end

-- Selection highlight -------------------------------------------------------------------
local highlight: Highlight
function Visuals.select(model: Model?)
	Visuals.selected = model
	highlight.Adornee = model
	highlight.Enabled = model ~= nil
end

function Visuals.init()
	highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromHex("#3b8cff")
	highlight.Enabled = false
	highlight.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local folder = workspace:WaitForChild("Dummies")
	local function add(model: Instance)
		if model:IsA("Model") then
			task.spawn(buildFace, model)
			task.spawn(buildLabel, model)
		end
	end
	folder.ChildAdded:Connect(add)
	folder.ChildRemoved:Connect(function(model)
		faces[model :: Model] = nil
		labels[model :: Model] = nil
		if Visuals.selected == model then
			Visuals.select(nil)
		end
	end)
	for _, m in folder:GetChildren() do
		add(m)
	end
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local cam = workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or Vector3.zero
		for _, f in faces do
			-- faces far from the camera are not worth animating
			if f.t < 1 or (f.head.Position - camPos).Magnitude < 160 then
				stepFace(f, dt, now)
			end
		end
		acc += dt
		if acc > 0.2 then
			acc = 0
			declutter()
		end
	end)
end

return Visuals
