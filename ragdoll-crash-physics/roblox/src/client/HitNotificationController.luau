--!nonstrict
-- The impact feed on the right edge: what was hit, how hard, health lost and the new status.
-- A pile-up (more than 3 dummies in one burst) is collapsed into a single summary card; every
-- individual record still goes to the event log (shown in the Crash Report panel).
local TweenService = game:GetService("TweenService")
local Shared = game.ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Gui = require(script.Parent.Gui)
local Settings = require(script.Parent.Settings)
local Audio = require(script.Parent.AudioController)

local Feed = {}
Feed.log = {} :: { any } -- newest first, max 60
local holder: Frame
local order = 0
local collapsed = false
local SEV_TEXT = { LIGHT = "LIGHT IMPACT", MEDIUM = "IMPACT", HEAVY = "HEAVY IMPACT", CRITICAL = "CRITICAL IMPACT" }
local SEV_COLOR = { LIGHT = Gui.T.dim, MEDIUM = Gui.T.warn, HEAVY = Color3.fromHex("#ff8a3c"), CRITICAL = Gui.T.bad }

local function statusColor(status: string): Color3
	local primary = string.split(status, " · ")[1]
	return Color3.fromHex(Config.StatusColors[primary] or "#ffffff")
end

local function card(lines: { { text: string, size: number, color: Color3, font: Enum.Font? } }, accent: Color3)
	if not Settings.get("Notifications") or collapsed then
		return
	end
	order -= 1
	local height = 12
	for _, l in lines do
		height += l.size + 4
	end
	local f = Gui.panel({ Size = UDim2.new(1, 0, 0, height), LayoutOrder = order, Parent = holder })
	Gui.make("Frame", { Size = UDim2.new(0, 4, 1, -12), Position = UDim2.fromOffset(6, 6), BackgroundColor3 = accent, Parent = f }, { Gui.corner(2) })
	local y = 6
	for _, l in lines do
		Gui.label(l.text, l.size, { Position = UDim2.fromOffset(18, y), Size = UDim2.new(1, -24, 0, l.size + 4),
			TextColor3 = l.color, Font = l.font or Gui.T.bold, Parent = f })
		y += l.size + 4
	end
	local scale = Gui.make("UIScale", { Scale = 0.6, Parent = f })
	TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	Audio.ui("hitNotify", 0.25)
	-- keep the newest five
	local cards = {}
	for _, c in holder:GetChildren() do
		if c:IsA("Frame") then
			table.insert(cards, c)
		end
	end
	table.sort(cards, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 6, #cards do
		cards[i]:Destroy()
	end
	task.delay(4.5, function()
		if f.Parent then
			local t = TweenService:Create(scale, TweenInfo.new(0.25), { Scale = 0 })
			t:Play()
			t.Completed:Wait()
			f:Destroy()
		end
	end)
end

function Feed.show(records, replay: boolean?)
	if not replay then
		for _, r in records do
			table.insert(Feed.log, 1, r)
		end
		while #Feed.log > 60 do
			table.remove(Feed.log)
		end
	end
	local tag = if replay then "REPLAY · " else ""
	if #records > 3 then
		local counts, orderSeen = {}, {}
		local ids = {}
		for _, r in records do
			if not ids[r.id] then
				ids[r.id] = true
				local primary = string.split(r.status, " · ")[1]
				if not counts[primary] then
					counts[primary] = 0
					table.insert(orderSeen, primary)
				end
				counts[primary] += 1
			end
		end
		local n = 0
		for _ in ids do
			n += 1
		end
		local lines = { { text = string.format("%s%d DUMMIES HIT!", tag, n), size = 17, color = Gui.T.text, font = Gui.T.black } }
		for _, primary in orderSeen do
			table.insert(lines, { text = string.format("%d %s", counts[primary], primary), size = 13,
				color = Color3.fromHex(Config.StatusColors[primary] or "#ffffff") })
		end
		card(lines, Gui.T.accent)
		return
	end
	for _, r in records do
		local detail = SEV_TEXT[r.severity]
		if r.damage > 0 then
			detail = string.format("-%d HEALTH · %s", r.damage, detail)
		end
		card({
			{ text = string.format("%s%s #%02d  ·  %s", tag, r.display, r.id, string.upper(r.source)), size = 11, color = Gui.T.dim },
			{ text = r.region .. " HIT!", size = 17, color = Gui.T.text, font = Gui.T.black },
			{ text = detail, size = 12, color = SEV_COLOR[r.severity] },
			{ text = r.status, size = 14, color = statusColor(r.status), font = Gui.T.black },
		}, statusColor(r.status))
	end
end

function Feed.init(screen: ScreenGui, mobile: boolean)
	local width = if mobile then 190 else 250
	local root = Gui.make("Frame", { Name = "ImpactFeed", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 64), Size = UDim2.new(0, width, 0.5, 0), Parent = screen })
	local header = Gui.button("IMPACTS  ▾", { Size = UDim2.new(1, 0, 0, 26), TextSize = 12, TextColor3 = Gui.T.dim, Parent = root })
	holder = Gui.make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 1, -32), Parent = root },
		{ Gui.list(6) })
	header.Activated:Connect(function() -- collapsible, mainly for small screens
		collapsed = not collapsed
		holder.Visible = not collapsed
		header.Text = if collapsed then "IMPACTS  ▸" else "IMPACTS  ▾"
	end)
end

return Feed
