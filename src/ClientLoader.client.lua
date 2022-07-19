-- @Stratiz 2022
-- This is where your scripts on the client are initialized. You could create a loading screen in here as well.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local require = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("RequireModule"))

require:InitModules {
    -- (Optional) Module Paths
}