--[[
    Example.lua
    Stratiz
    Created on 10/15/2022 @ 01:58
    
    Description:
        An example file to show how to use the Eden framework. You're welcome to follow this module format or make your own!
    
    Documentation:
       :ExampleMethod() : nil
            This is an example method that prints the defined constant.
--]]

--= Root =--
local Example = {
    -- All of the following parameters are optional.
    Priority = 0, -- The default priority is 0. The higher the priority, the earlier the module will be loaded. Negative priorities are allowed and will always be loaded last.
    Initialize = true, -- Determines if this modules :Init function will be called. If false, the module will not be initialized. Good for disabling modules.
}

--= Roblox Services =--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--= Dependencies =--
-- Modules are required normally, so you keep autocomplete and type checking.
local OtherExampleModule = require(ReplicatedStorage.SharedModules.ExampleShared)


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
function Example:ExampleMethod()
    print(EXAMPLE_CONSTANT)
end

--= Initializers =--
function Example:Init() -- This function will be called when the module is initialized.
    -- Do stuff here.
    TimeInitialized = GetCurrentTime()
end

--= Return Module =--
return Example