--[[ Small helpers shared by server and client ]]
local Util = {}

local SUFFIXES = {
	"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc",
	"Ud", "Dd", "Td", "Qad", "Qid", "Sxd", "Spd", "Ocd", "Nod", "Vg",
}

-- true for real numbers (not NaN, not +/-inf)
function Util.IsFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- tonumber() that only accepts finite numbers (Luau's tonumber parses "nan" and "inf")
function Util.Number(value: any): number?
	local n = tonumber(value)
	if n == nil or not Util.IsFinite(n) then
		return nil
	end
	return n
end

-- 1234567 -> "1.23M"
function Util.Abbreviate(n: number): string
	n = tonumber(n) or 0
	if n ~= n then
		return "0"
	elseif n == math.huge then
		return "∞"
	elseif n == -math.huge then
		return "-∞"
	end
	local negative = n < 0
	n = math.abs(n)
	if n < 1000 then
		local s = tostring(math.floor(n))
		return negative and "-" .. s or s
	end
	if n >= 1000 ^ #SUFFIXES then
		-- past the last suffix
		local text = string.format("%.2e", n)
		return negative and "-" .. text or text
	end
	local index = math.clamp(math.floor(math.log10(n) / 3), 0, #SUFFIXES - 1)
	local value = n / (1000 ^ index)
	-- log10 can land just below an integer (999.99...): fix the suffix
	if value >= 1000 and index < #SUFFIXES - 1 then
		index += 1
		value /= 1000
	elseif value < 1 and index > 0 then
		index -= 1
		value *= 1000
	end
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
	n = tonumber(n) or 0
	if not Util.IsFinite(n) or math.abs(n) >= 1e15 then
		return Util.Abbreviate(n)
	end
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""):gsub("^%-,", "-"))
end

-- 3725 -> "1h 2m 5s"
function Util.FormatTime(seconds: number): string
	seconds = math.max(0, math.floor(Util.Number(seconds) or 0))
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
	seconds = math.max(0, math.floor(Util.Number(seconds) or 0))
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

-- Fill in keys missing from `data` with values from `template`. Values of
-- the wrong type (corrupted saves) and NaN / inf numbers are replaced too.
function Util.Reconcile(data: { [any]: any }, template: { [any]: any })
	for k, v in template do
		local current = data[k]
		if current == nil or type(current) ~= type(v) or (type(v) == "number" and not Util.IsFinite(current)) then
			data[k] = Util.DeepCopy(v)
		elseif type(v) == "table" then
			Util.Reconcile(current, v)
		end
	end
	return data
end

-- Replace NaN / inf numbers anywhere in `t` (so a save can never fail on them).
-- Returns how many values were fixed.
function Util.Sanitize(t: { [any]: any }, template: { [any]: any }?, depth: number?): number
	local fixed = 0
	if (depth or 0) > 20 then
		return 0
	end
	for k, v in t do
		if type(v) == "number" and not Util.IsFinite(v) then
			local default = template and template[k]
			t[k] = type(default) == "number" and default or 0
			fixed += 1
		elseif type(v) == "table" then
			local sub = template and type(template[k]) == "table" and template[k] or nil
			fixed += Util.Sanitize(v, sub, (depth or 0) + 1)
		end
	end
	return fixed
end

return Util
