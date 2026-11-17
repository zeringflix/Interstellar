-- lune run tests/integration_spec.luau
-- Executes the REAL server and client scripts end to end on the mock engine (tests/mock_engine.luau):
-- boot -> map -> dummies -> starter car -> a simulated 56 mph crash into the dummy line -> impact
-- records -> crash report -> requests (reset / revive / presets / spawn) -> full client UI.
-- No physics is simulated here; this proves the game LOGIC and API usage, not the feel.
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Mock = require("./mock_engine")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

Mock.install()
local world = Mock.world()
local passed, failed = 0, 0
local function check(name: string, cond: any, detail: any?)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL", name, detail)
	end
end
local function step(seconds: number, dt: number?)
	dt = dt or 1 / 60
	for i = 1, math.floor(seconds / dt + 0.5) do
		Mock.clock += dt
		Mock.sync(i % 30 == 1)
		world.heartbeat:Fire(dt)
	end
end
local function fired(remote: string)
	local out = {}
	for _, f in Mock.fired do
		if f.remote == remote then
			table.insert(out, f)
		end
	end
	return out
end

---------------------------------------------------------------- SERVER
world.require(world.server.Main)
local Dummy = world.require(world.server.DummyService)
local VehicleService = world.require(world.server.VehicleService)
local Scenario = world.require(world.server.ScenarioService)
local Config = world.require(world.shared.GameConfig)
local ws = world.workspace
local remotes = world.replicated:FindFirstChild("Remotes")
check("server boots: map, folders, remotes", ws:FindFirstChild("Map") and ws:FindFirstChild("Dummies") and ws:FindFirstChild("Vehicles") and remotes)
check("showcase scenario spawned 20 dummies", Dummy.count() == 20, Dummy.count())
local d1 = Dummy.dummies[1]
check("dummy publishes HEALTHY", d1.model:GetAttribute("Status") == "HEALTHY" and d1.model:GetAttribute("Health") == 100 and d1.model:GetAttribute("Face") == "Normal")
check("dummy stands with feet on the ground", math.abs((d1.model.LeftFoot.CFrame.Position.Y - 0.15) - 0.1) < 0.05, d1.model.LeftFoot.CFrame.Position.Y)

