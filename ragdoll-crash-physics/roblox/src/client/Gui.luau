--!nonstrict
-- UI toolkit + theme. The look follows the reference sandbox UI the game is modelled on: chunky
-- dark panels with a thick navy outline, a coloured gradient header with a red X, rounded bold
-- white lettering with a black outline, green ON / red OFF pills.
-- Icons: every icon is looked up in UIAssets first (image ids from your uploaded icon pack);
-- when a slot is empty a simple vector glyph drawn from Frames is used instead, so the UI is
-- complete out of the box and upgrades itself the moment ids are filled in.
local UIAssets = require(script.Parent.UIAssets)

local Gui = {}

Gui.T = {
	panel = Color3.fromHex("#1a2130"), panel2 = Color3.fromHex("#2a3346"), stroke = Color3.fromHex("#0c111c"),
	text = Color3.fromHex("#ffffff"), dim = Color3.fromHex("#b9c2d3"), accent = Color3.fromHex("#2f9bff"),
	good = Color3.fromHex("#35d24a"), warn = Color3.fromHex("#ffb52e"), bad = Color3.fromHex("#f0333d"),
	font = Enum.Font.FredokaOne, bold = Enum.Font.FredokaOne, black = Enum.Font.FredokaOne,
	headers = { green = { "#3cff55", "#12b53a" }, red = { "#ff3d74", "#d41247" }, blue = { "#48c6ff", "#1f8fe8" },
		purple = { "#b06bff", "#7a2de0" }, orange = { "#ffb02e", "#f07a12" }, grey = { "#5b6578", "#3a4254" } },
}
local T = Gui.T

function Gui.make(class: string, props: { [any]: any }?, children: { Instance }?): any
	local inst = Instance.new(class)
	if inst:IsA("GuiObject") then
		(inst :: any).BorderSizePixel = 0
	end
	local parent
	for k, v in props or {} do
		if k == "Parent" then
			parent = v
		else
			(inst :: any)[k] = v
		end
	end
	for _, c in children or {} do
		c.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Gui.corner(r: number): UICorner
	return Gui.make("UICorner", { CornerRadius = UDim.new(0, r) })
end

function Gui.stroke(color: Color3?, thickness: number?): UIStroke
	return Gui.make("UIStroke", { Color = color or T.stroke, Thickness = thickness or 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

function Gui.padding(p: number): UIPadding
	local u = UDim.new(0, p)
	return Gui.make("UIPadding", { PaddingLeft = u, PaddingRight = u, PaddingTop = u, PaddingBottom = u })
end

function Gui.list(gap: number, horizontal: boolean?, align: Enum.HorizontalAlignment?): UIListLayout
	return Gui.make("UIListLayout", {
		Padding = UDim.new(0, gap), SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
	})
end

function Gui.gradient(top: string, bottom: string): UIGradient
	return Gui.make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromHex(top), Color3.fromHex(bottom)) })
end

-- outlined game lettering
function Gui.label(text: string, size: number, props: { [any]: any }?): TextLabel
	local l = Gui.make("TextLabel", {
		Text = text, TextSize = size, Font = T.font, TextColor3 = T.text, BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, size + 6), TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local outline = Gui.make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = math.clamp(size / 9, 1, 3), Parent = l })
	for k, v in props or {} do
		if k == "NoOutline" then
			outline:Destroy()
		else
			(l :: any)[k] = v
		end
	end
	return l
end

function Gui.button(text: string, props: { [any]: any }?, onClick: (() -> ())?): TextButton
	local b = Gui.make("TextButton", {
		Text = "", BackgroundColor3 = T.panel2, Size = UDim2.new(1, 0, 0, 40), AutoButtonColor = true,
	}, { Gui.corner(8), Gui.stroke(T.stroke, 3) })
	local caption = Gui.label(text, 15, { Name = "Caption", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Parent = b })
	for k, v in props or {} do
		if k == "TextSize" or k == "TextColor3" or k == "Font" then
			(caption :: any)[k] = v
		elseif k == "Text" then
			caption.Text = v
		else
			(b :: any)[k] = v
		end
	end
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

function Gui.setText(button: TextButton, text: string)
	local c = button:FindFirstChild("Caption")
	if c then
		(c :: TextLabel).Text = text
	end
end

-- green / red pill used for every ON / OFF and action button
function Gui.pill(text: string, color: string, props: { [any]: any }?, onClick: (() -> ())?): TextButton
	local g = T.headers[color] or T.headers.grey
	local b = Gui.button(text, props, onClick)
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	Gui.gradient(g[1], g[2]).Parent = b
	b:SetAttribute("Pill", color)
	return b
end

