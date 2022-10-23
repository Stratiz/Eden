# [The Eden Framework](https://github.com/Stratiz/Eden)

Eden is a lightweight & flexible module aggregator framework designed to grow with you. Populate the framework with your own utilities, modules from other frameworks, etc., and Eden will take it with little to no modification.

The primary goal of Eden is to eliminate the common hassle when it comes to over-complicated Roblox frameworks. Instead, Eden keeps it lean and straightforward by providing a flexible, essentialistic foundation for you and your team to build your project in a rapid iteration environment like Roblox.

Eden is designed to be used with Rojo but can easily be implemented without it.

*Check out the repository branches for examples of populated Eden projects.*

## Table of Contents
- [The Eden Framework](#the-eden-framework)
  - [Table of Contents](#table-of-contents)
- [Features](#features)
- [Parameters](#parameters)
- [Guidelines](#guidelines)
- [Installation](#installation)
  - [Rojo/GitHub](#rojogithub)
  - [Studio](#studio)
- [Examples & Usage](#examples--usage)
  - [For native Studio users](#for-native-studio-users)
  - [Code](#code)
  
# Features

- **Beginner friendly**

Due to Eden's flexible design, the learning curve is minimal and is perfect for teams onboarding new developers or studios looking for a consistent and predictable framework.

Eden is designed to be as predictable as possible, meaning there's no room for unexpected behavior or obscure edge cases.

- **Module Aggregation for simple requiring**

Eden is a module aggregator framework, which means it takes all of the modules in the provided directories and caches them so they can be accessed with less hassle.

A module require in Eden looks like this: `shared("ModuleName")`

`_G` and `shared` tend to be very controversial within Roblox. In this case, they're used as an alternate `require()` function, so you don't need to require the require module in every module in the game.

You can also require instances directly with `shared()`. Example: `shared(script.Folder.Module)`

- **Auto Initialization**

Another helpful feature that exists in Eden is the auto initialization of functions in priority order.

By putting an `:Init()` method in your module, Eden will automatically call this method in the order you specify by defining an optional `_Priority` variable in the module table when the game starts. The higher the priority number, the sooner the module will run. You can disable this functionality with the `Static` directory feature (see guidelines below) or with the `_Initialize` param.

- **Cyclical module detection**

Silent cyclical hangs are unfortunate, as they cause your game to break silently and take time to find. Thankfully, Eden will automatically detect and warn you if this occurs.

NOTE: Due to Luau limitations, a module that surpasses the `LOAD_TIMEOUT` time will lose any Luau optimizations during that run session.

*Check out the Order framework if you're into cyclicals (https://github.com/michaeldougal/order)*

- **Hang detection**

Sometimes code can infinitely yield silently, and it's essential to know when this issue occurs. Therefore, Eden monitors the execution times of your modules and will warn you if one is taking too long.

- **Flexible file structure**

Eden doesn't care how you organize your modules. You can put all of your modules directly under your root folders or create infinite subfolders. Eden is built to be flexible; make it your own!

# Parameters

**All parameters are optional.**

- **_Priority : number** *(Default: 0)*

An `int` that specifies the order in which the `:Init()` method is called on game start. The higher the priority, the sooner it will run. Negative `int`s are also allowed and will run after everything else.


- **_Initialize : boolean** *(Default: true)*


Specifies whether or not the `:Init()` function is called if present. Suitable for disabling modules.


- **_PlaceBlacklist : { number }** *(Default : {})*


A list of `PlaceId`s in which the module will not run its `:Init()` method


- **_PlaceBlacklist : { number }** *(Default : {})*


A list of `PlaceId`s in which the module will run its`:Init()` method. All other places will not run `:Init()`. An empty list assumes no blacklist.

# Guidelines


Eden is designed to have as few quirks as possible while giving you a reliable foundation to work on.


1. **Modules with the same name should be required by a path string instead of its raw name**

If you have two modules in the project with the same name (except for each one being in different run contexts), Eden will warn you that it doesn't know which one to use. To resolve this, reference the file by its file path in the project.


Example: `shared("Client/Framework/ModuleName")`


2. **Modules that you don't want to be required on runtime must be under a directory named "static"**


By default, Eden will require and preload all of the modules under the projects folders when the game starts, if you have a module that isn't supportive of this behavior, make it a descendant of a folder named `Static` (not case-sensitive).


For example, I want module X not to be required on game start because I will require it separately later. I can put it under a folder called `Static` under any of the root project directories such as `Client` and it will not be required. This is also great for things like `roact`, which has a crazy amount of unused modules.

3. **To use Eden inside of non-module scripts, you cannot reliably use `shared()`**


If you want to use Eden inside of a script that is not a module, you have to require the module directly.


```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local require = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Eden"))

require("ModuleName")
```

1. **Modules cannot have a priority greater than 2^16**

This is for the explicit module require option. If you manage to have more modules than that, you can change that limit up to `2^63-1`

5. **If you have a module that contains variables the same as that of an optional param, Eden will pick up on it and try to use it.**

For example, if you imported a module into Eden that has a `_Initialize` variable in the returned module table, Eden will try to use it, which could cause an error. In this case, you could put this file in a static directory and Eden won't put it through the internal first-time initialization process.


# Installation

## Rojo/GitHub

If you're using GitHub workflow (with or without Rojo), you can start using Eden by pressing "Use this template" at the top of the repository.

## Studio

If you're not using a GitHub workflow and want to use Eden in native Roblox Studio, run the following loader code in the studio **Command Bar (View > Command Bar)** and it will populate studio with the correct modules. You can also use the manual installation guide:

<details>

<summary>Loader code</summary>

<br>

Enable HTTP requests by going to [Home -> Game Settings -> Security -> Allow HTTP Requests] in studio (You may disable this after), then paste and run the following code:


```lua
-- This has intentionally sloppy error handling, if it breaks let it break and report it.
local RawRepoURL = "https://raw.githubusercontent.com/Stratiz/Eden/main/"
local GitHubApiURL = "https://api.github.com/repos/Stratiz/Eden/contents/"

local HttpService = game:GetService("HttpService")

local function HttpGet(url : string)
	return HttpService:GetAsync(url)
end

local function MakeFileFromGithub(filename, url)
	print("Fetching", filename)
	
	local DotPosition = string.find(filename, "%.")
	local TrueFileName = string.sub(filename, 1, DotPosition-1) 
	local FileType = string.sub(filename, DotPosition + 1)
	local FileContent = HttpGet(url)
	
	 
	local ScriptInstance
	if FileType == "server.lua" then
		ScriptInstance = Instance.new("Script")
	elseif FileType == "client.lua" then
		ScriptInstance = Instance.new("LocalScript")
	elseif FileType == "lua" then
		ScriptInstance = Instance.new("ModuleScript")
	end
	
	ScriptInstance.Name = TrueFileName
	ScriptInstance.Source = FileContent
	
	return ScriptInstance
end

local function GetGithubFolder(path : string)
	local NewFolder = Instance.new("Folder")
	for _, TargetFile in HttpService:JSONDecode(HttpGet(GitHubApiURL..path)) do
		if TargetFile.type == "dir" then
			GetGithubFolder(TargetFile.path).Parent = NewFolder
		elseif TargetFile.type == "file" then
			MakeFileFromGithub(TargetFile.name, TargetFile.download_url).Parent = NewFolder
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
					table.insert(ToParent, {Parent = parent, Instance = MakeFileFromGithub(DirData[#DirData], RawRepoURL..Path)})
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

6. In studio, copy and paste the contents of `ServerLoader.server.lua` into a Script called "ServerLoader" directly under `ServerScriptService`

7. In studio, copy and paste the contents of `ClientLoader.client.lua` into a Script called "ClientLoader" directly under `ReplicatedFirst`

8. Done!

</details>

  

# Examples & Usage

## For native Studio users

If you're using Eden without a GitHub workflow follow these important guidelines:

1. Server modules will go under `ServerScriptService -> ServerModules`

2. Shared modules which can be used by client or server will go under `ReplicatedStorage -> SharedModules`

3. Client modules will go under `StarterPlayer -> StarterPlayerScripts -> ClientModules`


## Code

Here's an example of a barebones Eden module that makes use of all the parameters and features.

```lua
--= Root =--
local Example = {
  -- All of the following parameters are optional.
  _Priority = 0, -- The default priority is 0. The higher the priority, the earlier the module will be loaded. Negative priorities are allowed and will always be loaded last.

  _Initialize = true, -- Determines if this modules :Init function will be called. If false, the module will not be initialized. Suitable for disabling modules.

  -- These two are suitable for games that require modules to only run in certain places under a universe
  _PlaceBlacklist = {
    123, -- The place ID of the place to blacklist.
  },
  _PlaceWhitelist = {
    456, -- The place ID of the place to whitelist. If this table is empty, all places will be allowed.
  }
}

--= Dependencies =--

-- If the module has a unique name you don't need to use the path and you can require by name "Example".

--"Shared/Example" is the path to the module. This is the same as the path in the file explorer.
local OtherExampleModule = shared("Shared/Example")

--= Initializers =--
function Example:Init() -- This function will be called when the module is initialized. This is also optional.
  -- Do stuff here.
end

--= Return Module =--
return  Example
```