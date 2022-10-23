--[[
	Eden.lua
	Stratiz
	Created on 09/06/2022 @ 21:50
	Updated on 10/23/2022 @ 01:41
	
	Description:
		Module aggregator for Eden.
	
	Documentation:
		Instead of require(), Eden uses shared("moduleName") this should only be done inside of module scripts.
		Ideally, your project should only contain module scripts.

		To require modules in script instances, you'll need to directly require the module with the following code:

		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local require = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Eden"))

		.InitalizedModulesEvent : Signal (See signal type export)
			Signal that fires when all modules have been initialized.

		:AreModulesInitialized() : boolean
			Returns whether or not all modules have been initialized. Good for loading screens.
			
		:InitModules(explictRequires: {string}?)
			Fires by default in the ServerLoader and ClientLoader scripts.
			Initializes all modules in the context, with the option of explictly defining what modules load first. This is a legacy feature but is still supported.
--]]

--= Root =--
local Eden = { }

--= Roblox Services =--
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--= Types =--
type ModuleState = "INACTIVE" | "ACTIVE" | "LOADING"

type ModuleData = {
	Name: string,
	Instance: ModuleScript,
	Path: string,
	State : ModuleState,
	RequiredBy: { ModuleData },
	_AutoInitData: {
		Priority : number,
		Init: (self : any?) -> ()?,
		RequiredData : any?
	}
}

type PathData = {
	Alias: string,
	Instance: Instance,
}

export type Signal = {
	Connect: <T>(self : T, toExecute : (any) -> ()) -> RBXScriptConnection,
	Fire: (any),
	Wait: <T>(self : T) -> any,
}

--= Constants =--
local DEBUG_LEVEL = 0 -- 0 = None, 1 = Uncommon info, 2 = Phase info, 3 = Module timings
local FIND_TIMEOUT = 3
local LONG_LOAD_TIMEOUT = 5
local LONG_INIT_TIMEOUT = 8
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
local Modules : { ModuleData } = {}
local ModuleCount = 0
local InitializingModules = false
local InitalizedModules = false
local _print = print
local _warn = warn

--= Internal Functions =--
local function print(debugLevel : number, ...)
	if debugLevel <= DEBUG_LEVEL then
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
	function Signal:Connect(toExecute : (any) -> ()) : RBXScriptConnection
		return BindableEvent.Event:Connect(toExecute)
	end

	function Signal:Fire(... : any)
		BindableEvent:Fire(...)
	end

	function Signal:Wait() : any
		return BindableEvent.Event:Wait()
	end

	return Signal
end

-- Gets the path string for a ModuleScript
local function GetModulePath(pathData : PathData, module : ModuleScript) : string
	local CurrentParent : Instance = module
	local OrderedInstanceTable = {}
	repeat
		table.insert(OrderedInstanceTable, 1, CurrentParent.Name)
		CurrentParent = CurrentParent.Parent or game
	until CurrentParent == pathData.Instance or CurrentParent == game
	return pathData.Alias.."/"..table.concat(OrderedInstanceTable, "/")
end

-- Adds a module to the Modules table
local function AddModule(pathData : PathData, module : ModuleScript)
	if module:IsA("ModuleScript") then
		local NewModuleData = {
			Instance = module,
			Name = module.Name,
			Path = GetModulePath(pathData, module),
			State = "INACTIVE" :: ModuleState,
			RequiredBy = {},
			_AutoInitData = {
				Priority = 0
			}
		}
		ModuleCount += 1

		table.insert(Modules, NewModuleData)
	end
end