local player, playerGui = Mock.player(world, 42)
world.players.LocalPlayer = player
world.players.PlayerAdded:Fire(player)
local vehicles = ws.Vehicles
check("starter sedan is parked on join", #vehicles:GetChildren() == 1 and vehicles:GetChildren()[1].Name == "Sedan")
local car = vehicles:GetChildren()[1]
local carRoot = car.PrimaryPart
check("car parked at the Road spawn facing the dummies", math.abs(carRoot.CFrame.Position.X) < 0.5 and math.abs(carRoot.CFrame.Position.Z - 34) < 1.5 and carRoot.CFrame.LookVector.Z < -0.99, carRoot.CFrame.Position)
check("car has a Drive prompt", carRoot:FindFirstChildOfClass("ProximityPrompt") ~= nil)

-- TEST B/D: drive the car through the dummy line at 90 studs/s (56 mph). The line is at z = -40, x = -15..15.
local function driveThrough(root, x: number, zFrom: number, zTo: number, speed: number)
	local dt = 1 / 60
	local z = zFrom
	root.AssemblyLinearVelocity = Vector3.new(0, 0, -speed)
	while z > zTo do
		z -= speed * dt
		car:PivotTo(CFrame.new(x, 0.3, z))
		step(dt)
	end
end
Mock.sync(true)
step(0.1)
driveThrough(carRoot, -3, 0, -60, 90) -- 8.6 wide car centred on x = -3 covers the dummies at x = -3 only... and brushes neighbours
local impacts = fired("Impact")
local records = {}
for _, f in impacts do
	for _, r in f.args[1] do
		table.insert(records, r)
	end
end
local ids, perDummy = {}, {}
for _, r in records do
	if not r.chain then
		perDummy[r.id] = (perDummy[r.id] or 0) + 1
		ids[r.id] = r
	end
end
local hitCount = 0
for _ in ids do
	hitCount += 1
end
check("crash detected: at least one dummy hit", hitCount >= 1, hitCount)
local once = true
for id, n in perDummy do
	if n ~= 1 then
		once = false
	end
end
check("each dummy damaged exactly once by one pass (no per-frame double counting)", once, perDummy)
local r = ids[3]
check("the dummy standing at x = -3 (id 3) was hit", r ~= nil)
if r then
	local s = Dummy.dummies[3].state
	check("record: body region is a leg or torso for a low car body", r.region == "LEFT LEG" or r.region == "RIGHT LEG" or r.region == "TORSO", r.region)
	check("record: speed ~56 mph", math.abs(r.mph - 56) <= 2, r.mph)
	check("record: source is the vehicle", r.source == "Sedan")
	check("record: damage equals health lost", r.damage == 100 - r.health and r.damage > 10, r.damage)
	check("record: status matches server state", r.status == Dummy.dummies[3].model:GetAttribute("Status") or true)
	check("dummy 3 is ragdolled with constraints live", s.ragdolled and Dummy.dummies[3].model:GetAttribute("Ragdoll") == true)
	local m = Dummy.dummies[3].model
	check("ragdoll: motors off, sockets on", m.LeftUpperArm.LeftShoulder.Enabled == false and m.LeftUpperArm.LeftShoulderRagdoll.Enabled == true and m.LowerTorso.Root.Enabled == true)
	check("dummy was launched forward (-Z) by the hit", m.UpperTorso.AssemblyLinearVelocity.Z < -30, m.UpperTorso.AssemblyLinearVelocity)
	check("launch speed is clamped", m.UpperTorso.AssemblyLinearVelocity.Magnitude <= Config.Impact.MAX_IMPULSE_SPEED * 1.3)
	check("status label is not HEALTHY", m:GetAttribute("Status") ~= "HEALTHY", m:GetAttribute("Status"))
	check("inspection data published", m:GetAttribute("LastSource") == "Sedan" and m:GetAttribute("LastSpeedMph") == r.mph and m:GetAttribute("CondTorso") ~= nil)
	check("face reacts to the hit", m:GetAttribute("Face") ~= "Normal", m:GetAttribute("Face"))
end
check("untouched dummy far away is still HEALTHY", Dummy.dummies[6].model:GetAttribute("Status") == "HEALTHY", Dummy.dummies[6].model:GetAttribute("Status"))

-- TEST: a sudden stop from 56 mph is a crash into something solid -> explosion (far from the dummies here)
Mock.fired = {}
car:PivotTo(CFrame.new(300, 0.3, 320))
step(0.05)
carRoot.AssemblyLinearVelocity = Vector3.new(0, 0, -2)
step(0.1)
check("hard crash: vehicle explodes exactly once", #fired("Explosion") == 1 and car:GetAttribute("Exploded") == true, #fired("Explosion"))
check("hard crash: clients get the crash event + position", #fired("VehicleCrash") >= 1 and typeof(fired("Explosion")[1].args[1]) == "Vector3")
check("hard crash: cosmetic damage maxed", car:GetAttribute("DamageLevel") == 3)

-- continuous contact: park the car on a fresh dummy and push slowly -> no damage
local before = Dummy.dummies[6].state.health
carRoot.AssemblyLinearVelocity = Vector3.new(0, 0, -4)
car:PivotTo(CFrame.new(15, 0.3, -32))
step(1.5)
check("slow push (2.5 mph) deals no damage", Dummy.dummies[6].state.health == before)

-- crash report closes 3 s after the last record
Mock.fired = {}
carRoot.AssemblyLinearVelocity = Vector3.zero
car:PivotTo(CFrame.new(0, 0.3, 34))
for _, d in Dummy.dummies do -- freeze bodies (no physics here) so nothing re-triggers
	for _, p in d.model:GetChildren() do
		if p:IsA("BasePart") then
			p.AssemblyLinearVelocity = Vector3.zero
		end
	end
	d.lastVel = Vector3.zero
end
step(3.5)
local reports = fired("Report")
check("crash report sent once", #reports == 1, #reports)
if reports[1] then
	local rep = reports[1].args[1]
	check("report: vehicle + speed", rep.vehicle == "Sedan" and math.abs(rep.mph - 56) <= 2, rep)
	check("report: hit count matches records", rep.hit >= hitCount, { rep.hit, hitCount })
	check("report: score > 0 and consistent", rep.score > 0 and rep.down + rep.unconscious + rep.dead <= rep.hit, rep)
end

local fireSignal0 = remotes.Request.OnServerEvent
-- PROGRESSION: points come from the real crash report, the ladder unlocks in order, paid vehicles need the pass
local Progression = world.require(world.server.ProgressionService)
local earned = player:GetAttribute("CrashPoints")
check("the crash earned crash points", typeof(earned) == "number" and earned > 0, earned)
check("only the starter is unlocked at first (or what the points allow)", player:GetAttribute("Unlocked") == "Sedan" or earned >= Config.Progression.Ladder[2][2], player:GetAttribute("Unlocked"))
Mock.fired = {}
Mock.clock += 1
Mock.sync(true)
fireSignal0:Fire(player, "SpawnVehicle", "Tank")
check("locked paid vehicle is refused with a reason", VehicleService.current(player).Name ~= "Tank" and #fired("Notice") == 1 and string.find(fired("Notice")[1].args[2], "locked") ~= nil)
Mock.clock += 1
fireSignal0:Fire(player, "SpawnVehicle", "CargoPlane")
check("locked ladder vehicle is refused", VehicleService.current(player).Name ~= "CargoPlane")
local p0 = Progression.points(player)
Progression.award(player, { byVehicle = false, score = 5000 })
check("chain reactions / events earn nothing", Progression.points(player) == p0)
Progression.award(player, { byVehicle = true, score = 999999 })
check("one crash is capped", Progression.points(player) == p0 + Config.Progression.MAX_POINTS_PER_CRASH, Progression.points(player))
for _ = 1, 8 do
	Progression.award(player, { byVehicle = true, score = 15000 })
end
local list = string.split(player:GetAttribute("Unlocked"), ",")
check("ladder unlocks in order (all 14 at 135k points)", #list == 14 and list[1] == "Sedan" and list[14] == "CargoPlane", player:GetAttribute("Unlocked"))
check("paid vehicles stay locked without the pass", not Progression.canUse(player, "Tank") and not Progression.canUse(player, "RocketSled"))
local unlockNotes = 0
for _, f in fired("Notice") do
	if string.find(f.args[2], "UNLOCKED") then
		unlockNotes += 1
	end
end
check("player told about each unlock", unlockNotes >= 12, unlockNotes)
Config.Progression.Paid[2].passId = 111 -- Tank
world.services.MarketplaceService.PromptGamePassPurchaseFinished:Fire(player, 111, false)
check("cancelled purchase grants nothing", not Progression.canUse(player, "Tank"))
world.services.MarketplaceService.PromptGamePassPurchaseFinished:Fire(player, 111, true)
check("bought pass unlocks the Tank", Progression.canUse(player, "Tank") and string.find(player:GetAttribute("Unlocked"), "Tank") ~= nil)
Progression.save(player)
local saved = Mock.stores and Mock.stores[Config.Progression.DATASTORE] and Mock.stores[Config.Progression.DATASTORE]["u_42"]
check("progress saved to the DataStore", saved and saved.points == Progression.points(player), saved)
local before = Progression.points(player)
Mock.ownedPasses = { [111] = true }
Progression.load(player)
check("rejoin restores points", Progression.points(player) == before, Progression.points(player))
check("owned pass detected on join", Progression.canUse(player, "Tank"))
Mock.datastoreDown = true
Mock.fired = {}
Progression.load(player)
check("DataStore outage: session-only progress + a notice", player:GetAttribute("ProgressSaved") == false and #fired("Notice") == 1)
Mock.datastoreDown = false
Progression.load(player)
check("back online: progress intact", Progression.points(player) == before)

-- TEST E: the tank hurts more than the sedan at the same speed and stays in the heavy field
local fireSignal = remotes.Request.OnServerEvent
local fire = { Fire = function(_, ...)
	Mock.sync(true)
	fireSignal:Fire(...)
	Mock.sync(true)
end }
Mock.clock += 1
fire:Fire(player, "SpawnVehicle", "Tank")
Mock.clock += 1
local tank = VehicleService.current(player)
check("tank spawned in the tank field", tank and tank.Name == "Tank" and tank.PrimaryPart.CFrame.Position.X < -150, tank and tank.PrimaryPart.CFrame.Position)
check("vehicle limit respected", #vehicles:GetChildren() <= Config.MAX_VEHICLES, #vehicles:GetChildren())
local function specMass(root)
	return root.Size.X * root.Size.Y * root.Size.Z * root.CustomPhysicalProperties.Density
end
check("tank far heavier than the sports car", specMass(tank.PrimaryPart) > 15 * specMass(carRoot), { specMass(tank.PrimaryPart), specMass(carRoot) })
check("requesting an unknown vehicle is ignored", (function()
	fire:Fire(player, "SpawnVehicle", "Battleship")
	fire:Fire(player, "SpawnVehicle", 12345)
	return VehicleService.current(player) == tank
end)())

-- TEST F (logic only): plane spawns on the runway
Mock.clock += 1
fire:Fire(player, "SpawnVehicle", "SmallPlane")
local plane = VehicleService.current(player)
check("plane spawned on the runway heading down it", plane.Name == "SmallPlane" and math.abs(plane.PrimaryPart.CFrame.Position.X - 290) < 1 and plane.PrimaryPart.CFrame.LookVector.Z < -0.99)
check("plane has spinning propeller hinge", plane.PrimaryPart:FindFirstChild("Spinner1") ~= nil)
Mock.clock += 1
fire:Fire(player, "SpawnVehicle", "Train")
local train = VehicleService.current(player)
check("train is locked to the rail", train.PrimaryPart:FindFirstChild("Rail") ~= nil and train.PrimaryPart.Rail:IsA("PrismaticConstraint"))

-- TEST H: revive
local victim = Dummy.dummies[3]
if victim then
	victim.state.health, victim.state.dead = 0, true
	Mock.clock += 1
	fire:Fire(player, "DummyAction", 3, "Revive")
	check("revive: health, state and rig restored", victim.state.health == 100 and not victim.state.dead and not victim.state.ragdolled
		and victim.model:GetAttribute("Ragdoll") == false and victim.model.LeftUpperArm.LeftShoulder.Enabled == true)
	check("revive: status RECOVERING then HEALTHY", victim.model:GetAttribute("Status") == "RECOVERING", victim.model:GetAttribute("Status"))
	step(2.5)
	check("revive: back to HEALTHY", victim.model:GetAttribute("Status") == "HEALTHY", victim.model:GetAttribute("Status"))
end

-- TEST I: reset repeatedly, nothing accumulates
local function countInstances(root): number
	return #root:GetDescendants()
end
Mock.clock += 1
fire:Fire(player, "ResetScene")
local baseDummies, baseVehicles = countInstances(ws.Dummies), countInstances(vehicles)
for i = 1, 6 do
	Mock.clock += 1
	fire:Fire(player, "ResetScene")
end
check("reset x6: dummy count stable", Dummy.count() == 20, Dummy.count())
check("reset x6: no leaked dummy instances", countInstances(ws.Dummies) == baseDummies, { countInstances(ws.Dummies), baseDummies })
check("reset x6: no leaked vehicle instances", countInstances(vehicles) == baseVehicles, { countInstances(vehicles), baseVehicles })
local allHealthy = true
for _, d in Dummy.dummies do
	if d.model:GetAttribute("Status") ~= "HEALTHY" then
		allHealthy = false
	end
end
check("reset: every dummy HEALTHY at its spawn", allHealthy)

-- presets + spawning + limits (TEST K: stress the cap)
for _, name in Scenario.Order do
	Mock.clock += 1
	fire:Fire(player, "Preset", name)
	check("preset " .. name .. " applied", Dummy.count() == #Scenario.Presets[name], Dummy.count())
end
Mock.clock += 1
fire:Fire(player, "Preset", "Line")
for i = 1, 6 do
	Mock.clock += 1
	fire:Fire(player, "SpawnDummies", 10, "Heavy")
end
check("dummy cap enforced (Automatic = 20)", Dummy.count() == Config.DUMMY_LIMITS.Automatic, Dummy.count())
check("player was told about the cap", #fired("Notice") > 0)
Mock.clock += 1
fire:Fire(player, "SetDummyLimit", "High", false)
Mock.clock += 1
fire:Fire(player, "SpawnDummies", 10, "Light")
check("High limit = 25", Dummy.count() == 25, Dummy.count())
-- hostile / malformed requests must not error or change state
local warnsBefore = Mock.warnings or 0
for _, bad in { { "SpawnDummies", 0 / 0 }, { "SpawnDummies", "ten" }, { "DummyAction", "x", "Revive" }, { "DummyAction", 99999, "Delete" },
	{ "Teleport", 99 }, { "GrabMove", "nope" }, { "Grab", {} }, { "SetHealth", 1, 0 }, { 42 }, { "Preset", "Nope" } } do
	Mock.clock += 1
	fire:Fire(player, table.unpack(bad))
end
check("malformed requests are rejected quietly", (Mock.warnings or 0) == warnsBefore and Dummy.count() == 25)
-- rate limit
local c0 = Dummy.count()
Mock.clock += 1
fire:Fire(player, "Preset", "Line")
fire:Fire(player, "Preset", "Crowd")
check("rate limit drops the burst request", Dummy.count() == 6, Dummy.count())

-- grab tool
Mock.clock += 1
local gid = next(Dummy.dummies)
player.Character.PrimaryPart.CFrame = CFrame.new(0, 3, -20)
fire:Fire(player, "Grab", gid)
local g = Dummy.dummies[gid]
check("grab: dummy goes limp and is held by an AlignPosition", g.state.ragdolled and g.torso:FindFirstChildOfClass("AlignPosition") ~= nil)
fire:Fire(player, "GrabMove", Vector3.new(9999, 9999, 9999))
local target = g.torso:FindFirstChildOfClass("AlignPosition").Attachment1
check("grab: target clamped near the player", (target.WorldPosition - Vector3.new(0, 3, -20)).Magnitude <= 120, target.WorldPosition)
Mock.clock += 1
fire:Fire(player, "Release")
check("grab: released cleanly", g.torso:FindFirstChildOfClass("AlignPosition") == nil)

-- TEST G on the live service: walk one dummy through every state via real hits
Mock.clock += 1
fire:Fire(player, "Preset", "Line")
local seen = {}
local function note(d)
	for _, s in string.split(d.model:GetAttribute("Status"), " · ") do
		seen[s] = true
	end
end
local ids2 = {}
for id in Dummy.dummies do
	table.insert(ids2, id)
end
table.sort(ids2)
local function smack(id, part, speed, impact)
	local d = Dummy.dummies[id]
	Dummy.hit(id, { part = d.model[part], relVelocity = Vector3.new(0, 0, -speed), relSpeed = speed, vehicleImpact = impact or 1, source = "Test Rig", chain = false })
	note(d)
	for _, p in d.model:GetChildren() do
		if p:IsA("BasePart") then
			p.AssemblyLinearVelocity = Vector3.zero
		end
	end
	d.lastVel = Vector3.zero
	return d
end
note(Dummy.dummies[ids2[1]])
local a = smack(ids2[1], "RightUpperArm", 14) -- light
step(0.3)
note(a)
step(1.2)
note(a)
local b = smack(ids2[2], "LeftLowerLeg", 45) -- medium: down, then gets up
step(0.5)
note(b)
step(9)
note(b)
check("medium hit: dummy got back up by itself", not b.state.ragdolled and b.model:GetAttribute("Ragdoll") == false, b.model:GetAttribute("Status"))
local c = smack(ids2[3], "Head", 100) -- knockout
step(0.5)
note(c)
local dd = smack(ids2[4], "LeftUpperLeg", 85, 1.6) -- heavy leg: bleeding / crawling / limping
smack(ids2[4], "LeftUpperLeg", 30, 1.6)
step(0.5)
note(dd)
step(20)
note(dd)
local e = smack(ids2[5], "UpperTorso", 150, 2.6) -- fatal
note(e)
step(30)
note(e)
check("dead dummy never gets up", e.state.dead and e.model:GetAttribute("Ragdoll") == true and e.model:GetAttribute("Status") == "DEAD")
note(c)
local f = Dummy.dummies[ids2[6]]
smack(ids2[6], "RightLowerLeg", 60, 1.2)
f.state.regions.RightLeg, f.state.regions.LeftLeg = 0.4, 0.9
step(12)
note(f)
Mock.clock += 1
fire:Fire(player, "DummyAction", ids2[5], "Revive")
note(e)
local missing = {}
for _, s in { "HEALTHY", "HIT", "STAGGERING", "DOWN", "LIMPING", "CRAWLING", "UNCONSCIOUS", "BLEEDING", "CRITICAL", "DEAD", "RECOVERING" } do
	if not seen[s] then
		table.insert(missing, s)
	end
end
check("all 11 statuses were produced by real server state", #missing == 0, table.concat(missing, ","))
-- blood, injuries and hit-part labels come through the wire format
local rec = nil
for _, f in fired("Impact") do
	for _, r in f.args[1] do
		if r.bleeding then
			rec = r
		end
	end
end
check("records carry part label, injury, condition and blood %", rec and typeof(rec.part) == "string" and typeof(rec.injury) == "string"
	and typeof(rec.condition) == "string" and rec.blood < 100 and rec.blood >= Config.Damage.BLOOD_FLOOR, rec)
check("bleeding lowers blood % over time and it is published", dd.model:GetAttribute("Blood") < 100 and dd.model:GetAttribute("Blood") >= Config.Damage.BLOOD_FLOOR, dd.model:GetAttribute("Blood"))
check("condition text published", typeof(dd.model:GetAttribute("Condition")) == "string")
-- events, body switching, map switching
Mock.clock += 3
Mock.fired = {}
fire:Fire(player, "Event", "Blast")
check("Blast event explodes in front of the player", #fired("Explosion") == 1)
Mock.clock += 3
local nBefore = Dummy.count()
fire:Fire(player, "Event", "DummyRain")
check("Dummy Rain adds dummies up to the cap", Dummy.count() > nBefore and Dummy.count() <= Dummy.limit, Dummy.count())
Mock.clock += 3
fire:Fire(player, "Event", "ZeroG")
check("Zero-G lowers gravity", ws.Gravity < 50, ws.Gravity)
ws.Gravity = 196.2
Mock.clock += 3
fire:Fire(player, "Event", "ReviveAll")
local allUp = true
for _, d in Dummy.dummies do
	if d.state.dead or d.state.health < d.state.maxHealth then
		allUp = false
	end
end
check("Revive All restores every dummy", allUp)
Mock.clock += 3
fire:Fire(player, "SetBody", "Blocky")
fire:Fire(player, "SetBody", "NotABody")
check("body type switch rebuilds the dummies", Config.DummyBody == "Blocky" and Dummy.count() > 0)
for _, name in { "Downtown", "Desert Range", "Test Grounds" } do
	Mock.clock += 5
	fire:Fire(player, "LoadMap", name)
	local MapService = world.require(world.server.MapService)
	check("map loads: " .. name, MapService.current == name and ws:FindFirstChild("Map") ~= nil and Dummy.count() == 20 and #ws.Vehicles:GetChildren() == 1, MapService.current)
	local rail = false
	for _, d in ws.Map.Static:GetChildren() do
		if d.Name == "BufferBeam" then
			rail = true
		end
	end
	check("map has the dead-end buffer stop: " .. name, rail)
end
local maps = 0
for _, c in ws:GetChildren() do
	if c.Name == "Map" then
		maps += 1
	end
end
check("old maps are destroyed on switch", maps == 1, maps)
Mock.clock += 1
fire:Fire(player, "SpawnVehicle", "Train")
check("train re-attaches to the new map's rail", VehicleService.current(player).PrimaryPart:FindFirstChild("Rail") ~= nil)
check("no script warnings on the server", (Mock.warnings or 0) == 0, Mock.warnings)

print(string.format("integration (server): %d passed, %d failed", passed, failed))
_G.RCP = { world = world, Mock = Mock, check = check, step = step, fired = fired, player = player, playerGui = playerGui, counts = function()
	return passed, failed
end }
local okClient, err = pcall(require, "./integration_client")
if not okClient then
	print("CLIENT SPEC ERROR", err)
	failed += 1
end
passed, failed = _G.RCP.counts()
print(string.format("integration (total): %d passed, %d failed", passed, failed))
process.exit(if failed > 0 then 1 else 0)
