--[[
    Example.lua
    Stratiz
    Created on 10/15/2022 @ 01:58
    
    Description:
        An example file to show how to use the Eden framework. You're welcome to follow this module format or make your own!
    
    Documentation:
       :ExampleMethod() : number
            This is an example method that prints the defined constant and returns a number
--]]

--= Root =--
local Example = {
    -- All of the following paramers are optional so in this case we'll only use one.
    _Initialize = false -- We wont run the init function
}

--= Roblox Services =--
local Players = game:GetService("Players")

--= Dependencies =--

--= Object References =--
local Player = Players.LocalPlayer

--= Constants =--
local EXAMPLE_CONSTANT = "Hello, world!"

--= Variables =--
local TimeInitialized = 0

--= Internal Functions =--
local function GetCurrentTime()
    return os.time()
end

--= API Functions =--
Example.Number = 12

function Example:ExampleMethod() : number
    print(EXAMPLE_CONSTANT)
    return GetCurrentTime()
end

--= Initializers =--
function Example:Init() -- This function wont run because we set _Initialize to false
    print("I RAN :)")
end

--= Return Module =--
return Example