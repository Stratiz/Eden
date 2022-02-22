--- Provides getting remote events
-- @function GetRemoteEvent

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StorageName = "RemoteEvents"

if not RunService:IsRunning() then
	return function(name)
		local event = Instance.new("RemoteEvent")
		event.Name = "Mock" .. name

		return event
	end
elseif RunService:IsServer() then
	return function(name)
		assert(type(name) == "string")

		local storage = ReplicatedStorage:FindFirstChild(StorageName)
		if not storage then
			storage = Instance.new("Folder")
			storage.Name = StorageName
			storage.Parent = ReplicatedStorage
		end

		local event = storage:FindFirstChild(name)
		if event then
			return event
		end

		event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = storage

		return event
	end
else -- RunService:IsClient()
	return function(name)
		assert(type(name) == "string")

		return ReplicatedStorage:WaitForChild(StorageName):WaitForChild(name)
	end
end