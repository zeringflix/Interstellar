--!nonstrict
-- All sound. IDs come from Shared/AudioIds (Creator Store assets). Handles engine loops whose pitch
-- follows speed, variation picking, distance roll-off and a hard cap on overlapping impact sounds.
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Shared = game.ReplicatedStorage:WaitForChild("Shared")
local AudioIds = require(Shared.AudioIds)
local Specs = require(Shared.VehicleSpecs)
local Settings = require(script.Parent.Settings)

local Audio = {}
local master, sfx, music, ui
local rng = Random.new()
local recent = {} :: { number } -- timestamps of recent 3D one-shots (spam limiter)
local lastByName = {} :: { [string]: number }
local MAX_PER_WINDOW, WINDOW = 6, 0.35

local function group(name: string, parent: Instance): SoundGroup
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Parent = parent
	return g
end

local function applyVolumes()
	master.Volume = Settings.get("MasterVolume")
	local on = if Settings.get("SoundEffects") then 1 else 0
	sfx.Volume = Settings.get("SfxVolume") * on
	ui.Volume = Settings.get("SfxVolume") * on
	music.Volume = Settings.get("MusicVolume")
end

local function pick(name: string): string?
	local list = AudioIds.OneShot[name]
	return list and list[rng:NextInteger(1, #list)]
end

-- 2D interface sound
function Audio.ui(name: string, volume: number?)
	local id = pick(name)
	if not id then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.5
	s.SoundGroup = ui
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 6)
end

-- 3D one-shot at a world position, rate limited so a 15-dummy pile-up is punchy, not deafening
function Audio.at(name: string, position: Vector3, volume: number?, pitch: number?, minGap: number?)
	local now = os.clock()
	if minGap and lastByName[name] and now - lastByName[name] < minGap then
		return
	end
	for i = #recent, 1, -1 do
		if now - recent[i] > WINDOW then
			table.remove(recent, i)
		end
	end
	if #recent >= MAX_PER_WINDOW then
		return
	end
	local id = pick(name)
	if not id then
		return
	end
	table.insert(recent, now)
	lastByName[name] = now
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.6
	s.PlaybackSpeed = (pitch or 1) * rng:NextNumber(0.93, 1.07)
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance, s.RollOffMaxDistance = 18, 420
	s.SoundGroup = sfx
	s.Parent = att
	s:Play()
	Debris:AddItem(att, 8)
end

-- Engine loops ------------------------------------------------------------------
local engines = {} :: { [Model]: { engine: Sound, layer: Sound?, skid: Sound?, cfg: any, max: number } }

local function loop(parent: Instance, id: string, volume: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = true
	s.Volume = 0
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance, s.RollOffMaxDistance = 25, 600
	s.SoundGroup = sfx
	s:SetAttribute("BaseVolume", volume)
	s.Parent = parent
	s:Play()
	return s
end

local function addVehicle(model: Model)
	local root = model:WaitForChild("Root", 5) :: BasePart?
	local key = model:GetAttribute("VehicleKey")
	local map = AudioIds.Vehicle[key]
	if not root or not map then
		return
	end
	local cfg = AudioIds.Engine[map.engine]
	local e = { engine = loop(root, cfg.id, cfg.volume), cfg = cfg, max = Specs.Vehicles[key].phys.maxSpeed }
	if map.layer then
		e.layer = loop(root, AudioIds.Layer[map.layer].id, AudioIds.Layer[map.layer].volume)
	end
	if #Specs.Vehicles[key].wheels > 0 then
		e.skid = loop(root, AudioIds.Layer.skid.id, AudioIds.Layer.skid.volume)
	end
	engines[model] = e
	Audio.at("spawnVehicle", root.Position, 0.5)
end

function Audio.horn(model: Model)
	local map = AudioIds.Vehicle[model:GetAttribute("VehicleKey")]
	if map and map.horn and model.PrimaryPart then
		Audio.at(map.horn, model.PrimaryPart.Position, 0.8, 1, 0.6)
	end
end

function Audio.init()
	master = group("RCP_Master", SoundService)
	sfx, music, ui = group("SFX", master), group("Music", master), group("UI", master)
	applyVolumes()
	Settings.Changed:Connect(applyVolumes)
	local bgm = Instance.new("Sound")
	bgm.Name = "Music"
	bgm.SoundId = AudioIds.Music
	bgm.Looped = true
	bgm.Volume = 0.35
	bgm.SoundGroup = music
	bgm.Parent = SoundService
	bgm:Play()
	local folder = workspace:WaitForChild("Vehicles")
	folder.ChildAdded:Connect(function(m)
		task.spawn(addVehicle, m :: Model)
	end)
	folder.ChildRemoved:Connect(function(m)
		engines[m :: Model] = nil
	end)
	for _, m in folder:GetChildren() do
		task.spawn(addVehicle, m :: Model)
	end
	RunService.Heartbeat:Connect(function(dt)
		for model, e in engines do
			local root = model.PrimaryPart
			if not root then
				continue
			end
			local seat = model:FindFirstChild("DriverSeat") :: VehicleSeat?
			local on = seat ~= nil and seat.Occupant ~= nil
			local power = model:GetAttribute("ClientPower") or 0
			local v = root.AssemblyLinearVelocity
			local speedF = math.clamp(v.Magnitude / e.max, 0, 1)
			local rev = math.clamp(speedF * 0.75 + power * 0.25, 0, 1)
			local k = math.min(1, dt * 8)
			local targetVol = if on then e.engine:GetAttribute("BaseVolume") * (0.55 + 0.45 * rev) else 0
			e.engine.Volume += (targetVol - e.engine.Volume) * k
			e.engine.PlaybackSpeed = e.cfg.pitch[1] + (e.cfg.pitch[2] - e.cfg.pitch[1]) * rev
			if e.layer then
				e.layer.Volume += (e.layer:GetAttribute("BaseVolume") * speedF - e.layer.Volume) * k
				e.layer.PlaybackSpeed = 0.8 + 0.5 * speedF
			end
			if e.skid then
				local lat = math.abs(v:Dot(root.CFrame.RightVector))
				local skidding = lat > 14 and v.Magnitude > 20
				e.skid.Volume += ((if skidding then e.skid:GetAttribute("BaseVolume") else 0) - e.skid.Volume) * k
			end
		end
	end)
end

return Audio
