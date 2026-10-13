--[[ ChatTags - [Owner] / [Admin] / [VIP] / rebirth tags in the chat ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local ChatTags = {}

local RANK_COLORS = {
	[1] = "#4FC3F7",
	[2] = "#66BB6A",
	[3] = "#FFA726",
	[4] = "#EF5350",
}

function ChatTags:Init()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		return
	end
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local properties = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		if not source then
			return properties
		end
		local sender = Players:GetPlayerByUserId(source.UserId)
		if not sender then
			return properties
		end
		local tags = {}
		local rank = sender:GetAttribute("AdminRank") or 0
		if rank > 0 then
			table.insert(tags, string.format("<font color='%s'>[%s]</font>", RANK_COLORS[rank] or "#FFFFFF", Config.RankNames[rank]))
		end
		if sender:GetAttribute("Pass_VIP") then
			table.insert(tags, "<font color='#FFD700'>[👑 VIP]</font>")
		end
		local rebirths = sender:GetAttribute("Rebirths") or 0
		if rebirths > 0 then
			table.insert(tags, string.format("<font color='#CE93D8'>[R%d]</font>", rebirths))
		end
		if #tags > 0 then
			properties.PrefixText = table.concat(tags, " ") .. " " .. message.PrefixText
		end
		return properties
	end
end

return ChatTags
