--[[ Social (client) - group reward, friends who are in the game (join them), invite friends, private-server info ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local Theme = UIKit.Theme

local Social = {}
local C

local scroll: ScrollingFrame

local function section(order: number, text: string)
	return UIKit.Label({ Text = text, Size = UDim2.new(1, -10, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Accent, LayoutOrder = order, ZIndex = 8, Parent = scroll })
end

local function note(order: number, text: string, height: number?, color: Color3?)
	local label = UIKit.new("TextLabel", {
		Text = text,
		Size = UDim2.new(1, -10, 0, height or 40),
		BackgroundTransparency = 1,
		TextWrapped = true,
		TextSize = 15,
		Font = Theme.BodyFont,
		TextColor3 = color or Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = order,
		ZIndex = 8,
		Parent = scroll,
	})
	return label
end

local function refresh()
	UIKit.Clear(scroll)
	local state = Remotes.SocialGet:InvokeServer()
	if not state then
		return
	end
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	section(nextOrder(), "👥 Group reward")
	if state.GroupId == 0 then
		note(nextOrder(), "A group reward hasn't been set up yet.")
	elseif state.Claimed then
		note(nextOrder(), "✓ You already claimed the group reward. Thank you!", 30, Theme.Green)
	else
		note(nextOrder(), "Join our Roblox group for free cash and a 2x boost! " .. state.GroupLink, 44)
		local row = UIKit.Row(scroll, nextOrder(), 50)
		UIKit.Label({ Text = state.InGroup and "You're in the group - claim it!" or "Join the group, then press Claim", Size = UDim2.new(1, -190, 1, -16), Position = UDim2.fromOffset(12, 8), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.BodyFont, ZIndex = 8, Parent = row })
		UIKit.Button({ Text = "🎁 CLAIM", Color = Theme.Green, Size = UDim2.fromOffset(160, 38), Position = UDim2.new(1, -170, 0, 6), ZIndex = 8, Parent = row, Callback = function()
			local ok, message = Remotes.SocialAction:InvokeServer("ClaimGroup")
			C.Notifications:Toast(tostring(message), ok and "success" or "error", 4)
			refresh()
		end })
	end

	section(nextOrder(), "🏠 Private server")
	if state.Private then
		note(nextOrder(), "✓ You're in a private server: +" .. math.floor(state.PrivateBonus * 100) .. "% income!", 30, Theme.Green)
	else
		note(nextOrder(), "Private (VIP) servers earn +" .. math.floor(state.PrivateBonus * 100) .. "% income. Find them on the game's page.", 44)
	end

	section(nextOrder(), "🧑‍🤝‍🧑 Friends")
	local here = math.min(tonumber(player:GetAttribute("FriendsHere")) or 0, Config.Bonuses.MaxFriends)
	note(nextOrder(), here > 0 and ("👫 " .. here .. " friend(s) here: +" .. here * Config.Bonuses.FriendPercent .. "% income!") or ("Play with friends: +" .. Config.Bonuses.FriendPercent .. "% income for each friend in your server (up to " .. Config.Bonuses.MaxFriends .. ")."), 44)
	local inviteRow = UIKit.Row(scroll, nextOrder(), 50)
	UIKit.Label({ Text = "Invite friends to play", Size = UDim2.new(1, -190, 1, -16), Position = UDim2.fromOffset(12, 8), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.BodyFont, ZIndex = 8, Parent = inviteRow })
	UIKit.Button({ Text = "📨 INVITE", Color = Theme.Accent2, Size = UDim2.fromOffset(160, 38), Position = UDim2.new(1, -170, 0, 6), ZIndex = 8, Parent = inviteRow, Callback = function()
		local ok = pcall(function()
			if SocialService:CanSendGameInviteAsync(player) then
				SocialService:PromptGameInvite(player)
			else
				C.Notifications:Toast("You can't send invites right now.", "error", 3)
			end
		end)
		if not ok then
			C.Notifications:Toast("Invites only work in the live game.", "info", 3)
		end
	end })

	-- friends currently playing this game in another server
	local ok, friends = pcall(function()
		return player:GetFriendsOnline(50)
	end)
	local joinable = 0
	if ok and type(friends) == "table" then
		for _, friend in friends do
			if friend.PlaceId == game.PlaceId and friend.GameId and friend.GameId ~= game.JobId then
				joinable += 1
				local row = UIKit.Row(scroll, nextOrder(), 50)
				UIKit.Label({ Text = tostring(friend.DisplayName or friend.UserName), Size = UDim2.new(1, -190, 1, -16), Position = UDim2.fromOffset(12, 8), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8, Parent = row })
				UIKit.Button({ Text = "➡ JOIN", Color = Theme.Green, Size = UDim2.fromOffset(160, 38), Position = UDim2.new(1, -170, 0, 6), ZIndex = 8, Parent = row, Callback = function()
					local teleported = pcall(function()
						TeleportService:TeleportToPlaceInstance(friend.PlaceId, friend.GameId, player)
					end)
					if not teleported then
						C.Notifications:Toast("Couldn't join right now.", "error", 3)
					end
				end })
			end
		end
	end
	if joinable == 0 then
		note(nextOrder(), "None of your friends are playing in another server right now.", 30)
	end
end

function Social:Init(controllers)
	C = controllers
	local _, content = C.UI:MakePanel("Social", "🌐 SOCIAL", Color3.fromRGB(70, 160, 255), 640, 560, refresh)
	scroll = UIKit.Scroll({ Size = UDim2.fromScale(1, 1), Parent = content })
	UIKit.List(scroll, 6)
	UIKit.new("UIPadding", { PaddingRight = UDim.new(0, 8), Parent = scroll })
end

return Social
