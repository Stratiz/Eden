
<img src="https://github.com/Stratiz/Repository-CDN/blob/main/Eden/EDEN_Banner.png?raw=true" alt="Logo" width="100%">

# [The Eden Framework](https://github.com/Stratiz/Eden) 

Eden is a lightweight & flexible module loader designed to grow with you. Populate the framework with your own utilities, modules from other frameworks, etc., and Eden will take it with ease.

Eden handles loading and initializing your modules, and you require modules the normal way, so autocomplete, type checking and linting keep working.

The primary goal of Eden is to eliminate the common hassle when it comes to over-complicated Roblox frameworks. Eden keeps it lean and straightforward by providing a flexible, essentialistic foundation for you and your team to build your project in a rapid iteration environment like Roblox.

Eden is designed to be used with Rojo but can easily be implemented without it.

## Table of Contents
- [The Eden Framework](#the-eden-framework)
	- [Table of Contents](#table-of-contents)
- [Features](#features)
- [Requiring modules](#requiring-modules)
	- [Why doesn't Eden replace `require()`?](#why-doesnt-eden-replace-require)
- [Parameters](#parameters)
- [Guidelines](#guidelines)
- [Eden Module](#eden-module)
	- [Methods](#methods)
	- [Properties](#properties)
	- [Types](#types)
- [Config](#config)
- [Installation](#installation)
	- [Rojo/GitHub](#rojogithub)
	- [Studio](#studio)
- [Examples \& Usage](#examples--usage)
	- [For native Studio users](#for-native-studio-users)
	- [Code](#code)
  
# Features

- **Beginner friendly**

Due to Eden's flexible design, the learning curve is minimal and is perfect for teams onboarding new developers or studios looking for a consistent and predictable framework.

Eden is designed to be as predictable as possible, meaning there's no room for unexpected behavior or tedious edge cases.

- **Module Aggregation**

Eden takes every module in the provided directories and loads them for you on startup, so you never have to wire up a manual list of what to load and in what order.

Requiring stays completely normal:

```lua
local MyModule = require(ReplicatedStorage.SharedModules.MyModule)
```

See [Requiring modules](#requiring-modules) for the reasoning.

- **Auto Initialization**

Another helpful feature that exists in Eden is the auto initialization of functions in priority order.

By putting an `:Init()` method in your module, Eden will automatically call this method in the order you specify by defining an optional `Priority` variable in the module table when the game starts. The higher the priority number, the sooner the module will run. You can disable this functionality with the `Static` directory feature (see guidelines below) or with the `Initialize` parameter.

- **Hang detection**

Sometimes code yields forever, and does so silently. Roblox's own cyclical require detection misses this case when a yielding call like `:WaitForChild()` is involved, so your game breaks with nothing in the output to explain it.

Eden times the load of every module it requires and the `:Init()` of every module it initializes, then warns you by name when one takes too long. That covers the usual suspects: infinite yields and the cyclical requires Roblox lets slip through.

- **Failures stay contained**

A module that errors while loading doesn't take the rest of your game down with it. Eden reports which module failed and carries on loading and initializing everything else.

- **Flexible file structure**

Eden doesn't care how you organize your modules. You can put all of your modules directly under your root folders or create infinite subfolders. Eden is built to be flexible; make it your own!

# Requiring modules

With `require()`

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MyModule = require(ReplicatedStorage.SharedModules.MyModule)
```

You only require the Eden module itself when you need one of [its methods](#eden-module):

```lua
local Eden = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Eden"))

Eden.ModulesInitializedEvent:Wait()
```

## Why doesn't Eden replace `require()`?

Because a require that takes a name can't be typed.

Earlier versions of Eden let you write `shared("MyModule")` or `Eden("MyModule")`. It read nicely, but Luau has no way to resolve a runtime string back to a module, so **every** module you pulled in that way came back as `any`. No autocomplete, no go-to-definition, no type errors when you misused a return value, and `--!strict` reduced to noise. On top of that, `shared` is a context-wide global that any plugin or third party module can overwrite, and Selene rejects calling it without a custom standard library file.

The only ways to make a string require typed are to generate an index module or a set of overloaded function type declarations at build time. Both need a build step that reruns whenever a file moves, and neither works in the Studio-native workflow Eden supports. A plain `require()` gets you the same module with none of that, so that's what Eden uses.

# Parameters

**All parameters are optional.**

- **Priority : number** *(Default: 0)*

	An `int` that specifies the order in which the `:Init()` method is called on game start. The higher the priority, the sooner it will run. Negative `int`s are also allowed and will run after everything else.


- **Initialize : boolean** *(Default: true)*


	Specifies whether or not the `:Init()` function is called if present. Suitable for disabling modules.


In the event these parameters collide with parameters in one of your modules and you want to isolate them, **you can put them in a ***InitParams*** dictionary and the properties in the root of the module will be ignored**

Example:
```lua
local module = {
   InitParams = { -- These will be used by Eden instead.
     Priority = 20
     Initialize = false
   }

   Priority = 1 -- Eden will ignore this because InitParams is present.
}

return module
```

# Guidelines


Eden is designed to have as few quirks as possible while giving you a reliable foundation to work on.


1. **Modules that you don't want to be required on runtime must be under a directory named "static"**


By default, Eden will require and preload all of the modules under the projects folders when the game starts, if you have a module that isn't supportive of this behavior, make it a descendant of a folder named `Static` (not case-sensitive).


For example, I want module X not to be required on game start because I will require it separately later. I can put it under a folder called `Static` under any of the root project directories such as `Client` and it will not be required. This is also great for things like `roact`, which has a crazy amount of unused modules.

2. **If you have a module that contains variables the same as that of an optional param, Eden will pick up on it and try to use it.**

For example, if you imported a module into Eden that has a `Initialize` variable in the returned module table, Eden will try to use it, which could cause an error. In this case, you should use the ***InitParams*** structure seen [above](#parameters). Alternatively, you could put this file in a static directory and Eden won't put it through the internal first-time initialization process.

3. **Don't rely on another module's `:Init()` having run inside your own module body.**

Eden requires every module before it initializes any of them, so at the time your module body runs, nothing has been `:Init()`'d yet. Use `Priority` to order the `:Init()` calls, or wait on [`.ModulesInitializedEvent`](#properties).

# Eden Module

The primary Eden module comes with some useful public methods to interact with the framework. 
To access the Eden module, require it directly: `require(ReplicatedStorage.SharedModules.Eden)`.
## Methods
- **:AreModulesInitialized() : `boolean`**
  
	Returns whether or not all modules have been initialized. Good for loading screens.

- **:AddModulesToInit(*addModules* : `{ Instance }`)**
  
	Adds modules to the initialization queue that otherwise wouldn't be initialized. Good for conditionally enabling/loading static modules for things like loading modules
	only under a specific placeId.

	Non-ModuleScripts are ignored, so you can pass `script:GetChildren()` directly.

- **:InitModules(*initFirst* : `{ Instance }?`)**
  
	Fires by default in the ServerLoader and ClientLoader scripts.
	Initializes all modules in the context, with the option of explicitly defining what modules will `:Init()` first with absolute priority.

## Properties
- **.ModulesInitializedEvent** : `Signal`
  
	A signal that fires once all the modules have finished initializing.

## Types
-  **Signal**
  
	Used to mimic an `RBXScriptSignal` since they're not creatable.

	*Methods:*
		
	- **:Connect(*toExecute* : `(any) -> ()`) -> `RBXScriptConnection`**
  
		Connects a callback function to trigger when the signal is fired

	- **:Once(*toExecute* : `(any) -> ()`) -> `RBXScriptConnection`**
  
		Connects a callback function to trigger when the signal is fired, and then automatically disconnects itself from the signal.
		
	- **:Fire(`any`)**

		Invoke all connected callbacks

	- **:Wait() -> `any`**

		Yields until the Signal is Fire()'d

# Config

In the root directory of your repository, there should always be a `Eden.config.lua` file. This file is the primary user facing configuration for Eden. (File is `EdenConfig` under `Eden` for studio users)

- **DEBUG_LEVEL** : `number` *(Default: 1)*
  
  Very useful for getting insight on whats holding up your call stack.
  1 = Errors & Warnings only, 2 = Phase info, 3 = Module timings

- **DEBUG_IN_GAME** : `boolean` *(Default: false)*

  If true, will print debug messages to the in-game console. Warnings and errors will always be printed to the in-game console regardless of the state of this option.

- **LONG_LOAD_TIMEOUT** : `number` *(Default: 5)*

  The amount of time in seconds Eden should wait before warning that a module is taking a long time to load.

- **LONG_INIT_TIMEOUT** : `number` *(Default: 8)*

  The amount of time in seconds Eden should wait before warning that a modules `:Init()` function is taking a long time.

- **PATH_SEPARATOR** : `string` *(Default: "/")*

  The character Eden uses to separate names when it labels a module in the output, for example `Server/Example`. Display only.

- **STATIC_DIRECTORY_NAME** : `string` *(Default: "static")*
  
  The non-case sensitive folder name Eden should look for when detecting static directories. 

- **SCRIPTS_AS_STATIC_DIRECTORY** : `boolean` *(Default: true)*

  When true, Eden will treat any type of script instance as a static directory, meaning descendant modules of a module or script won't be automatically required and :Init()'ed
  
  In the event where you want a module's child modules to go through the automatic Init, you could pass them through `:AddModulesToInit()`
  ```lua
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local Eden = require(ReplicatedStorage.SharedModules.Eden)

  local module = {}

  Eden:AddModulesToInit(script:GetChildren())

  return module
  ```
- **PCALL_NON_PRIORITY_MODULES** : `boolean` *(Default: false)*

  If true, all modules that error during `:Init()` without an explicit Priority parameter set will not break the init chain. Default is set to false as `:Init()` errors become less visible in the output.

# Installation

## Rojo/GitHub

If you're using GitHub workflow (with or without Rojo), you can start using Eden by pressing "Use this template" at the top of the repository.

## Studio

Eden is designed for users that use external IDEs such as VSCode, but if you'd like to run it in a native studio workflow, follow the instructions below:

If you're not using a GitHub workflow and want to use Eden in native Roblox Studio, run the following loader code in the studio **Command Bar (View > Command Bar)** and it will populate studio with the correct modules. You can also use the manual installation guide:

<details>

<summary>Loader code</summary>

<br>

Enable HTTP requests by going to [Home -> Game Settings -> Security -> Allow HTTP Requests] in studio (You may disable this after), then paste and run the following code in the command bar [View -> Command Bar]:

```lua
-- This has intentionally sloppy error handling, if it breaks let it break and report it.
local RawRepoURL = "https://raw.githubusercontent.com/Stratiz/Eden/main/"
local GitHubApiURL = "https://api.github.com/repos/Stratiz/Eden/contents/"

local HttpService = game:GetService("HttpService")

local function HttpGet(url : string)
	return HttpService:GetAsync(url)
end

local function MakeFileFromGithub(filename, url, alias)
	local FileNameParts = string.split(filename, ".")
	local TrueFileName = FileNameParts[1]

	table.remove(FileNameParts, 1)

	-- Skip anything that isn't lua source (.gitkeep, .md, etc)
	if FileNameParts[#FileNameParts] ~= "lua" then
		return nil
	end

	print("Fetching", filename)

	local FileContent = HttpGet(url)

	local ScriptInstance
	if FileNameParts[#FileNameParts - 1] == "server" then
		ScriptInstance = Instance.new("Script")
	elseif FileNameParts[#FileNameParts - 1] == "client" then
		ScriptInstance = Instance.new("LocalScript")
	else
		ScriptInstance = Instance.new("ModuleScript")
	end

	ScriptInstance.Name = alias or TrueFileName
	ScriptInstance.Source = FileContent

	return ScriptInstance
end

local function GetGithubFolder(path : string)
	local NewFolder = Instance.new("Folder")
	for _, TargetFile in HttpService:JSONDecode(HttpGet(GitHubApiURL..path)) do
		if TargetFile.type == "dir" then
			GetGithubFolder(TargetFile.path).Parent = NewFolder
		elseif TargetFile.type == "file" then
			local NewFile = MakeFileFromGithub(TargetFile.name, TargetFile.download_url)
			if NewFile then
				NewFile.Parent = NewFolder
			end
		end
	end
	
	return NewFolder
end

local ToParent = {}
local function FindFolder(target, parent)
	for DirectoryName, DirectoryData in pairs(target) do
		if type(DirectoryData) == "table" then
			local ClassName = DirectoryData["$className"]
			if ClassName then
				FindFolder(DirectoryData, parent[ClassName])
			else
				local Path = DirectoryData["$path"]
				if string.match(Path, ".lua") then
					local DirData = string.split(Path, "/")
					local NewFile = MakeFileFromGithub(DirData[#DirData], RawRepoURL..Path, DirectoryName)
					table.insert(ToParent, {Parent = parent, Instance = NewFile})

					for key, value in DirectoryData do
						if string.sub(key, 1, 1) ~= "$" then
							FindFolder(DirectoryData, NewFile)
						end
					end
				else
					local NewFolder = GetGithubFolder(Path)
					NewFolder.Name = DirectoryName
					table.insert(ToParent, {Parent = parent, Instance = NewFolder})
					FindFolder(DirectoryData, NewFolder)
				end
			end
		end
	end
end

print("Working...")

local ProjectJson = HttpService:JSONDecode(HttpGet(RawRepoURL.."default.project.json"))
FindFolder(ProjectJson.tree, game)

-- Ensures we only insert instances if everything succeeds
for _, Data in pairs(ToParent) do
	if Data.Instance then
		Data.Instance.Parent = Data.Parent
	end
end

print("Done!")
```

</details>

<details>

<summary>Manual installation guide</summary>

<br>

1. Download the source code by pressing the `Code` button at the top of the repository and pressing "Download ZIP"

2. Unzip the file and open the "src" folder

3. In the studio, create a folder under `ServerScriptService` called "ServerModules", this folder is where you will put all of your server code **modules**.

4. In studio, create a folder under `StarterPlayer -> StarterPlayerScripts` called "ClientModules", this folder is where you will put all of your client code **modules**.

5. In the studio, create a folder under `ReplicatedStorage` called "SharedModules", this folder is where you will put all of your code that needs to be shared between the client and server.

6. In studio, create a folder under `ReplicatedStorage` called "Packages", this folder is where your external dependencies (Wally, etc) go. **This folder is required even if you have no dependencies**
   
7. In studio, copy and paste the contents of `Eden.lua` into a ModuleScript called "Eden" under "SharedModules" folder in `ReplicatedStorage`
   
8. In studio, copy and paste the contents of `Eden.config.lua` into a ModuleScript called "EdenConfig" under the "Eden" module in "SharedModules"

9. In studio, copy and paste the contents of `ServerLoader.server.lua` into a Script called "ServerLoader" directly under `ServerScriptService`

10. In studio, copy and paste the contents of `ClientLoader.client.lua` into a Script called "ClientLoader" directly under `ReplicatedFirst`

11. Done!

</details>

  

# Examples & Usage

## For native Studio users

If you're using Eden without a GitHub workflow follow these important guidelines:

1. Server modules will go under `ServerScriptService -> ServerModules`

2. Shared modules which can be used by client or server will go under `ReplicatedStorage -> SharedModules`

3. Client modules will go under `StarterPlayer -> StarterPlayerScripts -> ClientModules`

4. External dependencies (Wally, etc) go under `ReplicatedStorage -> Packages`. Its contents are always treated as [static](#guidelines). This folder must exist, but it can be empty.


## Code

Here's an example of a barebones Eden module that makes use of all the parameters and features.

```lua
--= Root =--
local Example = {
  -- All of the following parameters are optional.
  Priority = 0, -- The default priority is 0. The higher the priority, the earlier the module will be loaded. Negative priorities are allowed and will always be loaded last.

  Initialize = true -- Determines if this modules :Init function will be called. If false, the module will not be initialized. Suitable for disabling modules.
}

--= Dependencies =--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules are required normally, so you keep autocomplete and type checking.
local OtherExampleModule = require(ReplicatedStorage.SharedModules.Example)

--= Initializers =--
function Example:Init() -- This function will be called when the module is initialized. This is also optional.
  -- Do stuff here.
end

--= Return Module =--
return  Example
```
