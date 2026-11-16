--!nonstrict
-- The damage read-out: ONE small two-line text bar at the bottom of the screen (no cards, no stack).
--   line 1 (small, coloured):  where the dummy was hit            e.g.  Left Knee
--   line 2 (white):            at most THREE facts joined by " · "  e.g.  Leg broken · Down · 82% blood left
-- A pile-up collapses to "7 dummies hit" / "3 down · 2 knocked out · 1 dead".
-- Every individual record still goes to Feed.log (shown in the Crash Report window).
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Gui = require(script.Parent.Gui)
local Settings = require(script.Parent.Settings)
local Audio = require(script.Parent.AudioController)
local Visuals = require(script.Parent.DummyVisuals)

local Feed = {}
Feed.log = {} :: { any } -- newest first, max 60
local bar: Frame
local top, bottom: TextLabel
local shownUntil = 0
local SEV_COLOR = { LIGHT = "#ffe08a", MEDIUM = "#ffb36b", HEAVY = "#ff8a8a", CRITICAL = "#ff5a5a" }

local function bloodText(blood: number?): string?
	if blood and Settings.get("BloodText") then
		return string.format("%d%% blood left", blood)
	end
	return nil
end

local function present(line1: string, color: string, items: { string })
	if not Settings.get("Notifications") then
		return
	end
	while #items > 3 do -- never more than three things on the bar
		table.remove(items)
	end
	top.Text = line1
	top.TextColor3 = Color3.fromHex(color)
	bottom.Text = table.concat(items, " · ")
	bar.Visible = true
	shownUntil = os.clock() + 4.5
	local scale = bar:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 0.86
	TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
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
	local ids, count, last = {}, 0, nil
	for _, r in records do
		if not ids[r.id] then
			count += 1
		end
		ids[r.id] = r
		last = r
	end
	if not last then
		return
	end
	Audio.ui("hitNotify", 0.22)
	local prefix = if replay then "REPLAY · " else ""
	if count > 1 then
		local tally, order = {}, {}
		for _, r in ids do
			local c = string.lower(r.condition or "hit")
			if not tally[c] then
				tally[c] = 0
				table.insert(order, c)
			end
			tally[c] += 1
		end
		table.sort(order, function(a, b)
			return tally[a] > tally[b]
		end)
		local items = {}
		for _, c in order do
			table.insert(items, string.format("%d %s", tally[c], c))
		end
		present(string.format("%s%d dummies hit", prefix, count), "#ffd24a", items)
		return
	end
	local r = last
	local items = { r.injury or (r.region .. " hit"), r.condition or r.status }
	if not r.dead then
		table.insert(items, if r.bleeding or (r.blood or 100) < 100 then (bloodText(r.blood) or string.format("-%d health", r.damage))
			else string.format("-%d health", r.damage))
	end
	present(prefix .. (r.part or r.region), SEV_COLOR[r.severity] or "#ff8a8a", items)
end

function Feed.init(screen: ScreenGui, mobile: boolean)
	bar = Gui.make("Frame", { Name = "DamageBar", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, if mobile then -64 else -104), Size = UDim2.fromOffset(if mobile then 430 else 620, 46), Visible = false, Parent = screen },
		{ Gui.make("UIScale", {}) })
	top = Gui.label("", if mobile then 14 else 17, { Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, Parent = bar })
	bottom = Gui.label("", if mobile then 16 else 21, { Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Center, Parent = bar })
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		if os.clock() < shownUntil then
			return
		end
		-- idle: show the selected dummy's live condition, otherwise hide
		local m = Visuals.selected
		if m and m.Parent and Settings.get("Notifications") then
			top.Text = string.format("%s #%02d", m:GetAttribute("Display") or "DUMMY", m:GetAttribute("DummyId") or 0)
			top.TextColor3 = Color3.fromHex("#9fd0ff")
			local items = { m:GetAttribute("Condition") or "Unhurt", string.format("%d health", m:GetAttribute("Health") or 0) }
			local b = bloodText(m:GetAttribute("Blood"))
			if b then
				table.insert(items, b)
			end
			bottom.Text = table.concat(items, " · ")
			bar.Visible = true
		else
			bar.Visible = false
		end
	end)
end

return Feed
