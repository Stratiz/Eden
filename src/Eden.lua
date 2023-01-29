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
local StarterPlayer = game:GetService("StarterPlayer")
local Players = game:GetService("Players")

--= Types =--
type ModuleState = "INACTIVE" | "ACTIVE" | "LOADING"

type ModuleData = {
	Name: string,
	Instance: ModuleScript,
	Path: string,
	State : ModuleState,
	RequiredBy: { ModuleData },
	AutoInitData: {
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
	Connect: (self : any, toExecute : (any) -> ()) -> RBXScriptConnection,
	Fire: (any),
	Wait: (self : any) -> any,
}

--= Constants =--
local DEBUG_LEVEL = 0 -- 0 = None, 1 = Uncommon info, 2 = Phase info, 3 = Module timings
local FIND_TIMEOUT = 3
local LONG_LOAD_TIMEOUT = 5
local LONG_INIT_TIMEOUT = 8
local MAX_PRIORITY = 2^16
local PATH_SEPERATOR = "/"
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
		Instance = (
			if RunService:IsRunning() then
				Players.LocalPlayer:WaitForChild("PlayerScripts")
			else
				StarterPlayer:WaitForChild("StarterPlayerScripts")
			):WaitForChild("ClientModules")
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
local NativePrint = print
local NativeWarn = warn

--= Internal Functions =--
local function print(debugLevel : number, ...)
	if debugLevel <= DEBUG_LEVEL then
		NativePrint("[EDEN]", ...)
	end
end

local function warn(...)
	NativeWarn("[EDEN]", ...)
end

-- Creates a signal object
local function MakeSignal() : Signal
	local bindableEvent = Instance.new("BindableEvent")
	local newSignal = {}
	function newSignal:Connect(toExecute : (any) -> ()) : RBXScriptConnection
		return bindableEvent.Event:Connect(toExecute)
	end

	function newSignal:Fire(... : any)
		bindableEvent:Fire(...)
	end

	function newSignal:Wait() : any
		return bindableEvent.Event:Wait()
	end

	return newSignal
end

-- Gets the path string for a ModuleScript
local function GetModulePath(pathData : PathData, module : ModuleScript) : string
	local currentParent : Instance = module
	local orderedInstanceTable = {}
	repeat
		table.insert(orderedInstanceTable, 1, currentParent.Name)
		currentParent = currentParent.Parent or game
	until currentParent == pathData.Instance or currentParent == game
	return pathData.Alias..PATH_SEPERATOR..table.concat(orderedInstanceTable, PATH_SEPERATOR)
end

-- Adds a module to the Modules table
local function AddModule(pathData : PathData, module : ModuleScript) : boolean
	if module:IsA("ModuleScript") then
		local newModuleData = {
			Instance = module,
			Name = module.Name,
			Path = GetModulePath(pathData, module),
			State = "INACTIVE" :: ModuleState,
			RequiredBy = {},
			AutoInitData = {
				Priority = 0
			}
		}
		ModuleCount += 1

		table.insert(Modules, newModuleData)
		return true
	else
		return false
	end
end

-- Returns a string of the circular dependency tree if one exists.
local function FindCycle(requirerModuleData : ModuleData, targetModuleData : ModuleData, _cycleString : string?) : string?
	local currentCycleString = requirerModuleData.Path.." -> "..(_cycleString or targetModuleData.Path)

	for _, requirer in requirerModuleData.RequiredBy do
		if targetModuleData == requirer then
			return requirer.Path.." -> "..currentCycleString
		else
			return FindCycle(requirer, targetModuleData, currentCycleString)
		end
	end

	return nil
end

-- Gets the custom module parameters and returns them as a dictionary
local function GetParamsFromRequiredData(requiredData : any) : { [string] : any }
	local params = {}

	if type(requiredData) == "table" then
		for _, paramName in SPECIAL_PARAMS do
			params[paramName] = rawget(requiredData, paramName)
		end
	end

	return params
end

-- Returns the module data object for a module if the query is found
local function FindModule(query : string) : ModuleData?
	local found = {}

	for _,ModuleData in ipairs(Modules) do
		if ModuleData.Name == query or ModuleData.Path == query then
			table.insert(found, ModuleData)
		end
	end

	if #found > 1 then
		warn("Multiple modules found with the name '"..query.."'. To clarify, please use the path instead. (ex: Shared/Framework/Module)")
	end

	return found[1]
end

-- The main require function that overrides the default require function
local function NewRequire(query : string | ModuleScript, _fromInternal : boolean?) : any
	-- Default require functionality
	if typeof(query) == "Instance" then
		return require(query :: ModuleScript) --//TC: Luau typechecking doesnt like this because its not an explict path, which is why we wont use !strict
	end

	local currentTimeout = 0
	local targetModuleData = FindModule(query :: string)
	local currentModuleCount = 0
	
	while not targetModuleData and currentTimeout < FIND_TIMEOUT do
		if currentModuleCount ~= ModuleCount then
			currentModuleCount = ModuleCount
			FindModule(query :: string)
		end

		currentTimeout += task.wait()
	end

	if not targetModuleData then
		error("Module "..(query :: string).." not found",3)
	else
		local firstRequire = false

		-- Check if module is already loaded
		if targetModuleData.State == "INACTIVE" then
			targetModuleData.State = "LOADING"
			firstRequire = true
		end

		-- Start loading timer
		local currentThread = coroutine.running()
		local timeStart = tick()
		task.spawn(function()
			while targetModuleData.State == "LOADING" do
				task.wait()
				if tick() - timeStart > LONG_LOAD_TIMEOUT then
					-- Disabling Luau optimizations for the requiring module to check for cyclical dependencies.
					if _fromInternal ~= true then
						local requirerEnv = getfenv(0)
						local requirer = nil
						for _, moduleData in Modules do
							if moduleData.Instance == requirerEnv.script then
								requirer = moduleData
								break
							end
						end
						if requirer then
							table.insert(targetModuleData.RequiredBy, requirer)
							local cycleString = FindCycle(requirer, targetModuleData)
							if cycleString then
								warn("Cyclical require detected: ("..cycleString..").\nPlease resolve this issue at",string.gsub(debug.traceback(currentThread,"",3),"\n",""))
								return
							end
						end
					end
					
					-- Displaying warning only once by checking if its the first require
					if firstRequire then
						warn("Module", targetModuleData.Path, "is taking a long time to load.")
					end
					break
				end
			end
		end)
		
		-- Require module and return
		local toReturn = require(targetModuleData.Instance) --//TC: Same typechecking issue as above

		if targetModuleData.State == "LOADING" then
			print(3, targetModuleData.Path, "Took",string.format("%.4f", tick()-timeStart),"seconds to require.")
			targetModuleData.State = "ACTIVE"
		end

		return toReturn
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
		local requiring = #Modules
		InitializingModules = true
		explictRequires = explictRequires or {}
		
		local function tryFinalize()
			requiring -= 1
			if requiring > 0 then
				return
			end
			print(2, "Finished requiring modules, starting init...")

			-- Order the explicit requires before init
			for _,moduleData in ipairs(Modules) do
				local targetIndex = table.find(explictRequires :: {any}, moduleData.Path)
				if targetIndex then
					moduleData.AutoInitData.Priority = MAX_PRIORITY + ((#explictRequires - targetIndex) + 1)
				end
			end

			-- Sort Modules by priority
			table.sort(Modules, function(a, b)
				return a.AutoInitData.Priority > b.AutoInitData.Priority
			end)

			-- Timer for long init times
			local focusedModuleData = nil
			local initTime = 0
			local timerConnection = RunService.Heartbeat:Connect(function(deltaTime)
				if focusedModuleData and initTime < LONG_INIT_TIMEOUT then
					initTime += deltaTime
					if initTime >= LONG_INIT_TIMEOUT then
						warn("Module", focusedModuleData.Path, "is taking a long time to complete :Init()")
					end
				end
			end)

			-- Auto initalize modules
			for _, moduleData in ipairs(Modules) do
				if moduleData.AutoInitData.Init then
					focusedModuleData = moduleData
					initTime = 0
					moduleData.AutoInitData.Init(moduleData.AutoInitData.RequiredData)
					print(3, moduleData.Path, "Took",string.format("%.4f", initTime),"seconds to :Init()")
				end
			end
			timerConnection:Disconnect()
			InitalizedModules = true
			InitializingModules = false

			self.InitalizedModulesEvent:Fire()
			
			print(2, "Initialization complete!")
		end

		-- Get Init data
		for _,moduleData in ipairs(Modules) do
			-- Check for static directory
			local directories = moduleData.Path:split(PATH_SEPERATOR)
			local staticIndex
			for index, directoryName in directories do
				if string.lower(directoryName) == "static" then
					staticIndex = index
					break
				end
			end
			if staticIndex then
				tryFinalize()
				continue
			end

			-- Require module
			task.defer(function()
				local success, requiredData = pcall(function()
					return NewRequire(moduleData.Path, true)
				end)
				if not success then
					warn("Module", moduleData.Path, "failed to auto-load:", requiredData)
				end

				local moduleParams = GetParamsFromRequiredData(requiredData)
				if type(requiredData) == "table" and moduleParams.Initialize ~= false then
					-- NOTE: Didnt fix naming here because the feature is slated for deletion in the next commit.
					local Listed = false

					-- Check whitelist
					local Whitelist = moduleParams.PlaceWhitelist
					if Whitelist and #Whitelist > 0 and not table.find(Whitelist, game.PlaceId) then
						print(1, "Module", moduleData.Path, "is not whitelisted in this place.")
						Listed = true
					end

					-- Check blacklist
					local Blacklist = moduleParams.PlaceBlacklist
					if Blacklist and table.find(Blacklist, game.PlaceId) then
						print(1, "Module", moduleData.Path, "is blacklisted in this place.")
						Listed = true
					end

					if not Listed then
						-- Sanity check priority
						local targetPriority = moduleParams.Priority or 0
						if targetPriority > MAX_PRIORITY then
							warn("Module", moduleData.Path, "has a priority higher than the max priority of", MAX_PRIORITY, " and will be clamped. Please lower the 'Priority' to avoid unintended behavior.")
							targetPriority = MAX_PRIORITY
						end

						moduleData.AutoInitData = {
							Priority = targetPriority,
							Init = rawget(requiredData, "Init"),
							RequiredData = requiredData
						}
					end
				end

				tryFinalize()
			end)
		end
	else
		error("You can only initalize modules once per context!")
	end
end

--= Initializers =--
print(2, "Aggregating modules...")

for _, pathData in ipairs(MODULE_PATHS) do
	pathData.Instance.DescendantAdded:Connect(function(moduleInstance)
		local success = AddModule(pathData, moduleInstance)

		if success and InitializingModules == true or InitalizedModules == true then
			warn("Module", moduleInstance.Name, "replicated late to", pathData.Alias, "module folder. This may cause unexpected behavior.")
		end
	end)

	for _, module in pairs(pathData.Instance:GetDescendants()) do
		AddModule(pathData, module)
	end
end

print(2, "Aggregated "..(ModuleCount).." modules!")

-- Bind call metatable
local CallMetaTable = {
	__call = function(_, ...)
		return NewRequire(...)
	end
}

setmetatable(shared, CallMetaTable)
setmetatable(Eden, CallMetaTable)

return Eden