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
	"ClientCommand", -- server -> client  (command, ...) used by admin fly/noclip/etc
	"MinigameState", -- server -> client  state table
	"MinigameJoin", -- client -> server
	"RequestRebirth", -- client -> server
	"BuyPass", -- client -> server  (passKey)
	"BuyProduct", -- client -> server  (productKey)
	"GoHome", -- client -> server
	"SaveSettings", -- client -> server  (settings)
}

local FUNCTIONS = {
	"RedeemCode", -- (code) -> ok, message
	"ClaimDaily", -- () -> ok, message
	"AdminCommand", -- (text) -> ok, message
	"AdminData", -- (what) -> data
	"GetLeaderboard", -- () -> rows
}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		for _, name in EVENTS do
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		for _, name in FUNCTIONS do
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
		folder.Parent = ReplicatedStorage
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
