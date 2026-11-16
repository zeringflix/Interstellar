--!nonstrict
-- Tiny UI toolkit + the crash-test control-panel theme (charcoal panels, light text, blue accents).
local Gui = {}

Gui.T = {
	panel = Color3.fromHex("#1c1f26"), panel2 = Color3.fromHex("#272b34"), stroke = Color3.fromHex("#3a3f4b"),
	text = Color3.fromHex("#eef1f6"), dim = Color3.fromHex("#9aa3b2"), accent = Color3.fromHex("#3b8cff"),
	good = Color3.fromHex("#4cd787"), warn = Color3.fromHex("#ffb84d"), bad = Color3.fromHex("#ff5a5a"),
	font = Enum.Font.GothamMedium, bold = Enum.Font.GothamBold, black = Enum.Font.GothamBlack,
}

function Gui.make(class: string, props: { [any]: any }?, children: { Instance }?): any
	local inst = Instance.new(class)
	if class == "Frame" or class == "TextButton" or class == "TextLabel" or class == "ScrollingFrame" or class == "ImageButton" then
		(inst :: any).BorderSizePixel = 0
	end
	if class == "TextButton" then
		(inst :: any).AutoButtonColor = true
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
	return Gui.make("UIStroke", { Color = color or Gui.T.stroke, Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
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

function Gui.label(text: string, size: number, props: { [any]: any }?): TextLabel
	local l = Gui.make("TextLabel", {
		Text = text, TextSize = size, Font = Gui.T.font, TextColor3 = Gui.T.text, BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, size + 6), TextTruncate = Enum.TextTruncate.AtEnd,
	})
	for k, v in props or {} do
		(l :: any)[k] = v
	end
	return l
end

function Gui.button(text: string, props: { [any]: any }?, onClick: (() -> ())?): TextButton
	local b = Gui.make("TextButton", {
		Text = text, TextSize = 15, Font = Gui.T.bold, TextColor3 = Gui.T.text, BackgroundColor3 = Gui.T.panel2,
		Size = UDim2.new(1, 0, 0, 40),
	}, { Gui.corner(8), Gui.stroke() })
	for k, v in props or {} do
		(b :: any)[k] = v
	end
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

function Gui.panel(props: { [any]: any }?, children: { Instance }?): Frame
	local f = Gui.make("Frame", { BackgroundColor3 = Gui.T.panel, BackgroundTransparency = 0.06 }, { Gui.corner(12), Gui.stroke() })
	for k, v in props or {} do
		(f :: any)[k] = v
	end
	for _, c in children or {} do
		c.Parent = f
	end
	return f
end

return Gui
