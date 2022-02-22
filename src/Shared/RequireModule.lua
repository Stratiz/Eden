-- @Stratiz 2021 :)

--- local ReplicatedStorage = game:GetService("ReplicatedStorage")
--- local require = require(ReplicatedStorage.SharedModules:WaitForChild("RequireModule"))
---
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
-- Aggregate modules
local Modules = {}

local ModulePaths = {
	RunService:IsClient() and Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ClientModules") or game:GetService("ServerScriptService"):WaitForChild("ServerModules"),
	ReplicatedStorage:WaitForChild("SharedModules"),
}

local ModuleCount = 0
local function AddModule(Module : Instance)
	if Module:IsA("ModuleScript") then
		if not Modules[Module.Name] then
			Modules[Module.Name] = {
				Instance = Module,
				Name = Module.Name,
				State = "INACTIVE",
				DuplicateCount = 0,
				RequiredBy = nil,
			}
			ModuleCount += 1
		else
			Modules[Module.Name].DuplicateCount += 1
			warn(Modules[Module.Name].DuplicateCount + 1,"modules with the same name '",Module.Name,"' detected. Please resolve this to prevent unexpected behavior.")
		end
	end
end

for _,ModuleFolder in ipairs(ModulePaths) do
	for _,Module in pairs(ModuleFolder:GetDescendants()) do	
		AddModule(Module)
	end
	ModuleFolder.DescendantAdded:Connect(function(Module)
		AddModule(Module)
	end)
end

----
local TIMEOUT = 2
local NewRequire = function(TargetModuleName)
	-- Default require functionality
	if typeof(TargetModuleName) == "Instance" then
		return require(TargetModuleName)
	end

	local CurrentTimeout = 0
	local TargetModuleData
	local function FindModule()
		for ModuleName,ModuleData in pairs(Modules) do
			if ModuleData.Instance:IsA("ModuleScript") and ModuleName == TargetModuleName then
				TargetModuleData = ModuleData
			end
		end
	end
	local CurrentModuleCount = 0
	while not TargetModuleData and CurrentTimeout < TIMEOUT do
		if CurrentModuleCount ~= ModuleCount then
			CurrentModuleCount = ModuleCount
			FindModule()
		end
		local Delta = task.wait()
		CurrentTimeout += Delta
	end
	if not TargetModuleData then
		error("Module "..TargetModuleName.." not found",3)
	else
		if TargetModuleData.State == "INACTIVE" then
			TargetModuleData.State = "LOADING"
		end
		local ToReturn
		task.spawn(function()
			local TimeStart = tick()
			while not ToReturn do
				task.wait()
				if tick() - TimeStart > 3 then
					warn("Module",TargetModuleName,"is taking a long time to load.")
					break
				end
			end
		end)
		local RequireScript = getfenv(2)["script"]
		if RequireScript and RequireScript:IsA("ModuleScript") then
			local InvokerModuleData = Modules[RequireScript.Name]
			if InvokerModuleData and InvokerModuleData.Instance == RequireScript then
				if TargetModuleData.State == "LOADING" then

					-- Check for cyclicals
					if InvokerModuleData.RequiredByModule then
						local CyclicalPathString = InvokerModuleData.Name
						local CurrentRequesterData = InvokerModuleData
						while InvokerModuleData.RequiredByModule and InvokerModuleData.RequiredByModule.Instance ~= TargetModuleData.Instance do
							if CurrentRequesterData.RequiredByModule then
								CurrentRequesterData = CurrentRequesterData.RequiredByModule
								CyclicalPathString = CurrentRequesterData.Name .." -> " .. CyclicalPathString
							else
								break
							end
						end
						if CurrentRequesterData.Instance == TargetModuleData.Instance then
							warn("Cyclical require detected: (",CyclicalPathString.." -> "..TargetModuleData.Name, ") \n\nPlease resolve this to prevent unexpected behavior.")
						end
					end
				end
				TargetModuleData.RequiredByModule = Modules[RequireScript.Name]
			end
		end
		
		ToReturn = require(TargetModuleData.Instance)
		if TargetModuleData.State == "LOADING" then
			TargetModuleData.State = "ACTIVE"
		end
		return ToReturn
	end
end

_G.require = NewRequire
return NewRequire