--[[ ChatTags - [Owner] / [Admin] / [VIP] / rebirth tags in the chat ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local ChatTags = {}

-- the glow of titles above heads: the outline pulses, "rainbow" titles cycle colours
function ChatTags:Start()
	local CollectionService = game:GetService("CollectionService")
	local RunService = game:GetService("RunService")
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		for _, label in CollectionService:GetTagged("GlowTitle") do
			if label:IsA("TextLabel") then
				local stroke = label:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Transparency = 0.25 + 0.3 * (0.5 + 0.5 * math.sin(t * 3))
				end
				if label:GetAttribute("Rainbow") then
					local color = Color3.fromHSV((t * 0.25) % 1, 0.75, 1)
					label.TextColor3 = color
					if stroke then
						stroke.Color = color
					end
				end
			end
		end
	end)
end

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
		local titleText = sender:GetAttribute("TitleText")
		if type(titleText) == "string" and titleText ~= "" then
			local titleColor = sender:GetAttribute("TitleColor")
			local hex = (type(titleColor) == "string" and titleColor:sub(1, 1) == "#") and titleColor or "#FFD700"
			table.insert(tags, string.format("<font color='%s'>[%s]</font>", hex, (titleText:gsub("[<>&]", ""))))
		end
		local found = sender:GetAttribute("SecretsFound") or ""
		if found ~= "" and #string.split(found, ",") >= #Config.Secrets then
			table.insert(tags, "<font color='#80FF9A'>[🕵️ Secret Master]</font>")
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
