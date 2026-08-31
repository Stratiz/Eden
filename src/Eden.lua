--[[
	Eden.lua
	Stratiz
	Created on 09/06/2022 @ 21:50
	Updated on 7/27/2026 @ 22:00
	Version: 2.0.0

	Description:
		Module loader for Eden.

	Documentation:
		Eden requires and initializes every module in your project directories for you. Modules require
		each other with plain require(), so Luau tooling (luau-lsp, selene, Studio script analysis) keeps
		full type information:

		local MyModule = require(ReplicatedStorage.SharedModules.MyModule)

		.ModulesInitializedEvent : Signal (See signal type export)
			Signal that fires when all modules have been initialized.

		:AreModulesInitialized() : boolean
			Returns whether or not all modules have been initialized. Good for loading screens.

		:AddModulesToInit(addModules : { Instance })
			Adds modules to the initialization queue that otherwise wouldn't be initialized. Good for conditionally enabling/loading static modules for things like loading modules
			only under a specific placeId. Non-ModuleScripts are ignored, so script:GetChildren() can be passed directly.

		:InitModules(initFirst : { Instance }?)
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
type ModuleState = "INACTIVE" | "ACTIVE" | "LOADING" | "ERROR"

type ModuleData = {
	Name: string,
	Instance: ModuleScript,
	Path: string,
	State : ModuleState,
	Static : boolean,
	AutoInitData: {
		Priority : number,
		Init: ((self : any?) -> ())?,
		HasExplicitPriority : boolean?,
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

-- External dependency directories (Wally, etc). Their direct children are always aggregated as static modules.
local PACKAGE_PATHS : { PathData } = {
	{
		Alias = "Packages",
		Instance = ReplicatedStorage:WaitForChild("Packages")
	},
}
local SPECIAL_PARAMS = {
	"Initialize",
	"Priority"
}

--= Variables =--
local Modules : { ModuleData } = {}
local ModuleFromInstance : { [Instance] : ModuleData } = {}
local ModuleCount = 0
local InitializedModules = false
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

-- Gets the path string for a ModuleScript. Only used to label modules in the output.
local function GetModulePath(pathData : PathData, module : ModuleScript) : string
	local currentParent : Instance = module
	local orderedInstanceTable = {}
	repeat
		table.insert(orderedInstanceTable, 1, currentParent.Name)
		currentParent = currentParent.Parent or game
	until currentParent == pathData.Instance or currentParent == game
	return pathData.Alias..(CONFIG.PATH_SEPARATOR)..table.concat(orderedInstanceTable, CONFIG.PATH_SEPARATOR)
end

-- Adds a module to the Modules table
local function AddModule(pathData : PathData, module : Instance, isStatic : boolean) : boolean
	if not module:IsA("ModuleScript") or module == script then
		return false
	end

	local newModuleData : ModuleData = {
		Instance = module,
		Name = module.Name,
		Path = GetModulePath(pathData, module),
		State = "INACTIVE" :: ModuleState,
		Static = isStatic,
		AutoInitData = {
			Priority = 0
		}
	}

	ModuleCount += 1
	table.insert(Modules, newModuleData)
	ModuleFromInstance[module] = newModuleData

	return true
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

-- Requires a module for the first time and reads its auto-init parameters.
-- Never raises: a module that fails to load must not stop the rest of the flow.
local function DoFirstRequire(moduleData : ModuleData)
	moduleData.State = "LOADING"

	local timeStart = tick()

	-- Watch for module bodies that never finish (infinite yields, cyclical requires, etc)
	task.spawn(function()
		while moduleData.State == "LOADING" do
			if tick() - timeStart >= CONFIG.LONG_LOAD_TIMEOUT then
				warn("Module", moduleData.Path, "is taking a long time to load. This is usually caused by an infinite yield or a cyclical require in the module body.")
				break
			end
			task.wait()
		end
	end)

	local success, requiredData = pcall(require, moduleData.Instance)

	if not success then
		moduleData.State = "ERROR"
		warn("Module", moduleData.Path, "failed to load. Check output for the error from:", moduleData.Instance:GetFullName())
		return
	end

	moduleData.State = "ACTIVE"
	print(3, moduleData.Path, "Took", string.format("%.4f", tick() - timeStart), "seconds to require.")

	local moduleParams = GetParamsFromRequiredData(requiredData)
	if type(requiredData) == "table" and moduleParams.Initialize ~= false then
		moduleData.AutoInitData = {
			HasExplicitPriority = moduleParams.Priority ~= nil,
			Priority = moduleParams.Priority or 0,
			Init = rawget(requiredData, "Init"),
			RequiredData = requiredData
		}
	end
end

--= API Methods =--
Eden.ModulesInitializedEvent = MakeSignal()

-- Getter function for InitializedModules boolean
function Eden:AreModulesInitialized() : boolean
	return InitializedModules
end

-- Makes static modules active by adding them to the Init flow.
function Eden:AddModulesToInit(addModules : { Instance })
	addModules = addModules or {}

	if InitializedModules == true or InitModulesPhaseInt >= 2 then
		error("Cannot add modules to Init flow after :InitModules() has finished all module requires.")
	end

	AddToInitProcessCount += 1

	local pending = #addModules
	local completed = 0

	for _, moduleInstance in ipairs(addModules) do
		task.spawn(function()
			local moduleData = if typeof(moduleInstance) == "Instance" then ModuleFromInstance[moduleInstance] else nil

			if moduleData then
				if moduleData.State == "INACTIVE" then
					moduleData.Static = false
					DoFirstRequire(moduleData)
				end
			elseif typeof(moduleInstance) ~= "Instance" then
				warn("Failed to add module to init flow: expected a ModuleScript, got", typeof(moduleInstance), "-", moduleInstance)
			elseif moduleInstance:IsA("ModuleScript") then
				warn("Failed to add module to init flow:", moduleInstance:GetFullName(), "is not inside an Eden module directory.")
			end
			-- Anything else is ignored silently, since script:GetChildren() commonly includes non-modules

			completed += 1
		end)
	end

	while completed < pending do
		task.wait()
	end

	AddToInitProcessCount -= 1
end

-- Initializes all modules in the current context
function Eden:InitModules(initFirst : { Instance }?)
	if InitializedModules == true or InitModulesPhaseInt > 0 then
		error("You can only initialize modules once per context!")
	end

	InitModulesPhaseInt = 1
	print(2, "Requiring modules...")

	-- Require every non-static module in parallel so one yielding module body doesn't block the rest
	local pending = 0
	local completed = 0

	for _, moduleData in ipairs(Modules) do
		if moduleData.Static == false then
			pending += 1
			task.defer(function()
				DoFirstRequire(moduleData)
				completed += 1
			end)
		end
	end

	-- Wait on the requires, including any modules pulled in by :AddModulesToInit()
	while completed < pending or AddToInitProcessCount > 0 do
		task.wait()
	end

	print(2, "Finished requiring modules, starting init...")
	InitModulesPhaseInt = 2

	-- Order the explicit first modules before general init
	local initFirstArray = initFirst or {}
	for index, moduleInstance in ipairs(initFirstArray) do
		local moduleData = if typeof(moduleInstance) == "Instance" then ModuleFromInstance[moduleInstance] else nil

		if moduleData then
			moduleData.AutoInitData.First = true
			moduleData.AutoInitData.Priority = (#initFirstArray - index) + 1
		else
			warn("Failed to prioritize module from initFirst table:", moduleInstance, "is not inside an Eden module directory.")
		end
	end

	-- Sort Modules by priority
	table.sort(Modules, function(a, b)
		if a.AutoInitData.First ~= b.AutoInitData.First then -- Force first modules are always first
			return a.AutoInitData.First == true
		elseif a.AutoInitData.Priority ~= b.AutoInitData.Priority then
			return a.AutoInitData.Priority > b.AutoInitData.Priority
		else -- Tie break alphabetically so init order is deterministic
			return a.Path < b.Path
		end
	end)

	-- Timer for long init times
	local focusedModuleData : ModuleData? = nil
	local initStartTime = 0
	local warnedLongInit = false
	local statusConnection = RunService.Heartbeat:Connect(function()
		local moduleData = focusedModuleData
		if moduleData and warnedLongInit == false and tick() - initStartTime >= CONFIG.LONG_INIT_TIMEOUT then
			warnedLongInit = true
			warn("Module", moduleData.Path, "is taking a long time to complete :Init()")
		end
	end)

	-- Auto initialize modules
	local success, initError = xpcall(function()
		for _, moduleData in ipairs(Modules) do
			local init = moduleData.AutoInitData.Init
			if not init then
				continue
			end

			focusedModuleData = moduleData
			initStartTime = tick()
			warnedLongInit = false

			if moduleData.AutoInitData.HasExplicitPriority == true or CONFIG.PCALL_NON_PRIORITY_MODULES == false then
				init(moduleData.AutoInitData.RequiredData)
			else
				local initSuccess, thisError = pcall(init, moduleData.AutoInitData.RequiredData)
				if not initSuccess then
					warn("Module", moduleData.Path, "failed to :Init() because:\n", thisError)
				end
			end

			print(3, moduleData.Path, "Took", string.format("%.4f", tick() - initStartTime), "seconds to :Init()")
		end
	end, function(thisError)
		return debug.traceback(tostring(thisError), 2)
	end)

	statusConnection:Disconnect()

	if not success then
		warn("Module", focusedModuleData and focusedModuleData.Path or "?", "failed to :Init(). Error must be resolved or modules next in priority will not execute :Init()\n"..tostring(initError))
		return
	end

	InitializedModules = true
	InitModulesPhaseInt = 3

	self.ModulesInitializedEvent:Fire()

	print(2, "Initialization complete!")
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

			if success and (InitModulesPhaseInt > 0 or InitializedModules == true) then
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

-- Add external packages
for _, pathData in ipairs(PACKAGE_PATHS) do
	pathData.Instance.ChildAdded:Connect(function(newChild)
		AddModule(pathData, newChild, true)
	end)

	for _, package in ipairs(pathData.Instance:GetChildren()) do
		AddModule(pathData, package, true)
	end
end

print(2, "Aggregated "..(ModuleCount).." modules!")

return Eden
