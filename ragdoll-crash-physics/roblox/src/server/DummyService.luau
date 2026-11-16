--!nonstrict
-- Owns every dummy: spawn / remove / reset / revive, the per-dummy state (through DamageModel),
-- physical reactions to validated hits, recovery, crawling, limping and safety resets.
local RunService = game:GetService("RunService")
local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.GameConfig)
local DamageModel = require(Shared.DamageModel)
local DummyRig = require(script.Parent.DummyRig)
local RagdollService = require(script.Parent.RagdollService)

local DummyService = {}
DummyService.dummies = {} :: { [number]: any }
DummyService.limit = Config.DUMMY_LIMITS.Automatic
DummyService.recordListeners = {} :: { (any) -> () }

local folder: Folder
local nextId = 1
local IDLE_ANIM, WALK_ANIM = "rbxassetid://507766388", "rbxassetid://507777826" -- stock Roblox R15 idle / walk
local rng = Random.new()

local function count(): number
	local n = 0
	for _ in DummyService.dummies do
		n += 1
	end
	return n
end
DummyService.count = count

local function publish(d, now: number)
	local s, m = d.state, d.model
	local text = DamageModel.statusText(s, now)
	if m:GetAttribute("Status") ~= text then
		m:SetAttribute("Status", text)
		m:SetAttribute("StatusPrimary", DamageModel.statusList(s, now)[1])
	end
	local hp = math.ceil(s.health)
	if m:GetAttribute("Health") ~= hp then
		m:SetAttribute("Health", hp)
	end
	local face = DamageModel.face(s, now)
	if m:GetAttribute("Face") ~= face then
		m:SetAttribute("Face", face)
	end
	for _, r in DamageModel.REGIONS do
		local v = math.floor(s.regions[r] * 100 + 0.5)
		if m:GetAttribute("Cond" .. r) ~= v then
			m:SetAttribute("Cond" .. r, v)
		end
	end
	local blood = math.floor(s.blood + 0.5)
	if m:GetAttribute("Blood") ~= blood then
		m:SetAttribute("Blood", blood)
	end
	local cond = DamageModel.condition(s, now)
	if m:GetAttribute("Condition") ~= cond then
		m:SetAttribute("Condition", cond)
	end
	m:SetAttribute("LastSource", s.lastSource)
	m:SetAttribute("LastSpeedMph", math.floor(s.lastSpeed * Config.STUDS_PER_SEC_TO_MPH + 0.5))
	m:SetAttribute("LastRegion", s.lastRegion)
end

function DummyService.init()
	folder = Instance.new("Folder")
	folder.Name = "Dummies"
	folder.Parent = workspace
	DummyService.folder = folder
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.05 then
			DummyService.update(acc)
			acc = 0
		end
	end)
end

function DummyService.spawn(typeName: string, cf: CFrame, tag: string?): any?
	if count() >= DummyService.limit then
		return nil
	end
	typeName = if Config.DummyTypes[typeName] then typeName else "Noob"
	local id = nextId
	nextId += 1
	local model = DummyRig.build(typeName, id)
	if not folder.Parent then
		model:Destroy()
		return nil
	end
	local hum0 = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local rootPart = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local hip = hum0.HipHeight
	-- cf is a ground point; lift the root so the feet rest on it
	local standCF = cf * CFrame.new(0, hip + rootPart.Size.Y / 2, 0)
	model:PivotTo(standCF)
	model.Parent = folder
	RagdollService.serverOwn(model)
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local animator = hum:FindFirstChildOfClass("Animator") :: Animator
	local tracks = {}
	for name, animId in { idle = IDLE_ANIM, walk = WALK_ANIM } do
		local a = Instance.new("Animation")
		a.AnimationId = animId
		local ok, track = pcall(function()
			return animator:LoadAnimation(a)
		end)
		if ok then
			track.Looped = true
			tracks[name] = track
		end
	end
	if tracks.idle then
		tracks.idle:Play()
	end
	local d = {
		id = id, model = model, hum = hum, root = model.HumanoidRootPart, torso = model.UpperTorso,
		state = DamageModel.newState(id, typeName), typeName = typeName, spawnCF = cf, hip = hip, tag = tag,
		tracks = tracks, lastVel = Vector3.zero, lastVehicleHit = -math.huge, airTime = 0, nextCrawl = 0,
		nextWander = 0, staggerOn = false, prevPrimary = "HEALTHY",
	}
	DummyService.dummies[id] = d
	publish(d, os.clock())
	return d
