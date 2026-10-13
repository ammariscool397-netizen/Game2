--[[
	MEGA TYCOON - server bootstrap.
	Loads every service in Services/, calls :Init(S) on each (S = registry of
	all services so they can talk to each other), then :Start().
]]
local ServerScriptService = game:GetService("ServerScriptService")

local servicesFolder = ServerScriptService:WaitForChild("Services")

local ORDER = {
	"WorldBuilder",
	"DataService",
	"MonetizationService",
	"TycoonService",
	"ObbyService",
	"SecretService",
	"DuoService",
	"QuestService",
	"GiftService",
	"DisasterService",
	"AdminService",
	"MinigameService",
	"RewardService",
	"LeaderboardService",
}

local S = {}
for _, name in ORDER do
	local module = servicesFolder:FindFirstChild(name)
	if module then
		local ok, result = pcall(require, module)
		if ok then
			S[name] = result
		else
			warn("[MegaTycoon] Failed to load " .. name .. ": " .. tostring(result))
		end
	end
end

for _, name in ORDER do
	local service = S[name]
	if service and service.Init then
		local ok, err = pcall(service.Init, service, S)
		if not ok then
			warn("[MegaTycoon] Init failed for " .. name .. ": " .. tostring(err))
		end
	end
end

for _, name in ORDER do
	local service = S[name]
	if service and service.Start then
		task.spawn(function()
			local ok, err = pcall(service.Start, service)
			if not ok then
				warn("[MegaTycoon] Start failed for " .. name .. ": " .. tostring(err))
			end
		end)
	end
end

workspace:SetAttribute("ServerReady", true)
print("[MegaTycoon] Server started - v" .. require(game:GetService("ReplicatedStorage").Shared.Config).Version)
