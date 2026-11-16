-- lune run tests/damage_spec.luau : unit tests for the pure damage / status model.
local process = require("@lune/process")
local Harness = require("./harness")
local h = Harness.new(false)
local D = h.require("shared/DamageModel")
local Config = h.require("shared/GameConfig")

local passed, failed = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL", name, detail)
	end
end
local function hit(state, speed, region, impact, now)
	return D.applyHit(state, { relSpeed = speed, region = region, vehicleImpact = impact or 1, source = "Sedan" }, now or 0)
end
local MPH = Config.STUDS_PER_SEC_TO_MPH

-- TEST A: slow bump -> small reaction, stays up
local s = D.newState(1, "Noob")
local r = hit(s, 14, "RightArm")
check("A light severity", r.severity == "LIGHT", r.severity)
check("A small damage", r.damage > 0 and r.damage <= 8, r.damage)
check("A staggers, no ragdoll", r.reaction == "STAGGER" and not s.ragdolled)
check("A status STAGGERING", D.statusText(s, 0.1) == "STAGGERING", D.statusText(s, 0.1))
check("A returns to HEALTHY", D.statusText(s, 10) == "HEALTHY", D.statusText(s, 10))
check("A health matches record", s.health == 100 - r.damage)
check("A region label", D.REGION_LABEL[r.region] == "RIGHT ARM")

-- TEST B: fast hit -> ragdoll, big damage, bounded
s = D.newState(2, "Noob")
r = hit(s, 95, "Torso")
check("B heavy", r.severity == "HEAVY" or r.severity == "CRITICAL", r.severity)
check("B ragdoll", r.reaction == "RAGDOLL" and s.ragdolled)
check("B damage 40..100", r.damage >= 40 and r.damage <= 100, r.damage)
check("B unconscious", D.isUnconscious(s, 1))
local txt = D.statusText(s, 1)
check("B status contains UNCONSCIOUS", string.find(txt, "UNCONSCIOUS") ~= nil, txt)
check("B not DEAD while health > 0", (s.health > 0) == (txt ~= "DEAD"), txt)

-- monotonic: faster never hurts less
local prev = -1
local mono = true
for speed = 0, 200, 5 do
	local e = D.evaluate(D.newState(0, "Noob"), { relSpeed = speed, region = "Torso", vehicleImpact = 1 })
	if e.damage < prev then
		mono = false
	end
	prev = e.damage
end
check("damage monotonic in speed", mono)
check("no damage below floor", D.evaluate(D.newState(0, "Noob"), { relSpeed = 7, region = "Head", vehicleImpact = 3 }).damage == 0)

-- TEST C: regions
for _, region in D.REGIONS do
	s = D.newState(3, "Noob")
	r = hit(s, 60, region)
	check("C region tracked " .. region, s.regions[region] < 1 and r.region == region)
	for _, other in D.REGIONS do
		if other ~= region then
			check("C other region untouched", s.regions[other] == 1)
		end
	end
end
local head = D.evaluate(D.newState(0, "Noob"), { relSpeed = 60, region = "Head", vehicleImpact = 1 }).damage
local arm = D.evaluate(D.newState(0, "Noob"), { relSpeed = 60, region = "LeftArm", vehicleImpact = 1 }).damage
check("C head hit worse than arm", head > arm, { head, arm })
check("part->region map", D.regionOf("LeftLowerLeg") == "LeftLeg" and D.regionOf("RightHand") == "RightArm" and D.regionOf("LowerTorso") == "Torso")

-- vehicle classes differ: tank vs sedan vs go-kart at the same speed
local function dmg(impact)
	return D.evaluate(D.newState(0, "Noob"), { relSpeed = 40, region = "Torso", vehicleImpact = impact }).damage
end
check("tank > sedan > kart", dmg(2.6) > dmg(1.0) and dmg(1.0) > dmg(0.7), { dmg(2.6), dmg(1.0), dmg(0.7) })

-- dummy types
local function typeDmg(t)
	return D.evaluate(D.newState(0, t), { relSpeed = 70, region = "Torso", vehicleImpact = 1 }).damage
end
check("armored < noob < light", typeDmg("Armored") < typeDmg("Noob") and typeDmg("Noob") < typeDmg("Light"))

