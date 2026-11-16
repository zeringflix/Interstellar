--!nonstrict
-- Slow-motion instant replay.
-- Roblox has no global physics time scale, so nothing here touches the simulation. Instead the
-- client keeps a rolling buffer (last ~10 s) of the CFrames of every visible vehicle / dummy part
-- plus the impact events that happened. REPLAY plays those transforms back on anchored, non-colliding
-- local "ghost" copies at 0.25x-1x while the real objects are hidden. Ghosts cannot touch anything,
-- so playback can never deal damage or score points.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game.ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Settings = require(script.Parent.Settings)
local VehicleInput = require(script.Parent.VehicleInputController)

local Replay = {}
Replay.playing = false
Replay.speed = Config.Replay.SPEED
Replay.onEvent = nil :: ((any) -> ())?   -- UI hook: an impact record re-shown during playback
Replay.onState = nil :: ((boolean, number, number) -> ())? -- playing, time, duration

local frames = {} :: { { t: number, cf: { [BasePart]: CFrame } } }
local events = {} :: { { t: number, record: any } }
local protos = {} :: { [BasePart]: BasePart } -- visual prototype captured the first time a part is seen
local tracked = {} :: { BasePart }
local dirty = true
local KEEP = { SurfaceGui = true, Decal = true, Texture = true, SpecialMesh = true, Frame = true, UICorner = true, TextLabel = true, UIPadding = true }

local function makeProto(part: BasePart): BasePart?
	local ok, clone = pcall(function()
		return part:Clone()
	end)
	if not ok or not clone then
		return nil
	end
	for _, d in clone:GetDescendants() do
		if not KEEP[d.ClassName] then
			d:Destroy()
		end
	end
	clone.Anchored, clone.CanCollide, clone.CanQuery, clone.CanTouch = true, false, false, false
	clone.LocalTransparencyModifier = 0
	return clone
end

local function refreshTracked()
	table.clear(tracked)
	for _, name in { "Vehicles", "Dummies" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			for _, d in folder:GetDescendants() do
				if d:IsA("BasePart") and (d.Transparency < 1 or d.Name == "Root") and d.Name ~= "WheelCollider" then
					table.insert(tracked, d)
					local proto = protos[d]
					-- (re)capture once the head has its face, so ghosts are not faceless
					if not proto or (d.Name == "Head" and d:FindFirstChild("Face") and not proto:FindFirstChild("Face")) then
						protos[d] = makeProto(d) :: BasePart
					end
				end
			end
		end
	end
	dirty = false
end

local function record(now: number)
	if dirty then
		refreshTracked()
	end
	local cf = {}
	for _, p in tracked do
		if p.Parent then
			cf[p] = p.CFrame
		end
	end
	table.insert(frames, { t = now, cf = cf })
	local cutoff = now - Config.Replay.SECONDS
	while frames[1] and frames[1].t < cutoff do
		table.remove(frames, 1)
	end
	while events[1] and events[1].t < cutoff do
		table.remove(events, 1)
	end
	-- forget prototypes of parts that left the buffer entirely
	if #frames % 60 == 0 then
		for part in protos do
			if not part.Parent and not frames[1].cf[part] then
				protos[part] = nil
			end
		end
	end
end

function Replay.addEvents(records)
	local now = os.clock()
	for _, r in records do
		table.insert(events, { t = now, record = r })
	end
end

function Replay.available(): number
	return if #frames > 1 then frames[#frames].t - frames[1].t else 0
end

function Replay.stop()
	Replay.playing = false
end

function Replay.play()
	if Replay.playing or #frames < 10 then
		return
	end
	Replay.playing = true
	VehicleInput.suspended = true
	local clip, clipEvents = frames, events
	frames, events = {}, {} -- recording restarts cleanly after playback
	local t0, t1 = clip[1].t, clip[#clip].t
	local cam = workspace.CurrentCamera
	local oldSubject = cam.CameraSubject

	local ghostFolder = Instance.new("Folder")
	ghostFolder.Name = "ReplayGhosts"
	ghostFolder.Parent = cam
	local ghosts = {} :: { [BasePart]: BasePart }
	local focus: BasePart? = nil
	for part, proto in protos do
		local seen = false
		for i = 1, #clip, 8 do
			if clip[i].cf[part] then
				seen = true
				break
			end
		end
		if seen then
			local g = proto:Clone()
			g.Parent = ghostFolder
			ghosts[part] = g
			if part.Name == "Root" and (not focus or (VehicleInput.current and VehicleInput.current.model == part.Parent)) then
				focus = g
			end
		end
	end
	if not focus then
		for part, g in ghosts do
			if part.Name == "UpperTorso" then
				focus = g
				break
			end
		end
	end
	-- hide the live objects locally
	local hidden = {} :: { BasePart }
	local guis = {} :: { any }
	for _, name in { "Vehicles", "Dummies" } do
		local folder = workspace:FindFirstChild(name)
		for _, d in (if folder then folder:GetDescendants() else {}) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
				table.insert(hidden, d)
			elseif (d:IsA("SurfaceGui") or d:IsA("BillboardGui") or d:IsA("ParticleEmitter")) and d.Enabled then
				d.Enabled = false
				table.insert(guis, d)
			end
		end
	end
	if focus then
		cam.CameraSubject = focus
	end

	local t = t0
	local idx, evIdx = 1, 1
	while Replay.playing and t < t1 do
		local dt = RunService.RenderStepped:Wait()
		t += dt * Replay.speed
		while clip[idx + 1] and clip[idx + 1].t < t do
			idx += 1
		end
		local a, b = clip[idx], clip[idx + 1] or clip[idx]
		local k = if b.t > a.t then math.clamp((t - a.t) / (b.t - a.t), 0, 1) else 0
		for part, g in ghosts do
			local ca, cb = a.cf[part], b.cf[part]
			if ca and cb then
				g.CFrame = ca:Lerp(cb, k)
				g.LocalTransparencyModifier = 0
			else
				g.LocalTransparencyModifier = 1 -- did not exist at this moment
			end
		end
		while clipEvents[evIdx] and clipEvents[evIdx].t <= t do
			if Replay.onEvent then
				Replay.onEvent(clipEvents[evIdx].record)
			end
			evIdx += 1
		end
		if Replay.onState then
			Replay.onState(true, t - t0, t1 - t0)
		end
	end

	ghostFolder:Destroy()
	for _, p in hidden do
		if p.Parent then
			p.LocalTransparencyModifier = 0
		end
	end
	for _, g in guis do
		if g.Parent then
			g.Enabled = true
		end
	end
	local hum = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	cam.CameraSubject = if oldSubject and oldSubject.Parent then oldSubject else hum
	VehicleInput.suspended = false
	Replay.playing = false
	dirty = true
	if Replay.onState then
		Replay.onState(false, 0, 0)
	end
end

function Replay.init()
	for _, name in { "Vehicles", "Dummies" } do
		local folder = workspace:WaitForChild(name)
		folder.DescendantAdded:Connect(function()
			dirty = true
		end)
		folder.DescendantRemoving:Connect(function()
			dirty = true
		end)
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		if Replay.playing then
			return
		end
		acc += dt
		local hz = if Settings.get("ReplayQuality") == "High" then Config.Replay.HZ_HIGH else Config.Replay.HZ_LOW
		if acc >= 1 / hz then
			acc = 0
			record(os.clock())
		end
	end)
end

return Replay
