--[[
	All networking goes through these remotes. The server creates them,
	the client waits for them. Usage: Remotes.Notify:FireClient(...)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	"Notify", -- server -> client  { Text, Type, Duration }
	"Announce", -- server -> all    { Title, Text, Color }
	"VFX", -- server -> client  (effectName, params)
	"Music", -- server -> client  (action, params)
	"ClientCommand", -- server -> client  (command, ...) fly/noclip/fling/launch/abduct/openfloors...
	"MinigameState", -- server -> client  state table
	"MinigameJoin", -- client -> server
	"RequestRebirth", -- client -> server
	"BuyPass", -- client -> server  (passKey)
	"BuyProduct", -- client -> server  (productKey)
	"GoHome", -- client -> server
	"SaveSettings", -- client -> server  (settings)
	"TycoonUpdate", -- server -> client  { Type = "Bought"|"Reset"|"Disabled"|"Repaired"|"Secret", ... }
	"BuyAll", -- client -> server
	"TeleportFloor", -- client -> server  (plotIndex, floor)
	"Disaster", -- server -> client  disaster state
	"DuoInvite", -- client -> server  (targetUserId)
	"DuoRespond", -- client -> server  (hostUserId, accept)
	"DuoLeave", -- client -> server  (kick partner if host / leave if partner)
	"DuoInvited", -- server -> client  { HostName, HostUserId, Timeout }
	"QuestUpdate", -- server -> client  (quests, claimedCount)
	"GiftUpdate", -- server -> client  { Index, ReadyIn, Total }
	"WeeklyUpdate", -- server -> client  { Days, DayFlags, Claimed, ResetsIn }
	"PetUpdate", -- server -> client  { Owned, Equipped, Slots, Eggs }
	"GiftItem", -- client -> server  ("Pass"|"Product", key, targetUserId)
	"TradeInvited", -- server -> client  { FromName, FromUserId, Timeout }
	"TradeUpdate", -- server -> client  trade state (nil = no trade)
	"TutorialClaim", -- client -> server  (finished the tutorial; the server checks)
}

local FUNCTIONS = {
	"RedeemCode", -- (code) -> ok, message
	"ClaimDaily", -- () -> ok, message
	"AdminCommand", -- (text) -> ok, message
	"AdminData", -- (what) -> data
	"BuyItem", -- (itemId) -> ok, message
	"GetTycoonState", -- () -> state
	"ClaimQuest", -- (quest type or slot) -> ok, message
	"ClaimGift", -- () -> ok, message
	"SpinWheel", -- () -> ok, segment index (0 if none), message
	"ActivateShield", -- () -> ok, message
	"Travel", -- (island id or "Plaza") -> ok, message
	"ClaimWeekly", -- (milestone index) -> ok, message
	"AchievementsGet", -- () -> { List = { {Id, Progress, Done} }, Done }
	"SeasonGet", -- () -> season state
	"SeasonClaim", -- (track "Free"|"Premium", level) -> ok, message
	"CosmeticsGet", -- () -> { Owned, Equipped }
	"CosmeticsAction", -- (action "Buy"|"Equip"|"Unequip", id|kind) -> ok, message
	"TradeAction", -- (action, arg) -> ok, message   (Invite userId | Respond bool | Add uid | Remove uid | Accept | Cancel)
	"StatsGet", -- () -> list of {Label, Value}
	"BoardsGet", -- () -> { Earned, Rebirths, Hatched }
	"SocialGet", -- () -> { Group, Claimed, Private }
	"SocialAction", -- ("ClaimGroup") -> ok, message
	"PetAction", -- (action, arg) -> ok, message   (Hatch eggId | Equip uid | Unequip uid | Sell uid | EquipBest | Refresh)
}

local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		folder = existing :: Folder
	else
		local created = Instance.new("Folder")
		created.Name = "Remotes"
		for _, name in EVENTS do
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = created
		end
		for _, name in FUNCTIONS do
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = created
		end
		created.Parent = ReplicatedStorage
		folder = created
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

local Remotes = {}
setmetatable(Remotes, {
	__index = function(_, name)
		local remote = folder:WaitForChild(name, 15)
		if not remote then
			error("Remote not found: " .. tostring(name))
		end
		rawset(Remotes, name, remote)
		return remote
	end,
})

return Remotes :: any