-- TEST G: every status is reachable and consistent
s = D.newState(4, "Noob")
check("G HEALTHY", D.statusText(s, 0) == "HEALTHY")
hit(s, 14, "LeftArm", 1, 0)
check("G STAGGERING", D.statusList(s, 0.2)[1] == "STAGGERING")
check("G HIT after stagger", D.statusList(s, 1.6)[1] == "HIT", D.statusText(s, 1.6))
s = D.newState(5, "Noob")
hit(s, 42, "LeftLeg", 1, 0)
check("G DOWN after medium leg hit", D.statusList(s, 0.5)[1] == "DOWN", D.statusText(s, 0.5))
s.ragdolled = false
s.regions.LeftLeg = 0.4
check("G LIMPING", D.statusText(s, 50) == "LIMPING", D.statusText(s, 50))
s.regions.LeftLeg = 0.1
s.ragdolled = true
check("G CRAWLING", D.statusList(s, 50)[1] == "CRAWLING", D.statusText(s, 50))
check("G cannot stand with broken leg", not D.canRecover(s, 50))
s = D.newState(6, "Noob")
hit(s, 100, "Head", 1, 0)
check("G UNCONSCIOUS", string.find(D.statusText(s, 1), "UNCONSCIOUS") ~= nil, D.statusText(s, 1))
s = D.newState(7, "Noob")
hit(s, 75, "LeftLeg", 1.2, 0)
check("G BLEEDING flagged", s.bleeding and string.find(D.statusText(s, 1), "BLEEDING") ~= nil, D.statusText(s, 1))
local before = s.health
for _ = 1, 400 do
	D.tick(s, 0.5)
end
check("G bleeding drains but never kills", s.health < before and s.health >= Config.Damage.BLEED_FLOOR and not s.dead, s.health)
check("G CRITICAL", D.statusList(s, 500)[1] == "CRITICAL", D.statusText(s, 500))
s = D.newState(8, "Noob")
hit(s, 14, "Torso", 1, 0)
check("light hit does not bleed", not s.bleeding)
s = D.newState(9, "Noob")
local n = 0
while not s.dead and n < 20 do
	hit(s, 120, "Torso", 2, n)
	n += 1
end
check("G DEAD", s.dead and D.statusText(s, 99) == "DEAD" and s.health == 0)
check("G dead ignores further hits", hit(s, 120, "Torso", 2, 100).ignored == true)
check("G dead cannot recover", not D.canRecover(s, 1000))
check("dead face", D.face(s, 1000) == "Dead")

-- TEST H: revive
D.revive(s, 200)
check("H revive restores", not s.dead and s.health == s.maxHealth and s.regions.Torso == 1 and not s.bleeding)
s.ragdolled = false
check("H RECOVERING", D.statusText(s, 200.5) == "RECOVERING", D.statusText(s, 200.5))
check("H HEALTHY afterwards", D.statusText(s, 210) == "HEALTHY")

-- faces follow state
s = D.newState(10, "Noob")
check("face Normal", D.face(s, 0) == "Normal")
hit(s, 30, "Torso", 1, 10)
check("face Surprised right after a hit", D.face(s, 10.1) == "Surprised", D.face(s, 10.1))
check("face Dizzy while down", D.face(s, 11.5) == "Dizzy", D.face(s, 11.5))
s = D.newState(11, "Noob")
hit(s, 100, "Head", 1, 0)
check("face Unconscious", D.face(s, 3) == "Unconscious", D.face(s, 3))

-- blood, injuries, labels
s = D.newState(20, "Noob")
r = hit(s, 85, "LeftLeg", 1.6, 0)
check("heavy hit: injury text + part label", r.injury == "Leg broken" or r.injury == "Leg shattered", r.injury)
check("heavy hit starts bleeding and costs blood", s.bleeding and s.blood < 100, s.blood)
local b0 = s.blood
for i = 1, 600 do
	D.tick(s, 0.5, i * 0.5)
end
check("blood drains to the floor, then clots", s.blood < b0 and s.blood >= Config.Damage.BLOOD_FLOOR and not s.bleeding, s.blood)
check("heavy blood loss knocks the dummy out", s.unconsciousUntil > 0)
check("part labels", D.partLabel("LeftLowerLeg") == "Left Knee" and D.partLabel("Head") == "Head" and D.partLabel("UpperTorso") == "Chest")
check("condition phrases", D.condition(D.newState(21, "Noob"), 0) == "Unhurt")
D.revive(s, 1000)
check("revive refills blood", s.blood == 100)

-- units
check("mph conversion", math.abs(109 * MPH - 68.2) < 0.2)

print(string.format("damage_spec: %d passed, %d failed", passed, failed))
process.exit(if failed > 0 then 1 else 0)
