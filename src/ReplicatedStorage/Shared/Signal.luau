--[[ Minimal signal class used for server-side events between services ]]
local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (self: Connection) -> () }

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	local handler = { fn = fn, connected = true }
	table.insert(self._handlers, handler)
	local signal = self
	return {
		Disconnect = function()
			handler.connected = false
			local index = table.find(signal._handlers, handler)
			if index then
				table.remove(signal._handlers, index)
			end
		end,
	}
end

function Signal:Fire(...)
	for _, handler in table.clone(self._handlers) do
		if handler.connected then
			task.spawn(handler.fn, ...)
		end
	end
end

return Signal