end

function DummyService.remove(id: number)
	local d = DummyService.dummies[id]
	if d then
		DummyService.dummies[id] = nil
		d.model:Destroy()
	end
end

function DummyService.clear()
	for id in DummyService.dummies do
		DummyService.remove(id)
	end
end

-- Rebuilds the dummy from scratch at its spawn point: the most reliable way to guarantee a valid rig.
function DummyService.reset(id: number)
	local d = DummyService.dummies[id]
	if not d then
		return
	end
	local typeName, cf, tag = d.typeName, d.spawnCF, d.tag
	DummyService.remove(id)
	local n = DummyService.spawn(typeName, cf, tag)
	return n
end

function DummyService.resetAll()
	local list = {}
	for id in DummyService.dummies do
		table.insert(list, id)
	end
	for _, id in list do
		DummyService.reset(id)
	end
end

function DummyService.revive(id: number): boolean
	local d = DummyService.dummies[id]
	if not d then
		return false
	end
	local now = os.clock()
	DamageModel.revive(d.state, now)
	if d.state.ragdolled then
		if RagdollService.disable(d.model, d.hip) then
			d.state.ragdolled = false
		else
			DummyService.reset(id) -- no ground under it: fall back to a clean respawn
			return true
		end
	else
		RagdollService.endStagger(d.model)
	end
	d.model:SetAttribute("ReviveFx", now)
	publish(d, now)
	return true
end

function DummyService.setLimit(mode: string, mobile: boolean)
	local n = Config.DUMMY_LIMITS[mode] or Config.DUMMY_LIMITS.Automatic
	if mode == "Automatic" and mobile then
		n = Config.MOBILE_DUMMY_LIMIT
	end
	DummyService.limit = n
end

-- Force a ragdoll without damage (used by the grab tool and by falls off platforms).
function DummyService.knockDown(d, seconds: number)
	if d.state.dead or d.state.ragdolled then
		return
	end
	d.state.ragdolled = true
	d.state.downUntil = math.max(d.state.downUntil, os.clock() + seconds)
	RagdollService.enable(d.model)
end

local function applyKnock(d, hit, record)
	local model = d.model
	local I = Config.Impact
	local speed = math.min(hit.relSpeed, I.MAX_IMPULSE_SPEED)
	local dir = if hit.relVelocity.Magnitude > 0.1 then hit.relVelocity.Unit else Vector3.new(0, 0, -1)
	if record.reaction == "RAGDOLL" then
		RagdollService.enable(model)
		-- The body picks up most of the striker's velocity; the struck limb gets all of it plus spin.
		local carry = dir * speed * math.clamp(0.55 + 0.25 * (hit.vehicleImpact or 1), 0.5, 1.15)
			+ Vector3.new(0, speed * 0.16, 0)
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") and p.AssemblyRootPart == p then
				local target = carry
				if hit.part and (p == hit.part or hit.part:IsDescendantOf(p)) then
					target = dir * speed * 1.15 + Vector3.new(0, speed * 0.1, 0)
				end
				local dv = target - p.AssemblyLinearVelocity
				p:ApplyImpulse(dv * p.AssemblyMass)
			end
		end
		if hit.part and hit.part.Parent == model then
			-- off-centre hits spin the dummy: torque from where it was struck relative to the torso
			local arm = hit.part.Position - d.torso.Position
			local spin = arm:Cross(dir) * speed * 0.12
			d.torso:ApplyAngularImpulse(spin * d.torso.AssemblyMass)
		end
	else
		RagdollService.stagger(model)
		d.staggerOn = true
		d.root:ApplyImpulse(dir * speed * 0.6 * d.root.AssemblyMass)
	end
end

-- The single entry point for damage. hit = { part, relVelocity, relSpeed, vehicleImpact, source, chain }
-- Returns the DamageModel record (or nil when ignored).
function DummyService.hit(id: number, hit)
	local d = DummyService.dummies[id]
	if not d then
		return nil
	end
	local now = os.clock()
	hit.partName = if hit.part then hit.part.Name else "UpperTorso"
	hit.region = DamageModel.regionOf(hit.partName)
	local record = DamageModel.applyHit(d.state, hit, now)
	if record.ignored then
		return nil
	end
	if not hit.chain then
		d.lastVehicleHit = now
	end
	applyKnock(d, hit, record)
	d.lastVel = d.torso.AssemblyLinearVelocity
	d.skipVelCheckUntil = now + 0.3
	publish(d, now)
	record.status = d.model:GetAttribute("Status")
	record.condition = d.model:GetAttribute("Condition")
	record.display = d.model:GetAttribute("Display")
	record.position = d.torso.Position
	for _, fn in DummyService.recordListeners do
		fn(record)
	end
	return record
