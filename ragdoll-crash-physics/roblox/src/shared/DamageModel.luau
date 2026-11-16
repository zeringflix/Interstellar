--!nonstrict
-- Pure damage / status logic. No Roblox instances in here, so it runs in plain
-- Luau and is covered by tests/damage_spec.luau. The server (DamageService) is the
-- only code that mutates dummy state, and it does so only through these functions.
local Config = require(script.Parent.GameConfig)
local D = Config.Damage

local DamageModel = {}

DamageModel.REGIONS = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }
DamageModel.REGION_LABEL = {
	Head = "HEAD", Torso = "TORSO", LeftArm = "LEFT ARM", RightArm = "RIGHT ARM",
	LeftLeg = "LEFT LEG", RightLeg = "RIGHT LEG",
}

-- Rig part name -> logical body region.
local PART_REGION = {
	Head = "Head", UpperTorso = "Torso", LowerTorso = "Torso", HumanoidRootPart = "Torso",
	LeftUpperArm = "LeftArm", LeftLowerArm = "LeftArm", LeftHand = "LeftArm",
	RightUpperArm = "RightArm", RightLowerArm = "RightArm", RightHand = "RightArm",
	LeftUpperLeg = "LeftLeg", LeftLowerLeg = "LeftLeg", LeftFoot = "LeftLeg",
	RightUpperLeg = "RightLeg", RightLowerLeg = "RightLeg", RightFoot = "RightLeg",
}
-- Exact spot shown to the player ("Left Knee"), finer than the six damage regions.
local PART_LABEL = {
	Head = "Head", UpperTorso = "Chest", LowerTorso = "Pelvis", HumanoidRootPart = "Chest",
	LeftUpperArm = "Left Shoulder", LeftLowerArm = "Left Elbow", LeftHand = "Left Hand",
	RightUpperArm = "Right Shoulder", RightLowerArm = "Right Elbow", RightHand = "Right Hand",
	LeftUpperLeg = "Left Thigh", LeftLowerLeg = "Left Knee", LeftFoot = "Left Foot",
	RightUpperLeg = "Right Thigh", RightLowerLeg = "Right Knee", RightFoot = "Right Foot",
}
function DamageModel.partLabel(partName: string): string
	return PART_LABEL[partName] or "Chest"
end

-- Plain-language injury for a hit, by region kind and severity (game flavour, not medicine).
local INJURY = {
	Head = { LIGHT = "Dazed", MEDIUM = "Concussed", HEAVY = "Skull cracked", CRITICAL = "Severe head trauma" },
	Torso = { LIGHT = "Winded", MEDIUM = "Bruised ribs", HEAVY = "Broken ribs", CRITICAL = "Chest crushed" },
	Arm = { LIGHT = "Arm bruised", MEDIUM = "Arm sprained", HEAVY = "Arm broken", CRITICAL = "Arm shattered" },
	Leg = { LIGHT = "Leg bruised", MEDIUM = "Leg sprained", HEAVY = "Leg broken", CRITICAL = "Leg shattered" },
}
function DamageModel.injury(region: string, severity: string): string
	local kind = if region == "Head" or region == "Torso" then region elseif string.find(region, "Arm") then "Arm" else "Leg"
	return INJURY[kind][severity] or "Hit"
end

-- One short phrase for how the dummy is doing right now ("Hurt, still standing").
function DamageModel.condition(state, now: number): string
	if state.dead then
		return "Dead"
	elseif now < state.unconsciousUntil then
		return "Knocked out"
	elseif state.ragdolled and not DamageModel.canStand(state) then
		return "Crawling"
	elseif state.ragdolled then
		return "Down"
	elseif state.health >= state.maxHealth then
		return "Unhurt"
	elseif state.regions.LeftLeg < 0.5 or state.regions.RightLeg < 0.5 then
		return "Limping"
	elseif state.health <= D.CRITICAL_HEALTH then
		return "Critical, still standing"
	end
	return "Hurt, still standing"
end

function DamageModel.regionOf(partName: string): string
	return PART_REGION[partName] or "Torso"
end

