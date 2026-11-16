--!nonstrict
-- Spawning, replacing, resetting and deleting vehicles, plus cosmetic crash damage.
local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.GameConfig)
local Specs = require(Shared.VehicleSpecs)
local VehicleBuilder = require(Shared.VehicleBuilder)

local VehicleService = {}
local folder: Folder
local railAnchor: BasePart
local order = {} :: { Model } -- oldest first

local function spawnCFrame(spec, slot: number): CFrame
	local s = Config.Map.Spawns[spec.spawn] or Config.Map.Spawns.Road
	return CFrame.new(s[1] + slot, s[2] + 0.3, s[3]) * CFrame.Angles(0, math.rad(s[4]), 0)
end

local function clearSpot(model: Model, spec): CFrame
	-- slide sideways until the spawn box is free of other vehicles
	local size = model.PrimaryPart.Size
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local step = size.X + 5
	for i = 0, 4 do
		local offset = if spec.phys.kind == "train" then 0 else (if i % 2 == 0 then 1 else -1) * math.ceil(i / 2) * step
		local cf = spawnCFrame(spec, offset)
		if spec.phys.kind == "train" or #workspace:GetPartBoundsInBox(cf * CFrame.new(0, size.Y / 2, 0), size, params) == 0 then
			return cf
		end
	end
	return spawnCFrame(spec, 0)
end

local function attachTrain(model: Model)
	local root = model.PrimaryPart
	local along = CFrame.Angles(0, math.rad(90), 0) -- attachment X axis -> world -Z (down the track)
	local a0 = Instance.new("Attachment")
	a0.CFrame = railAnchor.CFrame:ToObjectSpace(CFrame.new(root.Position) * along)
	a0.Parent = railAnchor
	local a1 = Instance.new("Attachment")
	a1.CFrame = root.CFrame:ToObjectSpace(CFrame.new(root.Position) * along)
	a1.Parent = root
	local rail = Instance.new("PrismaticConstraint")
	rail.Name = "Rail"
	rail.Attachment0, rail.Attachment1 = a0, a1
	rail.LimitsEnabled, rail.LowerLimit, rail.UpperLimit = true, -4, 566
	rail.Parent = root
	model.Destroying:Connect(function()
		a0:Destroy()
	end)
end

function VehicleService.init(vehicleFolder: Folder, anchor: BasePart)
	folder = vehicleFolder
	railAnchor = anchor
	task.spawn(function()
		while task.wait(1) do
			for _, v in folder:GetChildren() do
				local root = (v :: Model).PrimaryPart
				if root then
					local p = root.Position
					if p ~= p or p.Y < -60 or p.Magnitude > 1600 then
						VehicleService.reset(v :: Model)
					end
				end
			end
		end
	end)
end

function VehicleService.setRailAnchor(anchor: BasePart)
	railAnchor = anchor
end

function VehicleService.current(player: Player): Model?
	for i = #order, 1, -1 do
		if order[i].Parent and order[i]:GetAttribute("Owner") == player.UserId then
			return order[i]
		end
	end
	return nil
end

function VehicleService.delete(model: Model)
	local i = table.find(order, model)
	if i then
		table.remove(order, i)
	end
	local seat = model:FindFirstChild("DriverSeat") :: VehicleSeat?
	if seat and seat.Occupant then
		seat.Occupant.Sit = false
	end
	task.defer(model.Destroy, model)
end

