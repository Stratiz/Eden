-- @Stratiz 2022
-- This is where your scripts on the server are initialized. You don't need to modify this file.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Eden = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Eden"))

Eden:InitModules {
    -- (Optional) ModuleScripts to :Init() first, in order
}