end

local function valid(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 5000
end

function DummyService.update(dt: number)
	local now = os.clock()
	local bound = Config.Map.SIZE * 1.6
	local toReset = {}
	for id, d in DummyService.dummies do
		local s, model = d.state, d.model
		if not model.Parent or not d.torso.Parent then
			table.insert(toReset, id)
			continue
		end
		local pos, vel = d.torso.Position, d.torso.AssemblyLinearVelocity
		-- Safety net: fell out of the world, left the map or developed an invalid physics state.
		if not valid(pos) or not valid(vel) or pos.Y < -60 or math.abs(pos.X) > bound or math.abs(pos.Z) > bound then
			table.insert(toReset, id)
			continue
		end

		DamageModel.tick(s, dt, now)
		if s.ragdolled and not RagdollService.isRagdolled(model) then
			RagdollService.enable(model) -- passed out from blood loss
		end

		if s.ragdolled then
			-- Hard landings / secondary collisions while tumbling.
			local dv = (vel - d.lastVel).Magnitude
			if dv > 38 and now > (d.skipVelCheckUntil or 0) and not s.dead then
				DummyService.hit(id, { part = d.torso, relVelocity = d.lastVel, relSpeed = dv * 0.5,
					vehicleImpact = 0.8, source = "Hard Landing", chain = true })
			end
			if DamageModel.canRecover(s, now) and vel.Magnitude < 3 then
				if RagdollService.disable(model, d.hip) then
					s.ragdolled = false
					s.recoveringUntil = now + Config.Damage.RECOVER_TIME
				end
			elseif not s.dead and not DamageModel.isUnconscious(s, now) and not DamageModel.canStand(s)
				and now >= d.nextCrawl and vel.Magnitude < 6 then
				-- CRAWLING: drag the upper body forward in small physical pulls.
				d.nextCrawl = now + 0.9
				local fwd = d.torso.CFrame.UpVector * Vector3.new(1, 0, 1)
				if fwd.Magnitude > 0.2 then
					d.torso:ApplyImpulse((fwd.Unit * 7 + Vector3.new(0, 3, 0)) * d.torso.AssemblyMass)
				end
			end
		else
			-- Standing dummies knocked by flying bodies / props (chain reactions).
			local horiz = (d.root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
			if horiz > d.hum.WalkSpeed + 14 and now - d.lastVehicleHit > 0.5 and now > (d.skipVelCheckUntil or 0) then
				DummyService.hit(id, { part = d.torso, relVelocity = d.root.AssemblyLinearVelocity, relSpeed = horiz * 1.2,
					vehicleImpact = 1, source = "Collision", chain = true })
			end
			-- Knocked off a platform: go limp, the landing does the damage.
			local falling = d.hum:GetState() == Enum.HumanoidStateType.Freefall
			d.airTime = if falling then d.airTime + dt else 0
			if d.airTime > 0.55 or d.root.AssemblyLinearVelocity.Y < -55 then
				d.airTime = 0
				DummyService.knockDown(d, 2)
			end
			if d.staggerOn and now >= s.staggerUntil then
				d.staggerOn = false
				RagdollService.endStagger(model)
			end
			-- LIMPING dummies shuffle around their spot; healthy ones hold position for clean tests.
			local limping = (s.regions.LeftLeg < 0.5 or s.regions.RightLeg < 0.5) and now >= s.recoveringUntil
			d.hum.WalkSpeed = if limping then 4 else 8
			if limping and now >= d.nextWander then
				d.nextWander = now + rng:NextNumber(3, 6)
				local home = d.spawnCF.Position
				d.hum:MoveTo(home + Vector3.new(rng:NextNumber(-8, 8), 0, rng:NextNumber(-8, 8)))
			end
			local moving = d.hum.MoveDirection.Magnitude > 0.1
			if d.tracks.walk then
				if moving and not d.tracks.walk.IsPlaying then
					d.tracks.walk:Play(0.2, 1, 0.55)
				elseif not moving and d.tracks.walk.IsPlaying then
					d.tracks.walk:Stop(0.2)
				end
			end
		end
		d.lastVel = d.torso.AssemblyLinearVelocity
		publish(d, now)
	end
	for _, id in toReset do
		DummyService.reset(id)
	end
end

return DummyService
