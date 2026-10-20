--[[
	EventService - calendar events (Config.LiveEvents): the weekend bonus and
	yearly holidays. While events run, everybody earns the biggest multiplier
	(workspace attribute "LiveEventMult") and the event eggs are on sale.
	Admins can force an event on or off with ;event.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local LE = Config.LiveEvents

local EventService = {}
local S

local forced: { [string]: boolean? } = {} -- admin overrides: true = on, false = off
local lastActive: { [string]: boolean } = {}
local booted = false

-- the clock (tests replace this to pretend it is another date)
EventService.Clock = function(): number
	return os.time()
end

local function inDates(dates, month: number, day: number): boolean
	local from = dates.From[1] * 100 + dates.From[2]
	local to = dates.To[1] * 100 + dates.To[2]
	local today = month * 100 + day
	if from <= to then
		return today >= from and today <= to
	end
	return today >= from or today <= to -- a window over New Year
end

-- is an event running at this unix time (UTC)?
function EventService:IsRunningAt(event, time: number): boolean
	local date = os.date("!*t", time)
	if event.Weekly then
		local startHour = event.Weekly[date.wday]
		return startHour ~= nil and date.hour >= startHour
	end
	if event.Dates then
		return inDates(event.Dates, date.month, date.day)
	end
	return false
end

function EventService:IsActive(id: string): boolean
	local override = forced[id]
	if override ~= nil then
		return override == true
	end
	if not LE.Enabled then
		return false
	end
	for _, event in LE.List do
		if event.Id == id then
			return self:IsRunningAt(event, self.Clock())
		end
	end
	return false
end

function EventService:GetActive()
	local list = {}
	for _, event in LE.List do
		if self:IsActive(event.Id) then
			table.insert(list, event)
		end
	end
	return list
end

function EventService:Force(id: string, state: boolean?)
	forced[id] = state
	self:Update()
end

function EventService:GetEvent(id: string)
	for _, event in LE.List do
		if event.Id == id then
			return event
		end
	end
	return nil
end

-- sets the multiplier and tells everyone when an event starts or ends
function EventService:Update()
	local multiplier, ids = 1, {}
	local active = {}
	for _, event in self:GetActive() do
		multiplier = math.max(multiplier, event.Multiplier)
		table.insert(ids, event.Id)
		active[event.Id] = true
	end
	local changed = multiplier ~= (workspace:GetAttribute("LiveEventMult") or 1)
	workspace:SetAttribute("LiveEventMult", multiplier)
	workspace:SetAttribute("LiveEvents", table.concat(ids, ","))
	if booted then
		for _, event in LE.List do
			if active[event.Id] and not lastActive[event.Id] then
				Remotes.Announce:FireAllClients({ Title = event.Icon .. " " .. event.Name:upper() .. "!", Text = event.Text, Color = event.Color })
				Remotes.VFX:FireAllClients("Confetti", {})
			elseif lastActive[event.Id] and not active[event.Id] then
				Remotes.Announce:FireAllClients({ Title = event.Icon .. " " .. event.Name .. " is over", Text = "See you next time!", Color = Color3.fromRGB(200, 200, 200) })
			end
		end
	end
	lastActive = active
	if changed and S.DataService then
		for _, player in Players:GetPlayers() do
			S.DataService:RefreshMultiplier(player)
		end
	end
end

function EventService:Init(services)
	S = services
	workspace:SetAttribute("LiveEventMult", 1)
	workspace:SetAttribute("LiveEvents", "")
	self:Update()
	booted = true
end

function EventService:Start()
	while true do
		task.wait(30)
		Util.Try("Live events", self.Update, self)
	end
end

return EventService