function VehicleService.spawn(player: Player, key: string, seatPlayer: boolean?): Model?
	local spec = Specs.Vehicles[key]
	if not spec then
		return nil
	end
	while #order >= Config.MAX_VEHICLES do
		VehicleService.delete(order[1])
	end
	local model = VehicleBuilder.build(key)
	local cf = clearSpot(model, spec)
	model:PivotTo(cf)
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("DamageLevel", 0)
	model:SetAttribute("SpawnId", os.clock())
	model.Parent = folder
	table.insert(order, model)
	local root = model.PrimaryPart
	if spec.phys.kind == "train" then
		attachTrain(model)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Drive"
	prompt.ObjectText = spec.display
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = math.max(14, root.Size.Magnitude * 0.6)
	prompt.HoldDuration = 0
	prompt.Parent = root
	local seat = model:FindFirstChild("DriverSeat") :: VehicleSeat
	prompt.Triggered:Connect(function(who)
		local hum = who.Character and who.Character:FindFirstChildOfClass("Humanoid")
		if hum and not seat.Occupant then
			seat:Sit(hum)
		end
	end)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		prompt.Enabled = seat.Occupant == nil
	end)

	-- single-player sandbox: the player simulates their vehicle for latency-free driving
	pcall(function()
		root:SetNetworkOwner(player)
	end)
	if seatPlayer then
		task.delay(0.15, function()
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum and model.Parent and hum.Health > 0 then
				if hum.SeatPart then
					hum.Sit = false
					task.wait(0.1)
				end
				seat:Sit(hum)
			end
		end)
	end
	return model
end

-- Fresh copy at the spawn point: restores position, velocity, parts and cosmetic damage in one go.
function VehicleService.reset(model: Model): Model?
	local key = model:GetAttribute("VehicleKey")
	local player = game.Players:GetPlayerByUserId(model:GetAttribute("Owner") or 0)
	local seat = model:FindFirstChild("DriverSeat") :: VehicleSeat?
	local wasSeated = seat ~= nil and seat.Occupant ~= nil
	local i = table.find(order, model)
	if i then
		table.remove(order, i)
	end
	if seat and seat.Occupant then
		seat.Occupant.Sit = false
	end
	model:Destroy()
	if player then
		return VehicleService.spawn(player, key, wasSeated)
	end
	return nil
end

function VehicleService.deleteAll()
	for i = #order, 1, -1 do
		VehicleService.delete(order[i])
	end
end

-- Cosmetic crash damage, driven by real collision severity (dv = velocity lost in one step).
local function retilt(part: BasePart?, offset: CFrame)
	if not part then
		return
	end
	local w = part:FindFirstChildOfClass("WeldConstraint")
	if w then
		w.Enabled = false
		part.CFrame = part.CFrame * offset
		w.Enabled = true
	end
end

function VehicleService.onCrash(model: Model, dv: number)
	local level = model:GetAttribute("DamageLevel") or 0
	local target = if dv > 90 then 3 elseif dv > 55 then 2 else 1
	if target <= level then
		return
	end
	model:SetAttribute("DamageLevel", target)
	if level < 1 then
		retilt(model:FindFirstChild("BumperF") :: BasePart?, CFrame.Angles(0, 0, math.rad(7)))
		for _, n in { "HeadlightL", "HeadlightR" } do
			local l = model:FindFirstChild(n) :: BasePart?
			if l and math.random() < 0.5 then
				l.Material = Enum.Material.SmoothPlastic
				l.Color = Color3.fromHex("#55585f")
				local s = l:FindFirstChildOfClass("SpotLight")
				if s then
					s.Enabled = false
				end
			end
		end
	end
	if target >= 2 and level < 2 then
		local hood = model:FindFirstChild("Hood") :: BasePart?
		if hood then -- pop the hood open about its rear edge
			local half = hood.Size.Z / 2
			retilt(hood, CFrame.new(0, 0, half) * CFrame.Angles(math.rad(32), 0, 0) * CFrame.new(0, 0, -half))
		end
	end
	if target >= 3 and level < 3 then
		for _, n in { "BumperF", "Spoiler" } do
			local part = model:FindFirstChild(n) :: BasePart?
			local w = part and part:FindFirstChildOfClass("WeldConstraint")
			if part and w then
				w:Destroy()
				part.Massless = false
				part.CanCollide = true
				part.CollisionGroup = "Prop"
				part.Parent = workspace
				game:GetService("Debris"):AddItem(part, 10)
			end
		end
	end
end

return VehicleService