function Gui.recolor(pill: TextButton, color: string)
	local g = T.headers[color] or T.headers.grey
	local grad = pill:FindFirstChildOfClass("UIGradient")
	if grad then
		grad.Color = ColorSequence.new(Color3.fromHex(g[1]), Color3.fromHex(g[2]))
	end
end

function Gui.panel(props: { [any]: any }?, children: { Instance }?): Frame
	local f = Gui.make("Frame", { BackgroundColor3 = T.panel, BackgroundTransparency = 0.22 }, { Gui.corner(6), Gui.stroke(T.stroke, 4) })
	for k, v in props or {} do
		(f :: any)[k] = v
	end
	for _, c in children or {} do
		c.Parent = f
	end
	return f
end

-- Vector glyphs drawn from Frames on a 24 x 24 grid: { x, y, w, h, corner, rotation? }
local GLYPHS = {
	shop = { { 2, 5, 4, 2, 1 }, { 5, 6, 3, 9, 1, -14 }, { 6, 8, 15, 8, 2 }, { 8, 19, 4, 4, 2 }, { 16, 19, 4, 4, 2 } },
	car = { { 2, 11, 20, 6, 2 }, { 6, 6, 11, 6, 2 }, { 4, 15, 5, 5, 3 }, { 15, 15, 5, 5, 3 } },
	sandbox = { { 3, 3, 8, 8, 2 }, { 13, 3, 8, 8, 2 }, { 3, 13, 8, 8, 2 }, { 13, 13, 8, 8, 2 } },
	gear = { { 6, 6, 12, 12, 6 }, { 10, 2, 4, 20, 1 }, { 2, 10, 20, 4, 1 }, { 10, 2, 4, 20, 1, 45 }, { 10, 2, 4, 20, 1, -45 } },
	dummy = { { 7, 2, 10, 9, 3 }, { 5, 12, 14, 10, 2 } },
	pad = { { 2, 8, 20, 10, 5 }, { 3, 14, 6, 7, 3 }, { 15, 14, 6, 7, 3 } },
	replay = { { 5, 4, 4, 16, 1 }, { 10, 8, 8, 8, 1, 45 } },
	revive = { { 10, 3, 4, 18, 1 }, { 3, 10, 18, 4, 1 } },
	reset = { { 4, 4, 16, 16, 8 }, { 14, 2, 8, 8, 1 } },
}
local HOLES = { gear = { 9, 9, 6, 6, 3 }, reset = { 8, 8, 8, 8, 4 } }

function Gui.icon(name: string, size: number, color: Color3?, parent: Instance?): GuiObject
	local id = UIAssets.Icons[name]
	if id and id ~= "" then
		return Gui.make("ImageLabel", { Name = "Icon", Image = id, BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), ScaleType = Enum.ScaleType.Fit, Parent = parent })
	end
	local holder = Gui.make("Frame", { Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), Parent = parent })
	local k = size / 24
	local function piece(g, c: Color3)
		local f = Gui.make("Frame", { BackgroundColor3 = c, AnchorPoint = Vector2.new(0.5, 0.5), Rotation = g[6] or 0,
			Position = UDim2.fromOffset((g[1] + g[3] / 2) * k, (g[2] + g[4] / 2) * k), Size = UDim2.fromOffset(g[3] * k, g[4] * k), Parent = holder })
		Gui.corner(g[5] * k).Parent = f
	end
	for _, g in GLYPHS[name] or GLYPHS.sandbox do
		piece(g, color or T.text)
	end
	if HOLES[name] then
		piece(HOLES[name], T.panel)
	end
	return holder
end

-- window with coloured header + red X. Returns (window, scrolling body).
function Gui.window(title: string, color: string, iconName: string?, onClose: (() -> ())?): (Frame, ScrollingFrame)
	local g = T.headers[color] or T.headers.grey
	local w = Gui.panel({ ClipsDescendants = false })
	local header = Gui.make("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Color3.new(1, 1, 1), Parent = w },
		{ Gui.gradient(g[1], g[2]), Gui.corner(6), Gui.stroke(T.stroke, 4) })
	local x = 12
	if iconName then
		local ic = Gui.icon(iconName, 28, nil, header)
		ic.Position = UDim2.fromOffset(10, 8)
		x = 46
	end
	Gui.label(title, 24, { Name = "Title", Position = UDim2.fromOffset(x, 0), Size = UDim2.new(1, -x - 56, 1, 0), Parent = header })
	local close = Gui.pill("X", "red", { Size = UDim2.fromOffset(44, 44), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), TextSize = 24, Parent = header }, onClose)
	close.Name = "Close"
	local body = Gui.make("ScrollingFrame", { Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 54), Size = UDim2.new(1, -24, 1, -64),
		ScrollBarThickness = 6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarImageColor3 = T.dim, Parent = w })
	return w, body
end

return Gui
