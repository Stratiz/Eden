-- @Stratiz 2022
-- This is where your scripts on the server are initialized. You dont need to modify this file.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local require = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Eden"))

require:InitModules {
    -- (Optional) Module Paths
}