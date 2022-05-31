# Ansible
Ansible is a small networking library for Roblox games.
It simplifies networking by allowing the user to use sockets
in a single shared namespace, in lieu of scattering RemoteEvents
and RemoteFunctions throughout the DataModel. These sockets
combine the features of a RemoteEvent and a RemoteFunction
and are a drop-in replacement for RemoteEvents and a
near drop-in replacement for RemoteFunctions. They
deviate from RemoteFunctions only in that they return
a success boolean before the function's return parameters,
and use a method to set the callback instead of setting it
directly.

## Example Usage
In a LocalScript:
```lua
print(Ansible.Sum:InvokeServer(2, 2)) -- prints `true 4`
Ansible.Print:FireServer("Hello, Ansible!")
```
In a server-side Script:
```lua
Ansible.Sum:SetCallback(function(player, a, b) return a + b end)
Ansible.Print:Connect(function(player, text) player.Name..' says "'..text..'"' end)
-- prints `[playername] says "Hello, Ansible!"`
```
See the [docs](http://dimitriye98.github.io/ansible/) for more information.
