--[[
	Eden.lua
	Stratiz
	Created on 09/06/2022 @ 21:50
	Updated on 2/24/2023 @ 02:18
	Version: 1.0.0
	
	Description:
		Module aggregator for Eden.
	
	Documentation:
		Instead of require(), Eden uses shared("moduleName") this should only be done inside of module scripts.
		Ideally, your project should only contain module scripts.

		To require modules in script instances, you'll need to directly require the module with the following code:

		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local require = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Eden"))

		.ModulesInitalizedEvent : Signal (See signal type export)
			Signal that fires when all modules have been initialized.

		:AreModulesInitialized() : boolean
			Returns whether or not all modules have been initialized. Good for loading screens.
		
		:AddModulesToInit(addModules : { string | ModuleScript })
			Adds modules to the initialization queue that otherwise wouldnt be initialized. Good for conditionally enabling/loading static modules for things like loading modules
			only under a specific placeId.
			
		:InitModules(initFirst: {string | ModuleScript}?)
			Fires by default in the ServerLoader and ClientLoader scripts.
			Initializes all modules in the context, with the option of explicitly defining what modules load first.
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
	Static : boolean,
	AutoInitData: {
		Priority : number,
		Init: (self : any?) -> ()?,
		RequiredData : any?,
		First : boolean?
	}
}

type PathData = {
	Alias: string,
	Instance: Instance,
}

export type Signal = {
	Connect: (self : Signal, toExecute : (any) -> ()) -> RBXScriptConnection,
	Once: (self : Signal, toExecute : (any) -> ()) -> RBXScriptConnection,
	Fire: (self : Signal, any) -> (),
	Wait: (self : Signal) -> any,
}

--= Constants =--
local CONFIG = require(script:WaitForChild("EdenConfig"))
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
		Instance =  game:GetService("ServerScriptService"):WaitForChild("ServerModules")
	},
	{
		Alias = "Shared",
		Instance = ReplicatedStorage:WaitForChild("SharedModules")
	},
	-- Custom paths
}
local SPECIAL_PARAMS = {
	"Initialize",
	"Priority"
}

--= Variables =--
local Modules : { ModuleData } = {}
local ModuleCount = 0
local InitalizedModules = false
local InitModulesPhaseInt = 0
local AddToInitProcessCount = 0
local NativePrint = print
local NativeWarn = warn

--= Internal Functions =--
local function print(debugLevel : number, ...)
	if debugLevel <= CONFIG.DEBUG_LEVEL and (RunService:IsStudio() or CONFIG.DEBUG_IN_GAME) then
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

	function newSignal:Once(toExecute : (any) -> ()) : RBXScriptConnection
		return bindableEvent.Event:Once(toExecute)
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
	return pathData.Alias..(CONFIG.PATH_SEPERATOR)..table.concat(orderedInstanceTable, CONFIG.PATH_SEPERATOR)
end