function DamageModel.newState(id: number, typeName: string)
	local t = Config.DummyTypes[typeName] or Config.DummyTypes.Noob
	local regions = {}
	for _, r in DamageModel.REGIONS do
		regions[r] = 1
	end
	return {
		id = id, typeName = typeName, armor = t.armor,
		health = t.health, maxHealth = t.health, blood = 100, regions = regions,
		ragdolled = false, dead = false, bleeding = false,
		unconsciousUntil = 0, staggerUntil = 0, hitUntil = 0, recoveringUntil = 0, downUntil = 0,
		lastSource = "", lastSpeed = 0, lastRegion = "", lastDamageTime = -math.huge, lastDir = { 0, 0, 0 },
		history = {},
	}
end

local function clamp(x, lo, hi)
	return math.max(lo, math.min(hi, x))
end

-- hit = { relSpeed (studs/s), vehicleImpact (per-vehicle weight class), region, source }
-- Returns { damage, severity, reaction } without touching state.
function DamageModel.evaluate(state, hit)
	local score = hit.relSpeed * (hit.vehicleImpact or 1)
	local severity = "LIGHT"
	if score >= D.SEVERITY.CRITICAL then
		severity = "CRITICAL"
	elseif score >= D.SEVERITY.HEAVY then
		severity = "HEAVY"
	elseif score >= D.SEVERITY.MEDIUM then
		severity = "MEDIUM"
	end
	local t = clamp((hit.relSpeed - D.SPEED_FLOOR) / (D.SPEED_FULL - D.SPEED_FLOOR), 0, 1.5)
	local damage = (t ^ D.CURVE) * D.BASE_MAX * (hit.vehicleImpact or 1)
		* (D.REGION_MULT[hit.region] or 1) * (state.armor or 1)
	if state.ragdolled then
		damage *= D.RAGDOLLED_MULT
	end
	damage = math.floor(damage + 0.5)
	return { damage = damage, severity = severity }
end

-- Applies a validated hit. Mutates state and returns a record describing exactly what changed.
function DamageModel.applyHit(state, hit, now: number)
	if state.dead then
		return { ignored = true, reason = "dead" }
	end
	local ev = DamageModel.evaluate(state, hit)
	local damage, severity = ev.damage, ev.severity
	local before = state.health
	state.health = math.max(0, state.health - damage)
	local region = hit.region
	state.regions[region] = clamp(state.regions[region] - damage / 60, 0, 1)

	state.lastSource, state.lastSpeed, state.lastRegion = hit.source or "Unknown", hit.relSpeed, region
	state.lastDamageTime = now
	state.hitUntil = now + D.HIT_FLASH_TIME

	local reaction = "STAGGER"
	if state.health <= 0 then
		state.dead = true
		state.ragdolled = true
		reaction = "RAGDOLL"
	else
		local knockout = severity == "CRITICAL" or (region == "Head" and severity == "HEAVY") or damage >= 45
		if knockout then
			state.unconsciousUntil = math.max(state.unconsciousUntil, now + 5 + damage * 0.12)
		end
		if (severity == "HEAVY" or severity == "CRITICAL" or damage >= 35) and state.regions[region] < 0.55 then
			state.bleeding = true
			state.blood = math.max(D.BLOOD_FLOOR, state.blood - damage * 0.12) -- the wound itself costs some blood
		end
		local legsOut = state.regions.LeftLeg <= 0.2 or state.regions.RightLeg <= 0.2
		if severity ~= "LIGHT" or knockout or legsOut or state.ragdolled or state.health <= D.CRITICAL_HEALTH then
			reaction = "RAGDOLL"
			state.ragdolled = true
			local f = clamp(damage / 60, 0, 1)
			state.downUntil = math.max(state.downUntil, now + D.DOWN_TIME[1] + (D.DOWN_TIME[2] - D.DOWN_TIME[1]) * f)
		else
			state.staggerUntil = now + D.STAGGER_TIME
		end
	end

	local record = {
		id = state.id, region = region, severity = severity, damage = before - state.health,
		health = state.health, source = state.lastSource, relSpeed = hit.relSpeed, reaction = reaction,
		injury = DamageModel.injury(region, severity), partLabel = DamageModel.partLabel(hit.partName or ""),
		blood = math.floor(state.blood + 0.5), bleeding = state.bleeding, dead = state.dead,
		time = now, chain = hit.chain or false,
	}
	table.insert(state.history, record)
	if #state.history > 12 then
		table.remove(state.history, 1)
	end
	return record
