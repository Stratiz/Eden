--[[
	QuickDataStore.lua
	Stratiz
	Created/Documented on 08/20/2022 @ 23:21:09
	
	Description:
		Method of using datastore without the hassle, clicks into AsyncServiceHelper
	
	Documentation:
		.new(storeName : string) : QuickDataStoreObject
		-> Creates a new QuickDataStoreObject
			:Get(key : string) : table
			:GetAll() : table
			:Set(key : string, data : any) : boolean
			:Update(key : string, updater : (oldValue : any) -> (any)) : boolean
			:Remove(key : string) : boolean
--]]

--= Dependencies =--
local AsyncServiceHelper = shared('AsyncServiceHelper') ---@module AsyncServiceHelper

local DataStoreService = game:GetService("DataStoreService")
local QuickDataStore = {}

QuickDataStore.__index = QuickDataStore

function QuickDataStore.new(storeName : string, scope : string?) : {}
	local self = setmetatable({}, QuickDataStore)
	local options = Instance.new("DataStoreOptions")
	options.AllScopes = false -- what even is this

	self._Options = options
	self._DataStoreName = storeName
	
	self.DataStore = DataStoreService:GetDataStore(storeName, scope) -- If we use global random keys will show up in list keys

	return self
end


function QuickDataStore:Get(key : string) : {}

	local GotData, Data = AsyncServiceHelper:RetryUntilSuccess(function()
		AsyncServiceHelper:WaitForNextAvailableCall("DataStoreService", {
			DataStore = self.DataStore,
			RequestType = Enum.DataStoreRequestType.GetAsync,
			Key = key
		})
		return self.DataStore:GetAsync(key)
	end,3)

	if not GotData then
		warn("Failed to get '"..key.."' from datastore "..self._DataStoreName.." | ".. Data)
	end

	return GotData, Data
end

function QuickDataStore:GetAll()
	local Success, Pages = AsyncServiceHelper:RetryUntilSuccess(function()
		AsyncServiceHelper:WaitForNextAvailableCall("DataStoreService", {
			DataStore = self.DataStore,
			RequestType = Enum.DataStoreRequestType.GetSortedAsync, -- what rate limit is listkeys under
		})
		return self.DataStore:ListKeysAsync(nil, 10)
	end,3)

	if Success then
		local ReturnTable = {}
		repeat
			local CurrentPageEntries = Pages:GetCurrentPage()
			local FinishedKeys = 0
			for _,KeyInstance in ipairs(CurrentPageEntries) do
				task.spawn(function()
					local GotData, Data = self:Get(KeyInstance.KeyName)
					if GotData then
						ReturnTable[KeyInstance.KeyName] = Data
					end
					FinishedKeys += 1
				end)
			end
			repeat task.wait() until FinishedKeys == #CurrentPageEntries
			if Pages.IsFinished == false then
				local Advanced,Data = AsyncServiceHelper:RetryUntilSuccess(function()
					AsyncServiceHelper:WaitForNextAvailableCall("DataStoreService", {
						DataStore = self.DataStore,
						RequestType = Enum.DataStoreRequestType.GetSortedAsync -- This has to be incorrect...
					})
					Pages:AdvanceToNextPageAsync()
				end,2)
				if Advanced == false then
					warn("Failed to go to next page | "..Data)
					break
				end
			end
		until Pages.IsFinished == true
		return true, ReturnTable
	else
		warn("Failed to page datastore "..self._DataStoreName.." | "..Pages)
		return false, {}
	end
end

function QuickDataStore:Set(key : string, newValue : any) : boolean

	local Success, Data = AsyncServiceHelper:RetryUntilSuccess(function()
		AsyncServiceHelper:WaitForNextAvailableCall("DataStoreService", {
			DataStore = self.DataStore,
			RequestType = Enum.DataStoreRequestType.SetIncrementAsync,
			Key = key,
		})
		return self.DataStore:SetAsync(key, newValue)
	end,3)

	if not Success then
		warn("Failed to set '"..key.."' in datastore "..self._DataStoreName.." | ".. Data)
	end

	return Success
end

function QuickDataStore:Update(key : string, updater : (oldValue : any) -> (any)) : boolean

	local Success, Data = AsyncServiceHelper:RetryUntilSuccess(function()
		AsyncServiceHelper:WaitForNextAvailableCall("DataStoreService", {
			DataStore = self.DataStore,
			RequestType = Enum.DataStoreRequestType.UpdateAsync,
			Key = key,
		})
		return self.DataStore:UpdateAsync(key, updater)
	end,3)

	if not Success then
		warn("Failed to update '"..key.."' in datastore "..self._DataStoreName.." | ".. Data)
	end

	return Success
end

function QuickDataStore:Remove(key : string) : boolean
	
	local Success, Data = AsyncServiceHelper:RetryUntilSuccess(function()
		AsyncServiceHelper:WaitForNextAvailableCall("DataStoreService", {
			DataStore = self.DataStore,
			RequestType = Enum.DataStoreRequestType.SetIncrementAsync,
			Key = key
		})
		return self.DataStore:RemoveAsync(key)
	end,3)
	if not Success then
		warn("Failed to remove '"..key.."' from datastore "..self._DataStoreName.." | ".. Data)
		return false
	end
	return true
end

return QuickDataStore