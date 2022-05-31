local RunService = game:GetService("RunService")

local Socket = require(script.Socket)

local isClient = RunService:IsClient()

local function asyncWaitForChild(parent, name, callback)
    local child = parent:FindFirstChild(name)
    if child then
        callback(child)
    else
        local con
        con = parent.ChildAdded:Connect(function(child)
            if child.Name == name then
                con:Disconnect()
                callback(child)
            end
        end)
    end
end

local Sockets
local mt = {}
type Ansible = { [string]: Socket }
--[=[
    @class Ansible
    The root class is a [Socket](Socket) factory.

    Indexing it by a string lazily provides a named socket with that name like so:
    ```lua
    socket["DoRemote"]:Connect(listener) -- Connects a listener
    socket["DoRemote"]:FireServer() -- Fires the server side of the socket
    ```
]=]
local Ansible: Ansible = setmetatable({}, mt)
if isClient then
    Sockets = script:WaitForChild("_Sockets")

    local function bindToSocket(socket, socketFolder)
        asyncWaitForChild(socketFolder, "Event",
                function(e) socket:_bindEvent(e) end)
        asyncWaitForChild(socketFolder, "Invoker",
            function(i) socket:_bindInvoker(i) end)
    end

    function mt.__index(_, name: string)
        assert(type(name) == "string")
        local socket = Socket.new()
        local existingSocket = Sockets:FindFirstChild(name)
        if existingSocket then
            bindToSocket(socket, existingSocket)
        else
            asyncWaitForChild(Sockets, name,
                    function(s) bindToSocket(socket, s) end)
        end
        Ansible[name] = socket
        return socket
    end
else
    Sockets = Instance.new("Folder")
    Sockets.Name = "_Sockets"
    Sockets.Parent = script

    local function createSocket(name)
        local folder = Instance.new("Folder")
        folder.Name = name

        local event = Instance.new("RemoteEvent")
        event.Name = "Event"
        event.Parent = folder

        local invoker = Instance.new("RemoteEvent")
        invoker.Name = "Invoker"
        invoker.Parent = folder

        folder.Parent = Sockets

        return folder
    end

    function mt.__index(_, name)
        local existingSocket = Sockets:FindFirstChild(name)
        if not existingSocket then existingSocket = createSocket(name) end
        local socket = Socket.new(existingSocket.Event, existingSocket.Invoker)
        Ansible[name] = socket
        return socket
    end
end

return Ansible