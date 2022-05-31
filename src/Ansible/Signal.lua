--------------------------------------------------------------------------------
--               Batched Yield-Safe Signal Implementation                     --
-- This is a Signal class which has effectively identical behavior to a       --
-- normal RBXScriptSignal, with the only difference being a couple extra      --
-- stack frames at the bottom of the stack trace when an error is thrown.     --
-- This implementation caches runner coroutines, so the ability to yield in   --
-- the signal handlers comes at minimal extra cost over a naive signal        --
-- implementation that either always or never spawns a thread.                --
--                                                                            --
-- API:                                                                       --
--   local Signal = require(THIS MODULE)                                      --
--   local sig = Signal.new()                                                 --
--   local connection = sig:Connect(function(arg1, arg2, ...) ... end)        --
--   sig:Fire(arg1, arg2, ...)                                                --
--   connection:Disconnect()                                                  --
--   sig:DisconnectAll()                                                      --
--   local arg1, arg2, ... = sig:Wait()                                       --
--                                                                            --
-- Licence:                                                                   --
--   Licenced under the MIT licence.                                          --
--                                                                            --
-- Authors:                                                                   --
--   stravant - July 31st, 2021 - Created the file.                           --
--   dimitriye98 - May 31st, 2022 - Added Moonwave doc and Luau types         --
--------------------------------------------------------------------------------

-- The currently idle thread to run the next handler on
local freeRunnerThread = nil

-- Function which acquires the currently idle handler runner thread, runs the
-- function fn on it, and then releases the thread, returning it to being the
-- currently idle one.
-- If there was a currently idle runner thread already, that's okay, that old
-- one will just get thrown and eventually GCed.
local function acquireRunnerThreadAndCallEventHandler(fn, ...)
	local acquiredRunnerThread = freeRunnerThread
	freeRunnerThread = nil
	fn(...)
	-- The handler finished running, this runner thread is free again.
	freeRunnerThread = acquiredRunnerThread
end

-- Coroutine runner that we create coroutines of. The coroutine can be
-- repeatedly resumed with functions to run followed by the argument to run
-- them with.
local function runEventHandlerInFreeThread(...)
	acquireRunnerThreadAndCallEventHandler(...)
	while true do
		acquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

-- Connection class
type Connection = {
	Disconnect: (Connection) -> ()
}
--[=[
	@class Connection

	Emulates [RBXScriptConnection](https://developer.roblox.com/en-us/api-reference/datatype/RBXScriptConnection)
]=]
--[=[
	@prop Connected bool
	@within Connection

	A read-only field indicating whether or not the connection is connected
	@readonly
]=]
local Connection = {}
Connection.__index = Connection


function Connection.new(signal, fn): Connection
	return setmetatable({
		_connected = true,
		_signal = signal,
		_fn = fn,
		_next = false,
	}, Connection)
end

--[=[
	Disconnects the connection
]=]
function Connection:Disconnect()
	assert(self._connected, "Can't disconnect a connection twice.", 2)
	self._connected = false

	-- Unhook the node, but DON'T clear it. That way any fire calls that are
	-- currently sitting on this node will be able to iterate forwards off of
	-- it, but any subsequent fire calls will not hit it, and it will be GCed
	-- when no more fire calls are sitting on it.
	if self._signal._handlerListHead == self then
		self._signal._handlerListHead = self._next
	else
		local prev = self._signal._handlerListHead
		while prev and prev._next ~= self do
			prev = prev._next
		end
		if prev then
			prev._next = self._next
		end
	end
end

-- Make Connection strict
setmetatable(Connection, {
	__index = function(tb, key)
		if key == "Connected" then
			return tb._connected
		end
		error(("Attempt to get Connection::%s (not a valid member)"):format(tostring(key)), 2)
	end,
	__newindex = function(tb, key, value)
		if key == "Connected" then
			error("Connected cannot be assigned to", 2)
		end
		error(("Attempt to set Connection::%s (not a valid member)"):format(tostring(key)), 2)
	end
})

-- Signal class
type Signal = {
	Connect: (Signal, (...any) -> ()) -> Connection,
	DisconnectAll: (Signal) -> (),
	Fire: (Signal, ...any) -> (),
	Wait: (Signal, ...any) -> ()
}
--[=[
	@class Signal
	@private
	@ignore
]=]
local Signal = {}
Signal.__index = Signal

function Signal.new(): Signal
	return setmetatable({
		_handlerListHead = false,
	}, Signal)
end

--[=[
	Connects a listener to the signal
	@param listener (...any) -> ()
	@return Connection
]=]
function Signal:Connect(listener: (...any) -> ()): Connection
	local connection = Connection.new(self, listener)
	if self._handlerListHead then
		connection._next = self._handlerListHead
		self._handlerListHead = connection
	else
		self._handlerListHead = connection
	end
	return connection
end

--[=[
	Disconnect all handlers.
]=]
function Signal:DisconnectAll()
	-- Since we use a linked list it suffices to clear the
	-- reference to the head handler.
	self._handlerListHead = false
end

--[=[
	Fires the Signal
	@param ...? -- the parameters to pass to any listeners
]=]
function Signal:Fire(...: any)
	-- Signal:Fire(...) implemented by running the handler functions on the
	-- coRunnerThread, and any time the resulting thread yielded without returning
	-- to us, that means that it yielded to the Roblox scheduler and has been taken
	-- over by Roblox scheduling, meaning we have to make a new coroutine runner.
	local item = self._handlerListHead
	while item do
		if item._connected then
			if not freeRunnerThread then
				freeRunnerThread = coroutine.create(runEventHandlerInFreeThread)
			end
			task.spawn(freeRunnerThread, item._fn, ...)
		end
		item = item._next
	end
end

--- Blocks on the signal until it's fired
function Signal:Wait(): ...any
	-- Implement Signal:Wait() in terms of a temporary connection using
	-- a Signal:Connect() which disconnects itself.
	local waitingCoroutine = coroutine.running()
	local cn;
	cn = self:Connect(function(...)
		cn:Disconnect()
		task.spawn(waitingCoroutine, ...)
	end)
	return coroutine.yield()
end

-- Make signal strict
setmetatable(Signal, {
	__index = function(tb, key)
		error(("Attempt to get Signal::%s (not a valid member)"):format(tostring(key)), 2)
	end,
	__newindex = function(tb, key, value)
		error(("Attempt to set Signal::%s (not a valid member)"):format(tostring(key)), 2)
	end
})

return Signal