-- Adds a module to the Modules table
local function AddModule(pathData : PathData, module : ModuleScript, isStatic : boolean) : boolean
	if module:IsA("ModuleScript") then
		local newModuleData = {
			Instance = module,
			Name = module.Name,
			Path = GetModulePath(pathData, module),
			State = "INACTIVE" :: ModuleState,
			RequiredBy = {},
			Static = isStatic,
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

-- Determines if an instance is a static directory
local function IsObjectStaticDirectory(object : Instance) : boolean
	if object:IsA("Folder") then
		if string.lower(object.Name) == CONFIG.STATIC_DIRECTORY_NAME then
			return true
		end
	elseif CONFIG.SCRIPTS_AS_STATIC_DIRECTORY == true and object:IsA("LuaSourceContainer") then
		return true
	end

	return false
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
		local initParamsContainer = rawget(requiredData, "InitParams")
		local paramsContainer = requiredData

		if initParamsContainer and type(initParamsContainer) == "table" then
			paramsContainer = initParamsContainer
		end

		for _, paramName in SPECIAL_PARAMS do
			params[paramName] = rawget(paramsContainer, paramName)
		end
	end

	return params
end

-- Returns the module data object for a module if the query is found
local function FindModule(query : string | ModuleScript, _currentTimeout : number?) : ModuleData?
	local found = {}

	for _, moduleData in ipairs(Modules) do
		if moduleData.Name == query or moduleData.Path == query or moduleData.Instance == query then
			table.insert(found, moduleData)
		end
	end

	if #found == 0 then
		local currentTimeout = _currentTimeout or 0
		local currentModuleCount = ModuleCount

		repeat
			currentTimeout += task.wait()

			if currentModuleCount ~= ModuleCount then
				return FindModule(query :: string, currentTimeout)
			end
		until currentTimeout >= CONFIG.FIND_TIMEOUT

		return nil
	elseif #found > 1 and type(query) == "string" then
		warn("Multiple modules found with the name '"..query.."'. To clarify, please use the path instead. "..string.gsub("(ex: Shared/Framework/Module)", "/", CONFIG.PATH_SEPERATOR))
	end

	return found[1]
end

-- The main require function that overrides the default require function
local function NewRequire(query : string | ModuleScript, _fromInternal : boolean?) : any
	-- Default require functionality
	if typeof(query) == "Instance" and _fromInternal ~= true then
		return require(query :: ModuleScript) --//TC: Luau typechecking doesnt like this because its not an explicit path, which is why we wont use !strict
	end

	local targetModuleData = FindModule(query)

	if not targetModuleData then
		error("Module "..(query :: string).." not found", 3)
	else
		local firstRequire = false

		-- Check if module is errored
		if targetModuleData.State == "ERROR" and _fromInternal ~= true then
			error("Module ".. targetModuleData.Path.. " has errored and cannot be required until fixed.", 3)
		end

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
				if tick() - timeStart > CONFIG.LONG_LOAD_TIMEOUT then
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
		local success, toReturn = pcall(function()
			return require(targetModuleData.Instance) --//TC: Same typechecking issue as above
		end)

		if not success then
			targetModuleData.State = "ERROR"
			error(toReturn, 3)
		elseif targetModuleData.State == "LOADING" then
			print(3, targetModuleData.Path, "Took", string.format("%.4f", tick()-timeStart), "seconds to require.")
			targetModuleData.State = "ACTIVE"
		end

		return toReturn
	end
end

-- Do the first require for a module
local function DoFirstRequire(moduleData : ModuleData)
	local success, requiredData = pcall(function()
		return NewRequire(moduleData.Instance, true)
	end)
	if not success then
		warn("Module", moduleData.Path, "failed to auto-load. Check output for error from:", moduleData.Instance:GetFullName())
	end

	local moduleParams = GetParamsFromRequiredData(requiredData)
	if type(requiredData) == "table" and moduleParams.Initialize ~= false then

		moduleData.AutoInitData = {
			Priority = moduleParams.Priority or 0,
			Init = rawget(requiredData, "Init"),
			RequiredData = requiredData
		}
	end
end

--= API Methods =--
Eden.ModulesInitalizedEvent = MakeSignal()

-- Getter function for InitializedModules boolean
function Eden:AreModulesInitialized() : boolean
	return InitalizedModules
end

-- Makes static modules active by adding them to the Init flow.
function Eden:AddModulesToInit(addModules : { string | ModuleScript })
	addModules = addModules or {}

	if InitalizedModules == false and InitModulesPhaseInt < 2 then
		AddToInitProcessCount += 1

		local addedCount = 0
		for _, moduleQuery in ipairs(addModules) do
			if type(moduleQuery) ~= "userdata" or moduleQuery:IsA("ModuleScript") then
				task.spawn(function()
					local moduleData = FindModule(moduleQuery)
	
					if moduleData then
						moduleData.Static = false
						DoFirstRequire(moduleData)
					else
						warn("Failed to add module to init flow:", moduleQuery, "not found in Eden directory. Please verify the spelling and/or path.")
					end

					addedCount += 1
				end)
			else 
				warn("Failed to add module to init flow: Instance", moduleQuery:GetFullName(), "is not a valid module query.")
				addedCount += 1
			end
		end

		while #addModules > addedCount do
			task.wait()
		end

		AddToInitProcessCount -= 1
	else
		error("Cannot add modules to Init flow after :InitModules() has finished all module requires.")
	end
end

-- Initializes all modules in the current context
function Eden:InitModules(initFirst : { string | ModuleScript }?)
	if InitalizedModules == false and InitModulesPhaseInt == 0 then
		print(2, "Requiring modules...")
		local requiring = #Modules
		local initFirstArray = initFirst or {}

		InitModulesPhaseInt = 1
		
		local function tryFinalize()
			requiring -= 1
			if requiring > 0 then
				return
			end

			-- Wait for any modules that are being added to the init flow
			while AddToInitProcessCount > 0 do
				task.wait()
			end

			print(2, "Finished requiring modules, starting init...")
			local initThread = coroutine.running()
			InitModulesPhaseInt = 2

			-- Order the first requires before general init
			for index, moduleQuery in ipairs(initFirstArray :: {any}) do
				local moduleData = FindModule(moduleQuery)

				if moduleData then
					moduleData.AutoInitData.First = true
					moduleData.AutoInitData.Priority = (#initFirstArray - index) + 1
				else 
					warn("Failed to prioritize module from initFirst table:", moduleQuery, "not found. Please verify the spelling and/or path.")
				end
			end

			-- Sort Modules by priority
			table.sort(Modules, function(a, b)
				if a.AutoInitData.First == b.AutoInitData.First then
					return a.AutoInitData.Priority > b.AutoInitData.Priority
				else -- Force first modules are always first
					return a.AutoInitData.First == true
				end
			end)

			-- Timer for long init times
			local focusedModuleData = nil
			local initTime = 0
			local statusConnection; statusConnection = RunService.Heartbeat:Connect(function(deltaTime)
				-- Check if init thread is dead from error
				local status = coroutine.status(initThread)
				if status == "dead" and InitalizedModules == false then
					statusConnection:Disconnect()
					warn("Module", focusedModuleData.Path, "failed to :Init(). Error must be resolved or modules next in priority will not execute :Init()")
					return
				end

				-- Check if module is taking too long to init
				if focusedModuleData and initTime < CONFIG.LONG_INIT_TIMEOUT then
					initTime += deltaTime
					if initTime >= CONFIG.LONG_INIT_TIMEOUT then
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
					print(3, moduleData.Path, "Took", string.format("%.4f", initTime), "seconds to :Init()")
				end
			end

			statusConnection:Disconnect()
			InitalizedModules = true
			InitModulesPhaseInt = 3

			self.ModulesInitalizedEvent:Fire()

			print(2, "Initialization complete!")
		end

		-- Get Init data
		for _,moduleData in ipairs(Modules) do
			-- If module is static, skip it
			if moduleData.Static == true then
				tryFinalize()
				continue
			end

			-- Require module
			task.defer(function()
				DoFirstRequire(moduleData)

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
		if moduleInstance:IsA("ModuleScript") then
			local hasStaticParent = false
			
			do -- Check for static parent
				local parent = moduleInstance.Parent
				while parent ~= nil and parent ~= pathData.Instance do
					if IsObjectStaticDirectory(parent) then
						hasStaticParent = true
						break
					end
					parent = parent.Parent
				end
			end

			local success = AddModule(pathData, moduleInstance, hasStaticParent)

			if success and InitModulesPhaseInt > 0 or InitalizedModules == true then
				warn("Module", moduleInstance.Name, "replicated late to", pathData.Alias, "module folder. This may cause unexpected behavior.")
			end
		end
	end)

	local function findModules(directory : Instance, isStatic : boolean )
		for _, object in pairs(directory:GetChildren()) do
			AddModule(pathData, object, isStatic)

			-- Check for static directory and continue searching
			findModules(object, isStatic or IsObjectStaticDirectory(object))
		end
	end

	findModules(pathData.Instance, false)
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