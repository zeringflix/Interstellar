--!nonstrict
-- Turns verified hit records into (a) the live impact feed and (b) a per-crash report + score.
-- A "crash" is a burst of records; it closes after 3 quiet seconds. Every number in the report is
-- counted from DamageModel records / live dummy state - nothing is invented for display.
local RunService = game:GetService("RunService")
local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.GameConfig)
local DamageModel = require(Shared.DamageModel)
local DummyService = require(script.Parent.DummyService)

local CrashReportService = {}
CrashReportService.last = nil
CrashReportService.history = {}

local remotes
local current = nil
local pending = {}
local lastScored = {} :: { [number]: number } -- dummy id -> time it last earned score

local function wire(record)
	return {
		id = record.id, display = record.display, region = DamageModel.REGION_LABEL[record.region],
		severity = record.severity, damage = record.damage, health = math.ceil(record.health),
		status = record.status, source = record.source, chain = record.chain, injury = record.injury,
		part = record.partLabel, blood = record.blood, bleeding = record.bleeding, dead = record.dead, condition = record.condition,
		mph = math.floor(record.relSpeed * Config.STUDS_PER_SEC_TO_MPH + 0.5), position = record.position,
	}
end

local function onRecord(record)
	local now = os.clock()
	table.insert(pending, wire(record))
	if not current then
		current = { start = now, vehicle = nil, topMph = 0, dummies = {}, hits = 0, chain = 0, score = 0, props = 0 }
	end
	current.lastTime = now
	current.hits += 1
	if not record.chain then
		current.vehicle = current.vehicle or record.source
		current.topMph = math.max(current.topMph, record.relSpeed * Config.STUDS_PER_SEC_TO_MPH)
	end
	-- Score: full value the first time a dummy is hit in a crash; repeat taps inside the window earn nothing.
	local S = Config.Score
	local first = not current.dummies[record.id]
	current.dummies[record.id] = true
	local recently = lastScored[record.id] and (now - lastScored[record.id]) < S.REPEAT_WINDOW
	if first and not (recently and record.severity == "LIGHT") then
		current.score += S[record.severity] or 0
		lastScored[record.id] = now
	end
	if record.chain and first then
		current.chain += 1
		current.score += S.CHAIN
	end
end

local function close()
	local c = current
	current = nil
	local now = os.clock()
	local report = { vehicle = c.vehicle or "Chain Reaction", mph = math.floor(c.topMph + 0.5), hit = 0,
		down = 0, unconscious = 0, dead = 0, chain = c.chain, props = 0, score = 0 }
	for id in c.dummies do
		report.hit += 1
		local d = DummyService.dummies[id]
		if d then
			local s = d.state
			if s.dead then
				report.dead += 1
			elseif DamageModel.isUnconscious(s, now) then
				report.unconscious += 1
			elseif s.ragdolled then
				report.down += 1
			end
		end
	end
	if CrashReportService.countDisturbedProps then
		report.props = CrashReportService.countDisturbedProps()
	end
	report.score = c.score + report.props * Config.Score.PROP
	if report.hit == 0 then
		return
	end
	CrashReportService.last = report
	table.insert(CrashReportService.history, report)
	if #CrashReportService.history > 10 then
		table.remove(CrashReportService.history, 1)
	end
	remotes.Report:FireAllClients(report)
end

function CrashReportService.init(r)
	remotes = r
	table.insert(DummyService.recordListeners, onRecord)
	RunService.Heartbeat:Connect(function()
		if #pending > 0 then
			remotes.Impact:FireAllClients(pending)
			pending = {}
		end
		if current and os.clock() - current.lastTime > 3 then
			close()
		end
	end)
end

return CrashReportService
