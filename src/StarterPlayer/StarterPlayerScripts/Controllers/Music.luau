--[[
	Music - background playlist with a now-playing widget (skip / mute).
	Switches to the minigame playlist while you're in a minigame and
	supports admin "DJ" overrides (;music <id>).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local Theme = UIKit.Theme

local Music = {}
local C

local sound: Sound
local volume = Config.Music.DefaultVolume
local muted = false
local mode = "Lobby" -- Lobby | Minigame | Override
local override = nil
local index = 0
local generation = 0
local failures = 0
local titleLabel: TextLabel
local widget: Frame

local function targetVolume()
	return muted and 0 or volume
end

function Music:Init(controllers)
	C = controllers
	sound = Instance.new("Sound")
	sound.Name = "BackgroundMusic"
	sound.Volume = 0
	sound.Looped = false
	sound.Parent = SoundService

	-- widget (bottom left)
	widget = UIKit.new("Frame", {
		Name = "MusicWidget",
		Size = UDim2.fromOffset(250, 44),
		Position = UDim2.new(0, 12, 1, -12),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.15,
		Parent = C.UI.Gui,
	})
	UIKit.Corner(widget, 12)
	UIKit.Stroke(widget, Color3.new(0, 0, 0), 2, 0.3)
	local note = UIKit.Label({ Text = "🎵", Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(8, 7), Parent = widget })
	note:AddTag("UISpin")
	titleLabel = UIKit.Label({
		Text = "Loading music...",
		Size = UDim2.new(1, -130, 0, 22),
		Position = UDim2.fromOffset(42, 11),
		Font = Theme.BodyFont,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = widget,
	})
	UIKit.Button({
		Text = "⏭",
		Color = Theme.Accent2,
		Size = UDim2.fromOffset(36, 32),
		Position = UDim2.new(1, -82, 0, 6),
		Parent = widget,
		Callback = function()
			if mode == "Override" then
				mode = player:GetAttribute("InMinigame") and "Minigame" or "Lobby"
			end
			self:Next()
		end,
	})
	local muteButton
	muteButton = UIKit.Button({
		Text = "🔊",
		Color = Theme.Purple,
		Size = UDim2.fromOffset(36, 32),
		Position = UDim2.new(1, -42, 0, 6),
		Parent = widget,
		Callback = function()
			muted = not muted
			muteButton.Text = muted and "🔇" or "🔊"
			TweenService:Create(sound, TweenInfo.new(0.3), { Volume = targetVolume() }):Play()
		end,
	})

	Remotes.Music.OnClientEvent:Connect(function(action, params)
		if action == "play" and params and params.Id then
			override = params
			mode = "Override"
			self:Play(params.Id, params.Name)
		elseif action == "resume" then
			override = nil
			mode = player:GetAttribute("InMinigame") and "Minigame" or "Lobby"
			self:Next()
		end
	end)

	player:GetAttributeChangedSignal("InMinigame"):Connect(function()
		if mode == "Override" then
			return
		end
		local newMode = player:GetAttribute("InMinigame") and "Minigame" or "Lobby"
		if newMode ~= mode then
			mode = newMode
			index = 0
			self:Next()
		end
	end)

	player:GetAttributeChangedSignal("MusicVolume"):Connect(function()
		local v = player:GetAttribute("MusicVolume")
		if type(v) == "number" then
			self:SetVolume(v, true)
		end
	end)

	sound.Ended:Connect(function()
		if mode == "Override" and override then
			sound:Play()
		else
			self:Next()
		end
	end)
end

function Music:SetVolume(v: number, fromServer: boolean?)
	volume = math.clamp(v, 0, 1)
	sound.Volume = targetVolume()
	if not fromServer then
		Remotes.SaveSettings:FireServer({ MusicVolume = volume })
	end
end

function Music:GetVolume()
	return volume
end

function Music:SetWidgetVisible(visible: boolean)
	widget.Visible = visible
end

function Music:Play(id: string, name: string?)
	generation += 1
	local myGen = generation
	TweenService:Create(sound, TweenInfo.new(0.6), { Volume = 0 }):Play()
	task.wait(0.6)
	if myGen ~= generation then
		return
	end
	sound:Stop()
	sound.SoundId = id
	sound.TimePosition = 0
	sound:Play()
	titleLabel.Text = name or "Unknown Track"
	TweenService:Create(sound, TweenInfo.new(1.2), { Volume = targetVolume() }):Play()

	-- skip tracks that fail to load
	task.delay(8, function()
		if myGen ~= generation then
			return
		end
		if not sound.IsLoaded or sound.TimeLength == 0 then
			failures += 1
			local playlist = Config.Music[mode] or Config.Music.Lobby
			if failures >= #playlist + 1 then
				titleLabel.Text = "No music (set IDs in Config)"
				return
			end
			self:Next()
		else
			failures = 0
		end
	end)
end

function Music:Next()
	local playlist = Config.Music[mode == "Override" and "Lobby" or mode] or Config.Music.Lobby
	if #playlist == 0 then
		titleLabel.Text = "No music"
		return
	end
	index = index % #playlist + 1
	local track = playlist[index]
	task.spawn(self.Play, self, track.Id, track.Name)
end

function Music:Start()
	local v = player:GetAttribute("MusicVolume")
	if type(v) == "number" then
		volume = v
	end
	-- wait for the loading screen (with a safety timeout)
	local waited = 0
	while not player:GetAttribute("LoadingDone") and waited < 45 do
		waited += task.wait(0.25)
	end
	index = math.random(0, math.max(#Config.Music.Lobby - 1, 0))
	self:Next()
end

return Music
