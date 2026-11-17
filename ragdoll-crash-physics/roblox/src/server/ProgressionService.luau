--!nonstrict
-- Crash points, the unlock ladder and the Robux vehicles. Server-authoritative: the client only
-- ever sees the result as two Player attributes:
--   CrashPoints  (number)  lifetime points
--   Unlocked     (string)  comma-separated vehicle keys the player may spawn
-- Saving: one DataStore key per player, written with UpdateAsync that keeps the larger point total,
-- so a failed or out-of-order save can never lose progress. If DataStores are unavailable (Studio
-- without API access, an outage) the game keeps running with session-only progress and says so.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local Config = require(game.ReplicatedStorage.Shared.GameConfig)

local P = Config.Progression
local Progression = {}
Progression.notify = nil :: ((Player, string) -> ())?

local sessions = {} :: { [Player]: { points: number, passes: { [string]: boolean }, loaded: boolean, persistent: boolean, dirty: boolean } }
local store = nil
do
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore(P.DATASTORE)
	end)
	store = if ok then s else nil
end

local PAID = {}
for _, p in P.Paid do
	PAID[p.vehicle] = p
end
local LADDER = {}
for i, step in P.Ladder do
	LADDER[step[1]] = { index = i, cost = step[2] }
end

local function key(player: Player): string
	return "u_" .. player.UserId
end

local function retry(fn, tries: number)
	local delay = 1
	local ok, result
	for attempt = 1, tries do
		ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if attempt < tries then
			task.wait(delay)
			delay *= 2
		end
	end
	return false, result
end

function Progression.canUse(player: Player, vehicle: string): boolean
	local s = sessions[player]
	if not s then
		return vehicle == P.Ladder[1][1]
	end
	if P.StudioUnlockAll and RunService:IsStudio() then
		return true
	end
	if PAID[vehicle] then
		return s.passes[vehicle] == true
	end
	local step = LADDER[vehicle]
	return step ~= nil and s.points >= step.cost
end

-- Why a vehicle is locked, for the message the player sees.
function Progression.lockReason(player: Player, vehicle: string): string
	if PAID[vehicle] then
		return if PAID[vehicle].passId > 0 then "Buy it in the Shop" else "Coming soon to the Shop"
	end
	local step = LADDER[vehicle]
	if step then
		local s = sessions[player]
		return string.format("Unlocks at %d crash points (you have %d)", step.cost, if s then math.floor(s.points) else 0)
	end
	return "Not available"
end

local function publish(player: Player)
	local s = sessions[player]
	if not s then
		return
	end
	local list = {}
	for _, step in P.Ladder do
		if Progression.canUse(player, step[1]) then
			table.insert(list, step[1])
		end
	end
	for _, p in P.Paid do
		if Progression.canUse(player, p.vehicle) then
			table.insert(list, p.vehicle)
		end
	end
	player:SetAttribute("CrashPoints", math.floor(s.points))
	player:SetAttribute("Unlocked", table.concat(list, ","))
	player:SetAttribute("ProgressSaved", s.persistent)
end

local function checkPasses(player: Player)
	local s = sessions[player]
	for _, p in P.Paid do
		if p.passId > 0 and not s.passes[p.vehicle] then
			local ok, owns = retry(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, p.passId)
			end, 2)
			if ok and owns then
				s.passes[p.vehicle] = true
			end
		end
	end
end

function Progression.load(player: Player)
	local s = { points = 0, passes = {}, loaded = false, persistent = false, dirty = false }
	sessions[player] = s
	if store then
		local ok, data = retry(function()
			return store:GetAsync(key(player))
		end, 3)
		if ok then
			if typeof(data) == "table" and typeof(data.points) == "number" and data.points == data.points then
				s.points = math.max(0, data.points)
			end
			s.persistent = true
		end
	end
	if not sessions[player] then
		return -- left while loading
	end
	s.loaded = true
	checkPasses(player)
	publish(player)
	if not s.persistent and Progression.notify then
		Progression.notify(player, "Progress can't be saved right now - it will last this session only")
	end
end

function Progression.save(player: Player)
	local s = sessions[player]
	if not (s and s.loaded and s.persistent and s.dirty and store) then
		return
	end
	local points = s.points
	local ok = retry(function()
		store:UpdateAsync(key(player), function(old)
			local prev = if typeof(old) == "table" and typeof(old.points) == "number" then old.points else 0
			return { points = math.max(prev, points), version = 1 }
		end)
	end, 3)
	if ok then
		s.dirty = false
	end
end

-- Called with every finished crash report. Only reports started by a vehicle count.
function Progression.award(player: Player, report)
	local s = sessions[player]
	if not (s and s.loaded) or typeof(report) ~= "table" or not report.byVehicle then
		return
	end
	local gain = math.clamp(math.floor(tonumber(report.score) or 0), 0, P.MAX_POINTS_PER_CRASH)
	if gain <= 0 then
		return
	end
	local before = {}
	for _, step in P.Ladder do
		before[step[1]] = Progression.canUse(player, step[1])
	end
	s.points += gain
	s.dirty = true
	publish(player)
	for _, step in P.Ladder do
		if not before[step[1]] and Progression.canUse(player, step[1]) and Progression.notify then
			Progression.notify(player, "UNLOCKED: " .. string.upper(step[1]) .. "!")
		end
	end
end

function Progression.grantPass(player: Player, passId: number)
	local s = sessions[player]
	if not s then
		return
	end
	for _, p in P.Paid do
		if p.passId > 0 and p.passId == passId then
			s.passes[p.vehicle] = true
			publish(player)
			if Progression.notify then
				Progression.notify(player, "UNLOCKED: " .. string.upper(p.vehicle) .. "! Thanks for the support")
			end
		end
	end
end

function Progression.points(player: Player): number
	local s = sessions[player]
	return if s then s.points else 0
end

function Progression.init()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(Progression.load, player)
	end)
	for _, player in Players:GetPlayers() do
		if not sessions[player] then
			task.spawn(Progression.load, player)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		Progression.save(player)
		sessions[player] = nil
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased then
			Progression.grantPass(player, passId)
		end
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			Progression.save(player)
		end
	end)
	task.spawn(function()
		while task.wait(P.AUTOSAVE_SECONDS) do
			for _, player in Players:GetPlayers() do
				task.spawn(Progression.save, player)
			end
		end
	end)
end

return Progression
