
--[[
	RequireModule.lua
	Stratiz
	Created on 09/06/2022 @ 21:50
	Updated on 10/15/2022 @ 01:25
	
	Description:
		Module aggregator for Eden.
	
	Documentation:
		Instead of require(), Eden uses shared("moduleName") this should only be done inside of module scripts.
		Ideally, your project should only contain module scripts.

		To require modules in script instances, you'll need to directly require the module with the following code:

		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local require = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("RequireModule"))

		.InitalizedModulesEvent : Signal (See signal type export)
			Signal that fires when all modules have been initialized.
			
		:InitModules(explictRequires: {string}?)
			Fires by default in the ServerLoader and ClientLoader scripts.
			Initializes all modules in the context, with the option of explictly defining what modules load first. This is a legacy feature but is still supported.
--]]

--= Root =--
local RequireModule = { }

--= Roblox Services =--
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--= Types =--
type ModuleData = {
	Name: string,
	Instance: ModuleScript,
	Path: string,
	State : "INACTIVE" | "ACTIVE" | "LOADING",
	RequiredBy: { ModuleData }
}

type PathData = {
	Alias: string,
	Instance: Instance,
}

export type Signal = {
	Connect: ((any) -> nil) -> RBXScriptConnection,
	Fire: (any),
	Wait: () -> any,
}
--= Constants =--
local DEBUG = false
local FIND_TIMEOUT = 3
local LONG_LOAD_TIMEOUT = 4
local LONG_INIT_TIMEOUT = 10
local MAX_PRIORITY = 2^16
local SPECIAL_PARAMS = {
	"Initialize",
	"Priority",
	"PlaceBlacklist",
	"PlaceWhitelist",
}
local MODULE_PATHS = {
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

--= Variables =--
local CurrentlyLoadingTree = {}
local Modules : { ModuleData } = {}
local ModuleCount = 0
local InitializingModules = false
local InitalizedModules = false
local _print = print
local _warn = warn

--= Internal Functions =--
local function print(...)
	if DEBUG then
		_print("[EDEN]", ...)
	end
end

local function warn(...)
	_warn("[EDEN]", ...)
end

-- Creates a signal object
local function MakeSignal() : Signal
	local BindableEvent = Instance.new("BindableEvent")
	local Signal = {}
	function Signal:Connect(toExecute : (any)) : RBXScriptConnection
		return BindableEvent.Event:Connect(toExecute)
	end

	function Signal:Fire(...) : nil
		BindableEvent:Fire(...)
	end

	function Signal:Wait() : any
		return BindableEvent.Event:Wait()
	end

	return Signal
end

-- Gets the path string for a ModuleScript
local function GetModulePath(pathData : PathData, module : ModuleScript) : string
	local CurrentParent = module
	local OrderedInstanceTable = {}
	repeat
		table.insert(OrderedInstanceTable, 1, CurrentParent.Name)
		CurrentParent = CurrentParent.Parent
	until CurrentParent == pathData.Instance or CurrentParent == game
	return pathData.Alias.."/"..table.concat(OrderedInstanceTable, "/")
end

-- Adds a module to the Modules table
local function AddModule(pathData : PathData, module : Instance) : nil
	if module:IsA("ModuleScript") then
		local NewModuleData = {
			Instance = module,
			Name = module.Name,
			Path = GetModulePath(pathData, module),
			State = "INACTIVE",
			RequiredBy = {},
		}
		ModuleCount += 1

		table.insert(Modules, NewModuleData)
	end
end

-- Returns a string of the circular dependency tree if one exists.
local function FindCycle(requirerModuleData : ModuleData, targetModuleData : ModuleData, _cycleString)
	local CurrentCycleString = requirerModuleData.Path.." -> "..(_cycleString or targetModuleData.Path)
	for _, Requirer in requirerModuleData.RequiredBy do
		if targetModuleData == Requirer then
			return Requirer.Path.." -> "..CurrentCycleString
		else
			return FindCycle(Requirer, targetModuleData, CurrentCycleString)
		end
	end
	return nil
end

-- Gets the custom module parameters and returns them as a dictionary
local function GetParamsFromRequiredData(requiredData : any) : { [string] : any }
	local Params = {}
	if type(requiredData) == "table" then
		for _, ParamName in SPECIAL_PARAMS do
			Params[ParamName] = rawget(requiredData, "_"..ParamName)
		end
	end
	return Params
end

-- Returns the module data object for a module if the query is found
local function FindModule(query : string) : ModuleData?
	local Found = {}
	for _,ModuleData in ipairs(Modules) do
		if ModuleData.Name == query or ModuleData.Path == query then
			table.insert(Found, ModuleData)
		end
	end
	if #Found > 1 then
		warn("Multiple modules found with the name '"..query.."'. To clarify, please use the path instead. (ex: Shared/Framework/Module)")
	end
	return Found[1]
end

-- The main require function that overrides the default require function 
local function NewRequire(query : string | ModuleScript) : any
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

		-- Check for cyclic dependencies
		if TargetModuleData.State == "LOADING" then
			local CycleString = FindCycle(CurrentlyLoadingTree[#CurrentlyLoadingTree], TargetModuleData)
			if CycleString then
				warn("Cyclical require detected: ("..CycleString.."). Required module will return nil.")
				return nil -- Return nil instead of infinite hanging
			end
		end

		-- Check if module is already loaded
		if TargetModuleData.State == "INACTIVE" then
			TargetModuleData.State = "LOADING"
			if CurrentlyLoadingTree[1] then
				table.insert(TargetModuleData.RequiredBy, CurrentlyLoadingTree[#CurrentlyLoadingTree])
			end
			table.insert(CurrentlyLoadingTree, TargetModuleData)
		end

		-- Start loading timer
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
		
		-- Require module and return
		local ToReturn = require(TargetModuleData.Instance)
		if TargetModuleData.State == "LOADING" then
			TargetModuleData.State = "ACTIVE"
			table.remove(CurrentlyLoadingTree, #CurrentlyLoadingTree)
		end
		return ToReturn
	end
end

--= API Methods =--
RequireModule.InitalizedModulesEvent = MakeSignal()

-- Getter function for InitializedModules boolean
function RequireModule:AreModulesInitialized() : boolean
	return InitalizedModules
end

-- Initializes all modules in the current context
function RequireModule:InitModules(explictRequires : { string }?)
	if InitializingModules == false then
		InitializingModules = true
		explictRequires = explictRequires or {}
		
		-- Get Init data
		for _,ModuleData in ipairs(Modules) do

			--Default init data applicator
			local function DoDefault()
				ModuleData._AutoInitData = {
					Priority = 0,
				}
			end

			-- Check for static directory
			local Directories = ModuleData.Path:split("/")
			local StaticIndex
			for Index, DirectoryName in Directories do
				if string.lower(DirectoryName) == "static" then
					StaticIndex = Index
					break
				end
			end
			if StaticIndex then
				DoDefault()
				continue
			end

			-- Require module
			local Success, RequiredData = pcall(function()
				return NewRequire(ModuleData.Path)
			end)
			if not Success then
				warn("Module",ModuleData.Path,"failed to auto-load:",RequiredData)
			end

			local ModuleParams = GetParamsFromRequiredData(RequiredData)
			if type(RequiredData) == "table" and ModuleParams.Initialize ~= false then

				-- Check whitelist
				local Whitelist = ModuleParams.PlaceWhitelist
				if Whitelist and not table.find(Whitelist, game.PlaceId) then
					print("Module",ModuleData.Path,"is not whitelisted in this place.")
					DoDefault()
					continue
				end

				-- Check blacklist
				local Blacklist = ModuleParams.PlaceBlacklist
				if Blacklist and table.find(Blacklist, game.PlaceId) then
					print("Module",ModuleData.Path,"is blacklisted in this place.")
					DoDefault()
					continue
				end

				-- Sanity check priority
				local TargetPriority = ModuleParams.Priority or 0
				if TargetPriority > MAX_PRIORITY then
					warn("Module",ModuleData.Path,"has a priority higher than the max priority of",MAX_PRIORITY," and will be clamped. Please lower the _Priority to avoid unintended behavior.")
					TargetPriority = MAX_PRIORITY
				end

				ModuleData._AutoInitData = {
					Priority = TargetPriority,
					Init = rawget(RequiredData, "Init"),
					RequiredData = RequiredData
				}
			else
				DoDefault()
			end
		end

		-- Order the explicit requires before init
		for _,ModuleData in ipairs(Modules) do
			local TargetIndex = table.find(explictRequires, ModuleData.Path)
			if TargetIndex then
				ModuleData._AutoInitData.Priority = MAX_PRIORITY + TargetIndex
			end
		end

		-- Sort Modules by priority
		table.sort(Modules, function(a, b)
			return a._AutoInitData.Priority > b._AutoInitData.Priority
		end)

		-- Timer for long init times
		local FocusedModuleData = nil
		local ElapsedTime = 0
		local TimerConnection = RunService.Heartbeat:Connect(function(deltaTime)
			if FocusedModuleData and ElapsedTime < LONG_INIT_TIMEOUT then
				ElapsedTime += deltaTime
				if ElapsedTime >= LONG_INIT_TIMEOUT then
					warn("Module",FocusedModuleData.Path,"is taking a long time to complete :Init()")
				end
			end
		end)

		-- Auto initalize modules
		for _,ModuleData in ipairs(Modules) do
			if ModuleData._AutoInitData.Init then
				FocusedModuleData = ModuleData
				ElapsedTime = 0
				ModuleData._AutoInitData.Init(ModuleData._AutoInitData.RequiredData)
				ModuleData._AutoInitData = nil
			end
		end
		TimerConnection:Disconnect()
		InitalizedModules = true
		self.InitalizedModulesEvent:Fire()
	else
		error("You can only initalize modules once per context!")
	end
end

--= Initializers =--
for _,PathData in ipairs(MODULE_PATHS) do
	PathData.Instance.DescendantAdded:Connect(function(Module)
		if InitializingModules == true then
			warn("Module",Module.Name,"replicated late to",PathData.Alias,"module folder. This may cause unexpected behavior.")
		end
		AddModule(PathData, Module)
	end)
	for _,Module in pairs(PathData.Instance:GetDescendants()) do
		AddModule(PathData, Module)
	end
end

-- Bind call metatable
_G.require = NewRequire -- // Legacy support
shared.require = NewRequire

local CallMetaTable = {
	__call = function(_, ...)
		return NewRequire(...)
	end
}
setmetatable(shared,CallMetaTable)
setmetatable(RequireModule,CallMetaTable)

return RequireModule