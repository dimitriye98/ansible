local Signal = require(script.Parent.Signal)

local isClient = game:GetService("RunService"):IsClient()

local rand = Random.new()
local boundMin, boundMax = -2^53, 2^53
local function newTransactionId()
    return rand:NextInteger(boundMin, boundMax)
end

--[=[
    @class Socket

    Socket abstracts away the underlying RemoteEvents and
    functions as a combination between a RemoteEvent and a RemoteFunction.
]=]
local Socket = {}
do
    Socket.__index = Socket

    if isClient then
        function Socket.new()
            local ret = setmetatable({}, Socket)
            ret._waitingInvocations = {}
            ret._fireQueue = {}
            ret._invocationQueue = {}
            ret._signal = Signal.new()
            return ret
        end

        function Socket:_handleInvoker(transactionId, success, ...)
            local callback = self._waitingInvocations[transactionId]
            if callback then
                -- This is a response to a client request
                self._waitingInvocations[transactionId] = nil
                callback(success, ...)
            else
                -- This is a server request
                if not self._callback then
                    self._invoker:FireServer(transactionId, false)
                    return
                end

                local results = { pcall(self._callback, success, ...) }
                self._invoker:FireServer(transactionId, table.unpack(results))
                if not results[1] then
                    error(results[2])
                end
            end
        end

        function Socket:_bindInvoker(invoker: RemoteEvent)
            self._invoker = invoker
            invoker.OnClientEvent:Connect(function(...) self:_handleInvoker(...) end)
            for _, v in self._invocationQueue do
                self:InvokeServerNonblocking(table.unpack(v))
            end
            self._invocationQueue = nil
        end

        function Socket:_bindEvent(event: RemoteEvent)
            self._event = event
            event.OnClientEvent:Connect(function(...) self._signal:Fire(...) end)
            for _, v in self._fireQueue do
                self:FireServer(table.unpack(v))
            end
            self._fireQueue = nil
        end

        --[=[
            Fires the event on the server

            @param ...? -- the parameters to pass to any listeners
            @client
        ]=]
        function Socket:FireServer(...: any): ()
            if not self._event then
                table.insert(self._fireQueue, {...})
            else
                self._event:FireServer(...)
            end
        end

        --[=[
            Invokes the remote function on the server asynchronously,
            taking a callback to handle the return values

            @param callback
            @param ...? -- the parameters to pass to the remote function
            @client
        ]=]
        function Socket:InvokeServerNonblocking(callback: (...any) -> (), ...: any)
            if not self._invoker then
                table.insert(self._invocationQueue, {callback, ...})
            else
                local transactionId = newTransactionId()
                self._invoker:FireServer(transactionId, ...)
                self._waitingInvocations[transactionId] = callback
            end
        end

        --[=[
            Invokes the remote function on the server and blocks on it

            @param ...? -- the parameters to pass to the remote function
            @return ...any -- the results of the remote function
            @client
            @yields
        ]=]
        function Socket:InvokeServer(...: any)
            local co = coroutine.running()
            self:InvokeServerNonblocking(function (...)
                coroutine.resume(co, ...)
            end, ...)

            return coroutine.yield()
        end

        function Socket:FireClient()
            error("Cannot call FireClient from client")
        end

        function Socket:FireAllClients()
            error("Cannot call FireAllClients from client")
        end

        function Socket:InvokeClient()
            error("Cannot call InvokeClient from client")
        end

        function SocketInvokeClientNonblocking()
            error("Cannot call InvokeClientNonblocking from client")
        end

        function SocketInvokeAllClientsNonblocking()
            error("Cannot call InvokeAllClientsNonblocking from client")
        end
    else
        function Socket.new(event: RemoteEvent, invoker: RemoteEvent)
            local ret = setmetatable({}, Socket)
            ret._event = event
            ret._invoker = invoker
            ret._waitingInvocations = {}
            ret._signal = Signal.new()

            event.OnServerEvent:Connect(function (...) ret._signal:Fire(...) end)

            invoker.OnServerEvent:Connect(function (...) ret:_handleInvoker(...) end)

            return ret
        end

        function Socket:_handleInvoker(player, transactionId, success, ...)
            local callback = self._waitingInvocations[transactionId]
            if callback then
                -- This is a response to a server request
                self._waitingInvocations[transactionId] = nil
                callback(success, ...)
            else
                -- This is a client request
                if not self._callback then
                    self._invoker:FireClient(player, transactionId, false)
                    return
                end

                -- Note that `success` is actually the first argument
                -- of the intended invocation here
                local results = { pcall(self._callback, player, success, ...) }
                self._invoker:FireClient(player, transactionId, table.unpack(results))
                if not results[1] then
                    error(results[2])
                end
            end
        end

        --[=[
            Fires the event on the given client

            @param player -- the player whom to fire the event for
            @param ...? -- the parameters to pass to any listeners
            @server
        ]=]
        function Socket:FireClient(player: Player, ...: any)
            self._event:FireClient(player, ...)
        end

        --[=[
            Fires the event on all connected clients

            @param ...? -- the parameters to pass to any listeners
            @server
        ]=]
        function Socket:FireAllClients(...: any)
            self._event:FireAllClients(...)
        end

        --[=[
            Invokes the remote function on the given client asynchronously
            taking a callback to handle the return values

            @param client -- the client on whom to invoke the remote function
            @param callback
            @param ...? -- the parameters to pass to the remote function
            @server
        ]=]
        function Socket:InvokeClientNonblocking(
                client: Player,
                callback: (...any) -> (),
                ...: any
            )

            local transactionId = newTransactionId()
            self._invoker:FireClient(client, transactionId, ...)
            self._waitingInvocations[transactionId] = callback
        end

        --[=[
            Invokes the remote function on all clients asynchronously
            taking a callback to handle the return values

            @param callback
            @param ...? -- the parameters to pass to the remote function
            @server
        ]=]
        function Socket:InvokeAllClientsNonblocking(callback: (...any) -> (), ...: any)
            for _, client in game.Players:GetPlayers() do
                self:InvokeClientNonblocking(client, function(...)
                    callback(client, ...)
                end, ...)
            end
        end

        --[=[
            Invokes the remote function on the given client and blocks on it

            @param client -- the player on whom to invoke the remote function
            @param ...? -- the parameters to pass to the remote function
            @server
            @yields
        ]=]
        function Socket:InvokeClient(client: Player, ...: any)
            local co = coroutine.running()
            self:InvokeClientNonblocking(client, function(...)
                coroutine.resume(co, ...)
            end, ...)

            return coroutine.yield()
        end

        function Socket:FireServer()
            error("Cannot call FireServer from server")
        end

        function Socket:InvokeServerNonblocking()
            error("Cannot call InvokeServerNonblocking from server")
        end

        function Socket:InvokeServer()
            error("Cannot call InvokeServer from server")
        end
    end

    --[=[
        Sets the callback handler for this side of the socket's remote function
        @param callback (Player, ...any) -> (...any)
        @server
    ]=]
    --[=[
        Sets the callback handler for this side of the socket's remote function
        @param callback
        @client
    ]=]
    function Socket:SetCallback(callback: (...any) -> (...any))
        self._callback = callback
    end

    --[=[
        Connects a listener to the socket
        @param listener (Player, ...any) -> ()
        @return Connection
        @server
    ]=]
    --[=[
        Connects a listener to the socket
        @param listener (...any) -> ()
        @return Connection
        @client
    ]=]
    function Socket:Connect(listener: (...any) -> ()): Connection
        return self._signal:Connect(listener)
    end

    --[=[
        Blocks on the socket
        @return (Player, ...any) -- the return values of the listener
        @server
        @yields
    ]=]
    --[=[
        Blocks on the socket
        @return ...any -- the return values of the listener
        @client
        @yields
    ]=]
    function Socket:Wait(): ...any
        return self._signal:Wait()
    end
end

return Socket