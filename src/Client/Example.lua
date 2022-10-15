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
    -- All of the following paramers are optional.
    _Priority = 0, -- The default priority is 0. The higher the priority, the earlier the module will be loaded. Negative priorities are allowed and will always be loaded last.
    _Initialize = true, -- Determines if this modules :Init function will be called. If false, the module will not be initialized. Good for disabling modules.

    -- These two are good for games that require modules to only run in certain places under a universe
    _PlaceBlacklist = {
        123, -- The place ID of the place to blacklist.
    },
    _PlaceWhitelist = {
        456, -- The place ID of the place to whitelist. If this table is empty, all places will be allowed.
    }
}

--= Roblox Services =--
local Players = game:GetService("Players")

--= Dependencies =--

-- If the module has a unique name you dont need to use the path and you can require by name "Example".
--"Shared/Example" is the path to the module. This is the same as the path in the file explorer.
local OtherExampleModule = shared("Shared/Example")


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