--[[ Gifts (client) - the playtime gift button (bottom right) ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local Theme = UIKit.Theme

local Gifts = {}
Gifts.State = nil :: { Index: number, Total: number, ReadyAt: number }?
local C

local button: TextButton
local busy = false

local function refresh()
	local state = Gifts.State
	if not state or state.Index > state.Total then
		button.Visible = false
		return
	end
	button.Visible = not player:GetAttribute("InMinigame")
	local left = state.ReadyAt - os.clock()
	if left <= 0 then
		button.Text = "🎁 OPEN GIFT " .. state.Index .. "/" .. state.Total .. "!"
		button.BackgroundColor3 = Theme.Green
	else
		button.Text = "🎁 Gift " .. state.Index .. "/" .. state.Total .. " in " .. Util.Clock(left)
		button.BackgroundColor3 = Theme.PanelLight
	end
end

function Gifts:IsReady(): boolean
	return self.State ~= nil and self.State.Index <= self.State.Total and self.State.ReadyAt - os.clock() <= 0
end

function Gifts:Init(controllers)
	C = controllers
	button = UIKit.Button({
		Name = "GiftButton",
		Text = "🎁",
		Color = Theme.PanelLight,
		Size = UDim2.fromOffset(240, 50),
		Position = UDim2.new(1, -12, 1, -14),
		AnchorPoint = Vector2.new(1, 1),
		Parent = C.UI.Gui,
		Callback = function()
			if busy or not self:IsReady() then
				return
			end
			busy = true
			local ok, message = Remotes.ClaimGift:InvokeServer()
			busy = false
			C.Notifications:Toast(tostring(message), ok and "success" or "error")
		end,
	})
	button.Visible = false
	local scale = button:FindFirstChildOfClass("UIScale") :: UIScale
	Remotes.GiftUpdate.OnClientEvent:Connect(function(state)
		if type(state) ~= "table" then
			return
		end
		local wasReady = self:IsReady()
		self.State = { Index = state.Index, Total = state.Total, ReadyAt = os.clock() + math.max(0, state.ReadyIn or 0) }
		refresh()
		if not wasReady and self:IsReady() and scale then
			scale.Scale = 1.2
			TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end)
end

function Gifts:Start()
	local announced = 0
	while true do
		task.wait(1)
		Util.Try("Gifts", refresh)
		-- tell the player once when a gift unlocks
		local state = self.State
		if state and self:IsReady() and announced < state.Index then
			announced = state.Index
			C.Notifications:Toast("🎁 A playtime gift is ready! Open it in the bottom-right corner.", "success")
			UIKit.PlaySound("Notify", 0.6, 1.3)
		end
	end
end

return Gifts