-- Returns a string of the circular dependency tree if one exists.
local function FindCycle(requirerModuleData : ModuleData, targetModuleData : ModuleData, _cycleString : string?) : string?
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
local function NewRequire(query : string | ModuleScript, _fromInternal : boolean?) : any
	-- Default require functionality
	if typeof(query) == "Instance" then
		return require(query :: ModuleScript) --//TC: Luau typechecking doesnt like this because its not an explict path, which is why we wont use !strict
	end

	local CurrentTimeout = 0
	local TargetModuleData = FindModule(query :: string)
	
	local CurrentModuleCount = 0
	while not TargetModuleData and CurrentTimeout < FIND_TIMEOUT do
		if CurrentModuleCount ~= ModuleCount then
			CurrentModuleCount = ModuleCount
			FindModule(query :: string)
		end
		local Delta = task.wait()
		CurrentTimeout += Delta
	end

	if not TargetModuleData then
		error("Module "..(query :: string).." not found",3)
	else
		local FirstRequire = false

		-- Check if module is already loaded
		if TargetModuleData.State == "INACTIVE" then
			TargetModuleData.State = "LOADING"
			FirstRequire = true
		end

		-- Start loading timer
		local CurrentThread = coroutine.running()
		local TimeStart = tick()
		task.spawn(function()
			while TargetModuleData.State == "LOADING" do
				task.wait()
				if tick() - TimeStart > LONG_LOAD_TIMEOUT then
					-- Disabling Luau optimizations for the requiring module to check for cyclical dependencies.
					if _fromInternal ~= true then
						local RequirerEnv = getfenv(0)
						local Requirer = nil
						for _, ModuleData in Modules do
							if ModuleData.Instance == RequirerEnv.script then
								Requirer = ModuleData
								break
							end
						end
						if Requirer then
							table.insert(TargetModuleData.RequiredBy, Requirer)
							local CycleString = FindCycle(Requirer, TargetModuleData)
							if CycleString then
								warn("Cyclical require detected: ("..CycleString..").\nPlease resolve this issue at",string.gsub(debug.traceback(CurrentThread,"",3),"\n",""))
								return
							end
						end
					end
					
					-- Displaying warning only once by checking if its the first require
					if FirstRequire then
						warn("Module",TargetModuleData.Path,"is taking a long time to load.")
					end
					break
				end
			end
		end)
		
		-- Require module and return
		local ToReturn = require(TargetModuleData.Instance) --//TC: Same typechecking issue as above
		if TargetModuleData.State == "LOADING" then
			print(3, TargetModuleData.Path, "Took",string.format("%.4f", tick()-TimeStart),"seconds to require.")
			TargetModuleData.State = "ACTIVE"
		end
		return ToReturn
	end
end

--= API Methods =--
Eden.InitalizedModulesEvent = MakeSignal()

-- Getter function for InitializedModules boolean
function Eden:AreModulesInitialized() : boolean
	return InitalizedModules
end

-- Initializes all modules in the current context
function Eden:InitModules(explictRequires : { string }?)
	if InitializingModules == false then
		print(2, "Requiring modules...")
		local Requiring = #Modules
		InitializingModules = true
		explictRequires = explictRequires or {}
		
		local function TryFinalize()
			Requiring -= 1
			if Requiring > 0 then
				return
			end
			print(2, "Finished requiring modules, starting init...")

			-- Order the explicit requires before init
			for _,ModuleData in ipairs(Modules) do
				local TargetIndex = table.find(explictRequires :: {any}, ModuleData.Path)
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
					print(3, ModuleData.Path, "Took",string.format("%.4f", ElapsedTime),"seconds to :Init()")
				end
			end
			TimerConnection:Disconnect()
			InitalizedModules = true
			self.InitalizedModulesEvent:Fire()
			print(2, "Initialization complete!")
		end

		-- Get Init data
		for _,ModuleData in ipairs(Modules) do
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
				TryFinalize()
				continue
			end

			-- Require module
			task.defer(function()
				local Success, RequiredData = pcall(function()
					return NewRequire(ModuleData.Path, true)
				end)
				if not Success then
					warn("Module",ModuleData.Path,"failed to auto-load:",RequiredData)
				end

				local ModuleParams = GetParamsFromRequiredData(RequiredData)
				if type(RequiredData) == "table" and ModuleParams.Initialize ~= false then
					local Listed = false

					-- Check whitelist
					local Whitelist = ModuleParams.PlaceWhitelist
					if Whitelist and #Whitelist > 0 and not table.find(Whitelist, game.PlaceId) then
						print(1, "Module",ModuleData.Path,"is not whitelisted in this place.")
						Listed = true
					end

					-- Check blacklist
					local Blacklist = ModuleParams.PlaceBlacklist
					if Blacklist and table.find(Blacklist, game.PlaceId) then
						print(1, "Module",ModuleData.Path,"is blacklisted in this place.")
						Listed = true
					end

					if not Listed then
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
					end
				end

				TryFinalize()
			end)
		end
	else
		error("You can only initalize modules once per context!")
	end
end

--= Initializers =--
print(2, "Aggregating modules...")
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
print(2, "Aggregated "..(#Modules).." modules!")

-- Bind call metatable
_G.require = NewRequire -- // Legacy support
shared.require = NewRequire

local CallMetaTable = {
	__call = function(_, ...)
		return NewRequire(...)
	end
}
setmetatable(shared,CallMetaTable)
setmetatable(Eden,CallMetaTable)

return Eden