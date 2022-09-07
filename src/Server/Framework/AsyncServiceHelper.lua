--[[
    AsyncServiceHelper.lua V2.1
    Stratiz
    Created on 05/24/2022 @ 17:58:22
	Updated on 08/29/2022 @ 20:00:00
    
    Description:
        Provides functions to stay within rate limits
    
    Documentation:
        :RetryUntilSuccess(toRetry : () -> (any), retryCount : number?)
        -> Will retry provided function until it reaches success, or until it hits the optional retryCount parameter.
            If no retryCount is provided, the function will run indefinitely until it is successful.

            If retryCount is specified, the function will return arguments as if it was a pcall:
                
                local success, data, deltaTime

            otherwise the function will return just the eventual successfull data and a time delta.

                local data, deltaTime

        :InvokeOnNextAvailableCall(serviceName : string, params : {}, callback : () -> ())
        -> Will fire the callback function when the service is available for the next Async call.
        
        :WaitForNextAvailableCall(serviceName : string, params : {})
        -> Will wait for the service to be available for the next Async call. (signal style wait)

        Param options:
            --All options are optional but reccomended
            MemoryStoreService = {}
            HttpService = {}
            DataStoreService = {
                DataStore = DataStore object
                Key = Data store key
                RequestType = Datastorerequesttype enum
            }
--]]

--= Root =--
local AsyncServiceHelper = {
	Priority = 2
}

--= Roblox Services =--
local DataStoreService = game:GetService('DataStoreService')
local HttpService = game:GetService('HttpService')
local RunService = game:GetService('RunService')
local MessagingService = game:GetService('MessagingService')
local Players = game:GetService('Players')

--= Dependencies =--
local signal = shared("Signal")

--= Constants =--

local DATASTORE_BUFFER_SIZE = 5
local SAME_KEY_RATELIMIT = 6.2

--= Variables =--
local CurrentPlayerCount = 0
local DataStoreKeyCache = {}
local LastApiCallCache = {}
local CallbackQueue = {}

--= Internal Functions =--
local RateLimits = {
	MemoryStoreService = function(params)
		local lastCallTickDelta = tick() - (LastApiCallCache["MemoryStoreService"] or 0)
		local RateLimit = 1
		if CurrentPlayerCount > 0 then
			RateLimit = 60/(CurrentPlayerCount * 100)
		end

		local CanCall = lastCallTickDelta > RateLimit
		if CanCall then
			LastApiCallCache["MemoryStoreService"] = tick()
		end
		return CanCall
	end,
	DataStoreService = function(params)
		local DataStore = params.DataStore or "_DEFAULT"
		local Key = params.Key
		local RequestType = params.RequestType or Enum.DataStoreRequestType.GetAsync
		local lastCallTickDelta = tick() - (LastApiCallCache["DataStoreService"] and LastApiCallCache["DataStoreService"][DataStore] or 0)

		if DataStoreService:GetRequestBudgetForRequestType(RequestType) >= DATASTORE_BUFFER_SIZE then

			-- If doesnt exist then create tables
			if not DataStoreKeyCache[DataStore] then
				DataStoreKeyCache[DataStore] = {}
			end
			if not DataStoreKeyCache[DataStore][RequestType] then
				DataStoreKeyCache[DataStore][RequestType] = {}
			end
			if not LastApiCallCache["DataStoreService"] then
				LastApiCallCache["DataStoreService"] = {}
			end
			--// Cleaning
			for FocusedKey, UsedAtTick in pairs(DataStoreKeyCache[DataStore][RequestType]) do
				if tick() - UsedAtTick > SAME_KEY_RATELIMIT then
					DataStoreKeyCache[DataStore][RequestType][FocusedKey] = nil
				end
			end
			--//
			local KeyCacheTable = DataStoreKeyCache[DataStore][RequestType]

			local CurrentTick = tick()
			local TimeLeftForKey = Key and (SAME_KEY_RATELIMIT - (CurrentTick - (KeyCacheTable[Key] or (CurrentTick - (SAME_KEY_RATELIMIT+1))))) or 0 
			
			local CanCall = TimeLeftForKey <= 0
			if CanCall == true then
                if Key then
                    KeyCacheTable[Key] = CurrentTick
                end
				LastApiCallCache["DataStoreService"][DataStore] = CurrentTick
			end
			return CanCall
		else
			return false
		end
	end,
	HttpService = function(params)
		local lastCallTickDelta = tick() - (LastApiCallCache["HttpService"] or 0)
		local CanCall = lastCallTickDelta > (60/500)
		if CanCall then
			LastApiCallCache["HttpService"] = tick()
		end
		return CanCall
	end,
	MessagingService = function(params)
		local lastCallTickDelta = tick() - (LastApiCallCache["MessagingService"] or 0)
		local CanCall = lastCallTickDelta > 60/(150 + 60 * CurrentPlayerCount)
		if CanCall then
			LastApiCallCache["MessagingService"] = tick()
		end
		return CanCall
	end
}

--= Job API =--

function AsyncServiceHelper:RetryUntilSuccess(toRetry : () -> (any), retryCount : number?)
	local StartTick = tick()
	local CurrentRetry = 0
	while true do
		local Success, Data = pcall(toRetry)
		if Success then
			if retryCount then
				return true, Data, (tick()-StartTick)
			else
				return Data, (tick()-StartTick)
			end
		elseif retryCount and CurrentRetry >= retryCount then
			return false, Data, (tick()-StartTick)
		else
			if CurrentRetry%10 == 0 then
				warn("Async function failed (Current Retry: "..CurrentRetry.."), will continue to retry...",Data,debug.traceback())
			end
			task.wait(3)
			CurrentRetry += 1
		end
	end
end

function AsyncServiceHelper:InvokeOnNextAvailableCall(serviceName : string, params : {}, callback : () -> ())
	if RateLimits[serviceName] then
		table.insert(CallbackQueue, {
			ReturnEntity = callback,
			Type = "Callback",
			Params = params,
			ServiceName = serviceName
		})
	else
		error("Unsupported service name: "..serviceName)
	end
end

function AsyncServiceHelper:WaitForNextAvailableCall(serviceName : string, params : {})
	if RateLimits[serviceName] then
		local ReturnSignal = signal.new()
		table.insert(CallbackQueue, {
			ReturnEntity = ReturnSignal,
			Type = "Signal",
			Params = params,
			ServiceName = serviceName
		})
		return ReturnSignal:Wait()
	else
		error("Unsupported service name: "..serviceName)
	end
end

--= Job Initializers =--

function AsyncServiceHelper:Init()
	Players.PlayerAdded:Connect(function()
		CurrentPlayerCount += 1
	end)
	Players.PlayerRemoving:Connect(function()
		CurrentPlayerCount -= 1
	end)
	CurrentPlayerCount = #Players:GetPlayers()

	RunService.Heartbeat:Connect(function()
		for Index, Data in pairs(CallbackQueue) do
			local CanRequest = RateLimits[Data.ServiceName](Data.Params)
			if CanRequest then
				if Data.Type == "Callback" then
					task.spawn(Data.ReturnEntity)
				elseif Data.Type == "Signal" then
					Data.ReturnEntity:Fire()
				end
				table.remove(CallbackQueue, Index)
				break
			end
		end
	end)

	game:BindToClose(function()
		repeat
			task.wait(1)
		until #CallbackQueue <= 0
	end)
end

--= Return Job =--
return AsyncServiceHelper