--[[ UI - owns the main ScreenGui and the "one panel at a time" manager ]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UIKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UIKit"))

local player = Players.LocalPlayer

local UI = {}
UI.Gui = nil :: ScreenGui?
UI.Panels = {}
UI.Current = nil :: string?

local blur: BlurEffect

function UI:Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MegaTycoonUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	self.Gui = gui

	-- overlay layer for full-screen effects (flash, confetti, cash bursts)
	local fx = Instance.new("ScreenGui")
	fx.Name = "MegaTycoonFX"
	fx.ResetOnSpawn = false
	fx.IgnoreGuiInset = true
	fx.DisplayOrder = 20
	fx.Parent = player.PlayerGui
	self.FX = fx

	blur = Instance.new("BlurEffect")
	blur.Name = "UIBlur"
	blur.Size = 0
	blur.Parent = Lighting

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Escape and self.Current then
			self:Close()
		end
	end)
end

function UI:Start()
	-- show HUD once the loading screen is gone
	-- wait for the loading screen (with a safety timeout)
	local waited = 0
	while not player:GetAttribute("LoadingDone") and waited < 45 do
		waited += task.wait(0.25)
	end
	self.Gui.Enabled = true
end

-- Scale-based size so panels fit phones and big screens
function UI:PanelSize(maxW: number, maxH: number)
	return UDim2.new(0.9, 0, 0.82, 0), Vector2.new(maxW, maxH)
end

function UI:Register(name: string, frame: Frame, closeButton: GuiButton?, onOpen: (() -> ())?)
	self.Panels[name] = { Frame = frame, OnOpen = onOpen }
	if closeButton then
		closeButton.Activated:Connect(function()
			UIKit.PlaySound("Click", 0.5)
			self:Close()
		end)
	end
end

function UI:Open(name: string)
	local panel = self.Panels[name]
	if not panel then
		return
	end
	if self.Current and self.Current ~= name then
		local old = self.Panels[self.Current]
		if old then
			old.Frame.Visible = false
		end
	end
	self.Current = name
	UIKit.Open(panel.Frame)
	TweenService:Create(blur, TweenInfo.new(0.25), { Size = 14 }):Play()
	if panel.OnOpen then
		task.spawn(panel.OnOpen)
	end
end

function UI:Close()
	if not self.Current then
		return
	end
	local panel = self.Panels[self.Current]
	self.Current = nil
	if panel then
		UIKit.Close(panel.Frame)
	end
	TweenService:Create(blur, TweenInfo.new(0.25), { Size = 0 }):Play()
end

function UI:Toggle(name: string)
	if self.Current == name then
		self:Close()
	else
		self:Open(name)
	end
end

-- Builds a standard panel and registers it. Returns (frame, content)
function UI:MakePanel(name: string, title: string, color: Color3, maxW: number?, maxH: number?, onOpen: (() -> ())?)
	local frame, content, close = UIKit.Panel({
		Name = name,
		Title = title,
		Color = color,
		Size = UDim2.new(0.92, 0, 0.8, 0),
		MaxWidth = maxW or 760,
		Parent = self.Gui,
	})
	local constraint = frame:FindFirstChildOfClass("UISizeConstraint")
	if constraint then
		constraint.MaxSize = Vector2.new(maxW or 760, maxH or 520)
	end
	self:Register(name, frame, close, onOpen)
	return frame, content
end

return UI
