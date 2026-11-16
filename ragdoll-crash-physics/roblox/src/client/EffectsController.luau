--!nonstrict
-- Visual + audio feedback for verified events sent by the server. Kid-friendly by design:
-- cartoon stars, dust puffs and sparks only - no blood, wounds or gore of any kind.
local Shared = game.ReplicatedStorage:WaitForChild("Shared")
local Settings = require(script.Parent.Settings)
local Audio = require(script.Parent.AudioController)
local Camera = require(script.Parent.CameraController)

local Effects = {}
local STAR = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function density(): number
	local g = Settings.get("Graphics")
	return if not Settings.get("ImpactEffects") then 0 elseif g == "Low" then 0.4 elseif g == "Medium" then 0.7 else 1
end

local function burst(position: Vector3, texture: string, color: Color3, count: number, speed: number, size: number, life: number)
	local n = math.floor(count * density() + 0.5)
	if n <= 0 then
		return
	end
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = workspace.Terrain
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 0.2) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(life * 0.6, life)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 3
	e.Rate = 0
	e.LightEmission = if texture == STAR then 0.8 else 0
	e.Parent = att
	e:Emit(n)
	game:GetService("Debris"):AddItem(att, life + 0.5)
end

local SEV = { LIGHT = 1, MEDIUM = 2, HEAVY = 3, CRITICAL = 4 }

function Effects.onImpacts(records)
	for i, r in records do
		if i > 8 then
			break
		end
		local s = SEV[r.severity] or 1
		if r.source == "Hard Landing" then
			Audio.at("bodyFall", r.position, 0.5)
			burst(r.position, SMOKE, Color3.fromRGB(215, 205, 190), 6, 8, 2.5, 0.7)
		else
			Audio.at(if s >= 3 then "bodyHeavy" elseif s == 2 then "bodyMedium" else "bodyLight", r.position, 0.45 + s * 0.12)
			burst(r.position, STAR, Color3.fromRGB(255, 226, 90), 4 + s * 5, 14 + s * 6, 1.6, 0.55)
			if s >= 2 then
				burst(r.position, SMOKE, Color3.fromRGB(225, 220, 210), 4 + s * 2, 9, 3, 0.8)
			end
			if s >= 3 and not r.chain then
				Camera.shake(0.25 + (s - 3) * 0.3)
			end
		end
	end
end

function Effects.onVehicleCrash(vehicle: Model, dv: number, position: Vector3)
	local name = if dv > 80 then "crashHeavy" elseif dv > 45 then "crashMedium" else "crashLight"
	Audio.at(name, position, math.clamp(0.45 + dv / 160, 0.45, 1), 1, 0.15)
	if dv > 60 then
		Audio.at("glass", position, 0.5, 1, 0.5)
	end
	if dv > 95 then
		Audio.at("debris", position, 0.5, 1, 1)
	end
	burst(position, STAR, Color3.fromRGB(255, 190, 80), math.clamp(dv / 5, 4, 30), 30, 1.2, 0.4) -- cartoon sparks
	burst(position, SMOKE, Color3.fromRGB(200, 200, 200), math.clamp(dv / 10, 2, 12), 12, 4, 1)
	Camera.shake(math.clamp(dv / 110, 0.15, 1))
end

local function watchVehicle(model: Model)
	model:GetAttributeChangedSignal("DamageLevel"):Connect(function()
		local level = model:GetAttribute("DamageLevel") or 0
		local hood = model:FindFirstChild("Hood") or model.PrimaryPart
		if level >= 2 and hood and not hood:FindFirstChild("DamageSmoke") and density() > 0 then
			local e = Instance.new("ParticleEmitter")
			e.Name = "DamageSmoke"
			e.Texture = SMOKE
			e.Color = ColorSequence.new(Color3.fromRGB(90, 90, 95))
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 6) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
			e.Lifetime = NumberRange.new(1.2, 2)
			e.Speed = NumberRange.new(5, 9)
			e.Rate = 8 * density()
			e.EmissionDirection = Enum.NormalId.Top
			e.Parent = hood
		end
	end)
end

local STATE_SOUND = { DOWN = "stateDown", UNCONSCIOUS = "stateUnconscious", DEAD = "stateDead", RECOVERING = "stateRecover" }

local function watchDummy(model: Model)
	local last = model:GetAttribute("StatusPrimary")
	model:GetAttributeChangedSignal("StatusPrimary"):Connect(function()
		local now = model:GetAttribute("StatusPrimary")
		local torso = model:FindFirstChild("UpperTorso") :: BasePart?
		if torso and STATE_SOUND[now] and now ~= last then
			local low = now == "UNCONSCIOUS" or now == "DEAD"
			Audio.at(STATE_SOUND[now], torso.Position, if low then 0.3 else 0.4, if now == "DEAD" then 0.55 elseif low then 0.7 else 1, 0.25)
		end
		last = now
	end)
	model:GetAttributeChangedSignal("ReviveFx"):Connect(function()
		local torso = model:FindFirstChild("UpperTorso") :: BasePart?
		if torso then
			Audio.at("revive", torso.Position, 0.6)
			burst(torso.Position, STAR, Color3.fromRGB(110, 255, 190), 24, 16, 1.8, 0.9)
		end
	end)
end

local ready = false

function Effects.init()
	task.delay(4, function()
		ready = true -- no spawn pops for the dummies that exist at join
	end)
	local function applyGraphics()
		game:GetService("Lighting").GlobalShadows = Settings.get("Graphics") ~= "Low"
	end
	applyGraphics()
	Settings.Changed:Connect(applyGraphics)
	local remotes = game.ReplicatedStorage:WaitForChild("Remotes")
	remotes.VehicleCrash.OnClientEvent:Connect(function(vehicle, dv, position)
		if typeof(position) == "Vector3" then
			Effects.onVehicleCrash(vehicle, dv, position)
		end
	end)
	for _, pair in { { "Vehicles", watchVehicle }, { "Dummies", watchDummy } } do
		local folder = workspace:WaitForChild(pair[1])
		folder.ChildAdded:Connect(function(m)
			pair[2](m)
			if pair[1] == "Dummies" then
				local torso = m:WaitForChild("UpperTorso", 3)
				if torso and ready then
					Audio.at("spawnDummy", torso.Position, 0.35, 1, 0.1)
				end
			end
		end)
		for _, m in folder:GetChildren() do
			pair[2](m)
		end
	end
end

return Effects
