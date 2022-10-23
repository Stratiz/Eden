# The Eden Framework

Eden is a lightweight & flexible module aggregator framework designed to evolve with you. Populate the framework with your own utilities, modules from other frameworks, etc. and Eden will take it with little to no modification.

The primary goal of Eden is to eliminate the common hassle when it comes to over-complicated Roblox frameworks. Eden keeps it simple by providing the essential and friendly foundation for you and your team to quickly build your project in a rapid iteration environment such as Roblox. 

Eden is designed to be used with Rojo, but can very easily be implemented without it.

*Check out the repository branches for examples of populated Eden projects.*

# Features
- **Module Aggregation for simple requiring**

Eden is a module aggregator framework, which means it takes all of the modules in the provided directories and caches them so they can be accessed with less hassle.

A module require in Eden looks like this: `shared("ModuleName")`

`_G` and `shared` tend to be very controversial within Roblox. In this case, they're being used as an alternate `require()` function, so you don't need to require the require module in every module in the game. 

You can also require instances directly with `shared()`. Example: `shared(script.Folder.Module)`

- **Auto Initialization**

Another popular framework feature that exists in Eden is the auto initialization of functions in priority order. 

By putting an `:Init()` method in your module, Eden will automatically call this method in the order you specify by defining an optional `_Priority` variable in the module table when the game starts. The higher the priority number the sooner the module will run. You can disable this functionality with the `Static` directory rule (see rules below) or with the `_Initialize` param.

- **Cyclical module detection**

Silent cyclical hangs are terrible. They cause your game to break silently and it can be a pain to find. Thankfully, Eden will automatically detect and warn you if this occurs.

*Check out the Order framework if you're into Cyclicals (https://github.com/michaeldougal/order)*

- **Hang detection**

Sometimes code can infinitely yield silently, and it's important to know what modules are having this issue when it occurs. Eden monitors the execution times of your modules and will warn you if one is taking a bit too long.
- **Flexible file structure**

Eden doesn't care how you organize your modules. You can put all of your modules directly under your root folders or you can create infinite subfolders. Eden is built to be flexible, make it your own! 

# Parameters

**All parameters are optional.**
- **_Priority : `number`** *(Default: 0)*
  
An `int` that specifies the order in which the `:Init()` method is called on game start. The higher the priority the sooner it will run. Negative `ints` are allowed as well and will run after everything else.

  - **_Initialize : `boolean`** *(Default: true)*

Specifies whether or not the `:Init()` function is called if present. Good for disabling modules.


  - **_PlaceBlacklist : `{ number }`** *(Default : {})*

A list of `PlaceId`s in which the module will not run its `:Init()` method 

- **_PlaceBlacklist : `{ number }`** *(Default : {})*

A list of `PlaceId`s in which the module will run its`:Init()` method. All other places will not run `:Init()`. An empty list assumes no blacklist.
# Rules

Everyone hates too many rules in frameworks, as they tend to get in the way of a developer's workflow. Eden is designed to have as few as possible while still giving you a reliable foundation to work on.

1. **Modules with the same name should be required by a path string instead of its raw name**
  
If you have 2 modules in the project with the same name (with the exception of one each of which being in different run contexts) Eden will warn you that it doesn't know which one to use. To resolve this simply reference the file by its file path in the project.

Example: `shared("Client/Framework/ModuleName")`

 2. **Modules that you don't want to be required on runtime must be under a directory named "static"**

By default, Eden will require and preload all of the modules under the projects folders when the game starts, if you have a module that isn't supportive of this behavior, make it a descendant of a folder named `Static` (not case-sensitive).

For example, I want module `A` to not be required on game start because I'm going to require it separately later. I can put it under a folder called `Static` under any of the root project directories such as `Client` and it will not be required. This is also great for things like `roact` which has a crazy amount of unused modules.

3. **To use Eden inside of non-module scripts, you cannot reliably use `shared()`**

If you want to use Eden inside of a script that is not a module, you have to require the module directly.

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local require = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Eden"))

require("ModuleName")
```

 1. **Modules cannot have a priority greater than 2^16**

This is for the explicit module require option which is made for certain nevermore users, but the chances of you having that many modules in your game are extremely unlikely so you'll be fine. If not you can change that limit up to `2^63-1`


5. **If you have a module that contains variables the same as that of an optional param, Eden will pick up on it and try to use it.**

For example, if you imported a module into Eden that has a `_Initialize` variable in the returned module table, Eden will try to use it and it could cause an error. In this case, you could put this file in a static directory and Eden won't put it through the internal first-time initialization process. 

# Examples

Here's an example of a barebones Eden module that makes use of all the parameters and features.

```lua
--= Root =--
local Example = {
    -- All of the following paramers are optional.
    _Priority = 0, -- The default priority is 0. The higher the priority, the earlier the module will be loaded. Negative priorities are allowed and will always be loaded last.
    _Initialize = true, -- Determines if this modules :Init function will be called. If false, the module will not be initialized. Good for disabling modules.

    -- These two are good for games that require modules to only run in certain places under a universe
    _PlaceBlacklist = {
        123, -- The place ID of the place to blacklist.
    },
    _PlaceWhitelist = {
        456, -- The place ID of the place to whitelist. If this table is empty, all places will be allowed.
    }
}

--= Dependencies =--

-- If the module has a unique name you dont need to use the path and you can require by name "Example".
--"Shared/Example" is the path to the module. This is the same as the path in the file explorer.
local OtherExampleModule = shared("Shared/Example")

--= Initializers =--
function Example:Init() -- This function will be called when the module is initialized. This is also optional
    -- Do stuff here.
end

--= Return Module =--
return Example
```