-- @Stratiz 2022
-- This is where your scripts on the server are initialized.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local require = require(ReplicatedStorage.SharedModules:WaitForChild("RequireModule"))

local ModulesToInit = {}

for _,ModuleName in ipairs(ModulesToInit) do
    require(ModuleName):Init()
end