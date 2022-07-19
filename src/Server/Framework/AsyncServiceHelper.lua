--[[
    AsyncServiceHelper.lua
    Stratiz
    Created on 05/24/2022 @ 17:58:22
    
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
        -> Will wait for the service to be available for the next Async call. (Signal style wait)

        Param options: 
            --All options are optional but reccomended
            MemoryStoreService = {}
            HttpService = {}
            DataStoreService = {
                DataStore = DataStore object
                Key = Data store key
                IsVerisonApi = boolean
                RequestType = Datastorerequesttype enum
            }
--]]

--= Root =--
local AsyncServiceHelper = {
    Priority = 0
}

--= Roblox Services =--
local MemoryStoreService = game:GetService('MemoryStoreService')
local DataStoreService = game:GetService('DataStoreService')
local HttpService = game:GetService('HttpService')
local RunService = game:GetService('RunService')
local MessagingService = game:GetService('MessagingService')
local Players = game:GetService('Players')

--= Dependencies =--
local Signal = _G.require('Signal')

--= Constants =--

local DATASTORE_BUFFER_SIZE = 5
local SAME_KEY_RATELIMIT = 6.1

--= Variables =--
local CurrentPlayerCount = 0
local DataStoreKeyCache = {}
local LastApiCallCache = {}

local CallbackQueue = {}

--= Internal Functions =--
local RateLimits = {
    MemoryStoreService = function(lastCallTickDelta, params)
        local RateLimit = 1
        if CurrentPlayerCount > 0 then
            RateLimit = 60/(CurrentPlayerCount * 100)
        end

        return lastCallTickDelta > RateLimit
    end,
    DataStoreService = function(lastCallTickDelta, params)
        if DataStoreService:GetRequestBudgetForRequestType(params.RequestType or Enum.DataStoreRequestType.GetAsync) >= DATASTORE_BUFFER_SIZE then
            local DataStore = params.DataStore or "_DEFAULT"
            local Key = params.Key or "_KEY"
            if not DataStoreKeyCache[DataStore] then
                DataStoreKeyCache[DataStore] = {}
            end
            --// Cleaning
            for FocusedKey, UsedAtTick in pairs(DataStoreKeyCache[DataStore]) do
                if tick() - UsedAtTick > SAME_KEY_RATELIMIT then
                    DataStoreKeyCache[DataStore][FocusedKey] = nil
                end
            end
            --//
            local CurrentTick = tick()
            local TimeLeftForKey = SAME_KEY_RATELIMIT - (CurrentTick - (DataStoreKeyCache[DataStore][Key] or (CurrentTick - (SAME_KEY_RATELIMIT+1))))
            local RateLimit = params.VersionApi and (60/(5 + CurrentPlayerCount * 2)) or (60/(60 + CurrentPlayerCount * 10))

            local CanCall = TimeLeftForKey <= 0 and lastCallTickDelta > RateLimit
            if CanCall == true then
                DataStoreKeyCache[DataStore][Key] = CurrentTick
            end

            return CanCall
        else
            return false
        end
    end,
    HttpService = function(lastCallTickDelta, params)
        return lastCallTickDelta > (60/500)
    end,
    MessagingService = function(lastCallTickDelta)
        return lastCallTickDelta > 150 + 60 * CurrentPlayerCount
    end
}

--= Job API =--

function AsyncServiceHelper:RetryUntilSuccess(toRetry : () -> (any), retryCount : number?)
    local StartTick = tick()
    local CurrentRetry = 0
    while true do
        local Success, Data = pcall(function()
            return toRetry()
        end)
        if Success then
            if retryCount then
                return true, Data, (tick()-StartTick)
            else
                return Data, (tick()-StartTick)
            end
        elseif retryCount and CurrentRetry >= retryCount then
            return false, Data, (tick()-StartTick)
        else
            if retryCount%10 == 0 then
                warn("Async function failed (Current Retry:"..retryCount.."), will continue to retry...\n",debug.traceback())
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
        local ReturnSignal = Signal.new()
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
            local LastCallTickDelta = tick() - (LastApiCallCache[Data.ServiceName] or 0)
            local CanRequest = RateLimits[Data.ServiceName](LastCallTickDelta, Data.Params)
            if CanRequest then
                if Data.Type == "Callback" then
                    task.spawn(Data.ReturnEntity)
                elseif Data.Type == "Signal" then
                    Data.ReturnEntity:Fire() 
                end
                LastApiCallCache[Data.ServiceName] = tick()
                table.remove(CallbackQueue, Index)
                break
            end
        end
    end)

    game:BindToClose(function()
        repeat
            task.wait()
        until #CallbackQueue <= 0
    end)
end

--= Return Job =--
return AsyncServiceHelper