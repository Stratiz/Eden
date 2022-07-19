-- @Stratiz 2021 :)

local RequireModule = {}
--- local ReplicatedStorage = game:GetService("ReplicatedStorage")
--- local require = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("RequireModule"))

-- Constants
local FIND_TIMEOUT = 3
local LONG_LOAD_TIMEOUT = 4

---
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
-- Aggregate modules
local Modules = {}
local ModuleCount = 0
local InitalizedModules = false

local ModulePaths = {
	-- Core paths
	RunService:IsClient() and {
		Alias = "Client",
		Instance = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ClientModules"),
	} or {
		Alias = "Server",
		Instance =  game:GetService("ServerScriptService"):WaitForChild("ServerModules"),
	},
	{
		Alias = "Shared",
		Instance = ReplicatedStorage:WaitForChild("SharedModules"),
	},
	-- Custom paths
	
}


local function GetModulePathFromAlias(pathData : {}, module : ModuleScript)
	local CurrentParent = module
	local OrderedInstanceTable = {}
	repeat
		table.insert(OrderedInstanceTable, 1, CurrentParent.Name)
		CurrentParent = CurrentParent.Parent
	until CurrentParent == pathData.Instance or CurrentParent == game
	return pathData.Alias.."/"..table.concat(OrderedInstanceTable, "/")
end

local function AddModule(pathData : {}, module : Instance)
	if module:IsA("ModuleScript") then
		local ModuleName = module.Name

		local NewModuleData = {
			Instance = module,
			Name = ModuleName,
			Path = GetModulePathFromAlias(pathData, module),
			State = "INACTIVE",
			RequiredBy = {},
		}
		ModuleCount += 1

		table.insert(Modules, NewModuleData)
	end
end

for _,PathData in ipairs(ModulePaths) do
	for _,Module in pairs(PathData.Instance:GetDescendants()) do
		AddModule(PathData,Module)
	end
	PathData.Instance.DescendantAdded:Connect(function(Module)
		if InitalizedModules == true then
			warn("Module",Module.Name,"replicated late to",PathData.Alias,"module folder. This may cause unexpected behavior.")
		end
		AddModule(PathData,Module)
	end)
end


local function FindCycle(targetModuleObject, _cycleTable)
	local CycleTable = _cycleTable or {}
	table.insert(CycleTable, targetModuleObject)
	for _, Requirer in targetModuleObject.RequiredBy do
		local FindResult = table.find(CycleTable, Requirer)
		if FindResult then
			local CycleString = ""
			for Index, ModuleData in ipairs(CycleTable) do
				if Index >= FindResult then 
					CycleString ..= ModuleData.Name .. " -> "
				end
			end
			CycleString ..= CycleTable[FindResult].Name
			return CycleString
		else
			return FindCycle(Requirer, CycleTable)
		end
	end
	return nil
end

local function FindModule(targetString : string)
	local Found = {}
	for _,ModuleData in ipairs(Modules) do
		if ModuleData.Name == targetString or ModuleData.Path == targetString then
			table.insert(Found, ModuleData)
		end
	end
	if #Found > 1 then
		warn("Multiple modules found with the name '"..targetString.."'. To clarify, please use the path instead. (ex: Shared/Framework/MODULE)")
	end
	return Found[1]
end

local CurrentlyLoadingTree = {}
local NewRequire = function(query : string | ModuleScript)
	-- Default require functionality
	if typeof(query) == "Instance" then
		return require(query)
	end

	local CurrentTimeout = 0
	local TargetModuleData = FindModule(query)
	
	local CurrentModuleCount = 0
	while not TargetModuleData and CurrentTimeout < FIND_TIMEOUT do
		if CurrentModuleCount ~= ModuleCount then
			CurrentModuleCount = ModuleCount
			FindModule(query)
		end
		local Delta = task.wait()
		CurrentTimeout += Delta
	end

	if not TargetModuleData then
		error("Module "..query.." not found",3)
	else
		if TargetModuleData.State == "INACTIVE" then
			TargetModuleData.State = "LOADING"
			if CurrentlyLoadingTree[1] then
				table.insert(TargetModuleData.RequiredBy, CurrentlyLoadingTree[#CurrentlyLoadingTree])
			end
			table.insert(CurrentlyLoadingTree, TargetModuleData)
		end
		local ToReturn
		task.spawn(function()
			local TimeStart = tick()
			while TargetModuleData.State == "LOADING" do
				task.wait()
				if tick() - TimeStart > LONG_LOAD_TIMEOUT then
					warn("Module",query,"is taking a long time to load.")
					break
				end
			end
		end)
		
		-- Check for cyclic dependencies
		if TargetModuleData.State == "LOADING" then
			local CycleString = FindCycle(TargetModuleData)
			if CycleString then
				warn("Cyclical require detected: ("..CycleString..") \n\nPlease resolve this to prevent unexpected behavior.")
			end
		end

		ToReturn = require(TargetModuleData.Instance)
		if TargetModuleData.State == "LOADING" then
			TargetModuleData.State = "ACTIVE"
			table.remove(CurrentlyLoadingTree, #CurrentlyLoadingTree)
		end
		return ToReturn
	end
end

function RequireModule:InitModules(explictRequires : {}?)
	if InitalizedModules == false then
		InitalizedModules = true
		explictRequires = explictRequires or {}
		-- Get Init data
		local LowestPriority = math.huge
		for _,ModuleData in ipairs(Modules) do
			local Success, RequiredData = pcall(function()
				return NewRequire(ModuleData.Path)
			end)
			
			if not Success then
				warn("Module",ModuleData.Path,"failed to auto-load:",RequiredData)
			end
			if type(RequiredData) == "table" then
				local TargetPriority = rawget(RequiredData,"_Priority") or math.huge
				ModuleData._AutoInitData = {
					Priority = TargetPriority,
					Init = rawget(RequiredData,"Init"),
					RequiredData = RequiredData
				}
				if TargetPriority < LowestPriority then
					LowestPriority = TargetPriority
				end
			else
				ModuleData._AutoInitData = {
					Priority = math.huge,
				}
			end
		end
		LowestPriority = LowestPriority > 0 and 0 or LowestPriority
		for _,ModuleData in ipairs(Modules) do
			local TargetIndex = table.find(explictRequires, ModuleData.Path)
			if TargetIndex then
				ModuleData._AutoInitData.Priority = LowestPriority - ((#explictRequires + 1) - TargetIndex)
			end
		end

		-- Sort Modules by priority
		table.sort(Modules, function(a, b)
			return a._AutoInitData.Priority < b._AutoInitData.Priority
		end)
		
		print(explictRequires,Modules)
		-- Auto initalize modules
		for _,ModuleData in ipairs(Modules) do
			if ModuleData._AutoInitData.Init then
				ModuleData._AutoInitData.Init(ModuleData._AutoInitData.RequiredData)
				ModuleData._AutoInitData = nil
			end
		end
	else
		error("You can only initalize modules once!")
	end
end

_G.require = NewRequire
shared.require = NewRequire

local CallMetaTable = {
	__call = function(_, ...)
		return NewRequire(...)
	end
}
setmetatable(shared,CallMetaTable)
setmetatable(RequireModule,CallMetaTable)

return RequireModule