end

-- Time-based changes (bleeding drain). Returns true when something changed.
function DamageModel.tick(state, dt: number, now: number?): boolean
	if state.dead or not state.bleeding then
		return false
	end
	local changed = false
	if state.blood > D.BLOOD_FLOOR then
		state.blood = math.max(D.BLOOD_FLOOR, state.blood - D.BLOOD_RATE * dt)
		changed = true
		if state.blood < 55 and now then -- heavy blood loss: the dummy passes out
			state.unconsciousUntil = math.max(state.unconsciousUntil, now + 4)
			state.ragdolled = true
		end
	else
		state.bleeding = false -- clotted
		changed = true
	end
	if state.health > D.BLEED_FLOOR then
		state.health = math.max(D.BLEED_FLOOR, state.health - D.BLEED_RATE * dt)
		changed = true
	end
	return changed
end

function DamageModel.isUnconscious(state, now: number): boolean
	return not state.dead and now < state.unconsciousUntil
end

function DamageModel.canStand(state): boolean
	return state.regions.LeftLeg > 0.2 and state.regions.RightLeg > 0.2
end

-- May the dummy start getting up right now?
function DamageModel.canRecover(state, now: number): boolean
	return state.ragdolled and not state.dead and not DamageModel.isUnconscious(state, now)
		and DamageModel.canStand(state) and now >= state.downUntil and state.health > D.CRITICAL_HEALTH * 0.4
end

-- The ordered list of condition labels that are true right now. Always derived from state.
function DamageModel.statusList(state, now: number): { string }
	if state.dead then
		return { "DEAD" }
	end
	local list = {}
	if state.health <= D.CRITICAL_HEALTH then
		table.insert(list, "CRITICAL")
	end
	if now < state.unconsciousUntil then
		table.insert(list, "UNCONSCIOUS")
	elseif state.ragdolled and not DamageModel.canStand(state) then
		table.insert(list, "CRAWLING")
	elseif state.ragdolled then
		table.insert(list, "DOWN")
	elseif now < state.recoveringUntil then
		table.insert(list, "RECOVERING")
	elseif now < state.staggerUntil then
		table.insert(list, "STAGGERING")
	elseif state.regions.LeftLeg < 0.5 or state.regions.RightLeg < 0.5 then
		table.insert(list, "LIMPING")
	elseif now < state.hitUntil then
		table.insert(list, "HIT")
	end
	if state.bleeding then
		table.insert(list, "BLEEDING")
	end
	if #list == 0 then
		list[1] = "HEALTHY"
	end
	return list
end

function DamageModel.statusText(state, now: number): string
	return table.concat(DamageModel.statusList(state, now), " · ")
end

function DamageModel.regionLabel(cond: number): string
	if cond >= 0.85 then
		return "Healthy"
	elseif cond >= 0.6 then
		return "Light Damage"
	elseif cond >= 0.35 then
		return "Moderate Damage"
	elseif cond > 0.1 then
		return "Severe Damage"
	end
	return "Broken"
end

-- Which face the dummy should wear. Driven purely by state.
function DamageModel.face(state, now: number): string
	if state.dead then
		return "Dead"
	elseif now < state.unconsciousUntil then
		return "Unconscious"
	elseif now < state.hitUntil and now - state.lastDamageTime < 0.6 then
		return "Surprised"
	elseif state.ragdolled or now < state.staggerUntil then
		return "Dizzy"
	elseif state.health <= D.CRITICAL_HEALTH or state.bleeding or state.health < state.maxHealth * 0.6 then
		return "Hurt"
	end
	return "Normal"
end

function DamageModel.revive(state, now: number)
	state.health = state.maxHealth
	state.blood = 100
	for _, r in DamageModel.REGIONS do
		state.regions[r] = 1
	end
	state.dead, state.bleeding = false, false
	state.unconsciousUntil, state.staggerUntil, state.hitUntil, state.downUntil = 0, 0, 0, 0
	state.recoveringUntil = now + D.RECOVER_TIME
end

return DamageModel
