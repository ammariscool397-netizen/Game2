--[[
	MEGA TYCOON - client bootstrap. Loads every controller in Controllers/,
	calls :Init(C) on each (C = registry of all controllers), then :Start().
]]
local controllersFolder = script.Parent:WaitForChild("Controllers")

local ORDER = {
	"UI",
	"Notifications",
	"Music",
	"VFX",
	"Animator",
	"Build",
	"HUD",
	"Shop",
	"Panels",
	"Duo",
	"Disasters",
	"Quests",
	"Gifts",
	"Wheel",
	"Shield",
	"Pets",
	"Travel",
	"Guide",
	"DropVisuals",
	"Admin",
	"Minigame",
	"ChatTags",
}

local C = {}
for _, name in ORDER do
	local module = controllersFolder:WaitForChild(name, 10)
	if module then
		local ok, result = pcall(require, module)
		if ok then
			C[name] = result
		else
			warn("[MegaTycoon] Failed to load controller " .. name .. ": " .. tostring(result))
		end
	end
end

for _, name in ORDER do
	local controller = C[name]
	if controller and controller.Init then
		local ok, err = pcall(controller.Init, controller, C)
		if not ok then
			warn("[MegaTycoon] Init failed for " .. name .. ": " .. tostring(err))
		end
	end
end

for _, name in ORDER do
	local controller = C[name]
	if controller and controller.Start then
		task.spawn(function()
			local ok, err = pcall(controller.Start, controller)
			if not ok then
				warn("[MegaTycoon] Start failed for " .. name .. ": " .. tostring(err))
			end
		end)
	end
end
