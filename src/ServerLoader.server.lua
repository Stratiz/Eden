-- @Stratiz 2022
-- This is where your scripts on the server are initialized.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local require = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("RequireModule"))

require:InitModules {
    -- (Optional) Module Paths
}