
--[[
	QuickMemoryStore.lua
	Stratiz
	Created/Documented on 08/20/2022 @ 23:21:09
	
	Description:
		Method of using datastore without the hassle, clicks into AsyncServiceHelper
	
	Documentation:
		.new(storeName : string) : QuickMemoryStoreObject
		-> Creates a new QuickMemoryStoreObject
			:Get(key : string) : table
			:GetAll() : table
			:Set(key : string, data : any) : boolean
			:Update(key : string, updater : (oldValue : any) -> (any)) : boolean
			:Remove(key : string) : boolean
--]]

--= Dependencies =--
local AsyncServiceHelper = shared('AsyncServiceHelper') ---@module AsyncServiceHelper

local MemoryStoreService = game:GetService("MemoryStoreService")
local QuickMemoryStore = {}

QuickMemoryStore.__index = QuickMemoryStore

function QuickMemoryStore.new(storeName : string) : {}
	local self = setmetatable({}, QuickMemoryStore)

	self._MemoryStoreName = storeName
	
	self.MemoryStore = MemoryStoreService:GetSortedMap(storeName)

	return self
end


function QuickMemoryStore:Get(key : string) : {}

	local GotData, Data = AsyncServiceHelper:RetryUntilSuccess(function()
		AsyncServiceHelper:WaitForNextAvailableCall("MemoryStoreService", {})
		return self.MemoryStore:GetAsync(key)
	end,3)

	if not GotData then
		warn("Failed to get '"..key.."' from MemoryStore "..self._MemoryStoreName.." | ".. Data)
	end

	return GotData, Data
end

function QuickMemoryStore:GetAll() : {[string] : any}
	local exclusiveLowerBound = nil
	local ToReturn = {}
	while true do
		AsyncServiceHelper:WaitForNextAvailableCall("MemoryStoreService", {})
		local getRangeSuccess, items = pcall(function()
			return self.MemoryStore:GetRangeAsync(Enum.SortDirection.Ascending, 100, exclusiveLowerBound)
		end)
		if getRangeSuccess then
			for _,kvPair in pairs(items) do
				ToReturn[kvPair.key] = kvPair.value
			end
			if #items < 100 then
				break
			else
				exclusiveLowerBound = items[#items].key
			end
		end
	end
	return ToReturn
end

function QuickMemoryStore:Set(key : string, newValue : any, expires : number) : boolean

	local Success, Data = AsyncServiceHelper:RetryUntilSuccess(function()
		AsyncServiceHelper:WaitForNextAvailableCall("MemoryStoreService", {})
		return self.MemoryStore:SetAsync(key, newValue, expires)
	end,3)

	if not Success then
		warn("Failed to set '"..key.."' in MemoryStore "..self._MemoryStoreName.." | ".. Data)
	end

	return Success
end

function QuickMemoryStore:Update(key : string, updater : (oldValue : any) -> (any)) : boolean

	local Success, Data = AsyncServiceHelper:RetryUntilSuccess(function()
		AsyncServiceHelper:WaitForNextAvailableCall("MemoryStoreService", {})
		return self.MemoryStore:UpdateAsync(key, updater)
	end,3)

	if not Success then
		warn("Failed to update '"..key.."' in MemoryStore "..self._MemoryStoreName.." | ".. Data)
	end

	return Success
end

function QuickMemoryStore:Remove(key : string) : boolean
	
	local Success, Data = AsyncServiceHelper:RetryUntilSuccess(function()
		AsyncServiceHelper:WaitForNextAvailableCall("MemoryStoreService", {})
		return self.MemoryStore:RemoveAsync(key)
	end,3)
	if not Success then
		warn("Failed to remove '"..key.."' from MemoryStore "..self._MemoryStoreName.." | ".. Data)
		return false
	end
	return true
end

return QuickMemoryStore