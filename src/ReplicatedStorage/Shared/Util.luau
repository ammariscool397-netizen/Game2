--[[ Small helpers shared by server and client ]]
local Util = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- 1234567 -> "1.23M"
function Util.Abbreviate(n: number): string
	n = tonumber(n) or 0
	local negative = n < 0
	n = math.abs(n)
	if n < 1000 then
		local s = tostring(math.floor(n))
		return negative and "-" .. s or s
	end
	local index = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local value = n / (1000 ^ index)
	local text
	if value >= 100 then
		text = string.format("%d", math.floor(value))
	elseif value >= 10 then
		text = string.format("%.1f", math.floor(value * 10) / 10)
	else
		text = string.format("%.2f", math.floor(value * 100) / 100)
	end
	if text:find("%.") then
		text = (text:gsub("0+$", ""):gsub("%.$", ""))
	end
	text ..= SUFFIXES[index + 1]
	return negative and "-" .. text or text
end

function Util.Money(n: number): string
	return "$" .. Util.Abbreviate(n)
end

-- 1234567 -> "1,234,567"
function Util.Commas(n: number): string
	local s = tostring(math.floor(tonumber(n) or 0))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""):gsub("^%-,", "-"))
end

-- 3725 -> "1h 2m 5s"
function Util.FormatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%dh %dm %ds", h, m, s)
	elseif m > 0 then
		return string.format("%dm %ds", m, s)
	end
	return string.format("%ds", s)
end

function Util.Clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function Util.DeepCopy<T>(t: T): T
	if type(t) ~= "table" then
		return t
	end
	local copy = {}
	for k, v in t :: any do
		copy[k] = Util.DeepCopy(v)
	end
	return copy :: any
end

-- Fill in keys missing from `data` with values from `template`
function Util.Reconcile(data: { [any]: any }, template: { [any]: any })
	for k, v in template do
		if data[k] == nil then
			data[k] = Util.DeepCopy(v)
		elseif type(v) == "table" and type(data[k]) == "table" then
			Util.Reconcile(data[k], v)
		end
	end
	return data
end

return Util
