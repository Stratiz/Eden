-- Stratiz 2022
-- Updated: 05/10/2022
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Maid = shared("Maid")
local Signal = shared("Signal")

local InputController = {}

InputController.CurrentInputType = nil --// "Keyboard" or "Touch" or "Controller"
InputController.InputTypeChangedSignal = Signal.new()

InputController.Inputs = {}

local CurrentGamepadEnum = Enum.UserInputType.Gamepad1

local function DeactivateMappedInput(MappedInput,...)
    if MappedInput.Active == true then
        MappedInput.Active = false
        MappedInput.Changed:Fire(...)
    end
    MappedInput.Ended:Fire(...)
end

local function ActivateMappedInput(MappedInput,...)
    if MappedInput.Active == false then
        MappedInput.Active = true
        MappedInput.Changed:Fire(...)
    end
    MappedInput.Began:Fire(...)
end

function InputController:Init()

    local function InputTypeChanged(NewType)
        InputController.CurrentInputType = NewType
        InputController.InputTypeChangedSignal:Fire(NewType)
    end

    --// Functions for checking if input is bound and activating their binds
    local function CheckAndTrigger(activate : boolean ,inputObject : InputObject, gameProcessed : boolean?, ...)
        for MapName,MapData in pairs(self.Inputs) do
            if MapData.Active then
                for _,MappedInput in ipairs(MapData.Binds) do
                    if gameProcessed == nil or MappedInput.Config.GameProcessed == gameProcessed then
                        if table.find(MappedInput.Config.Enums,inputObject.KeyCode) or table.find(MappedInput.Config.Enums,inputObject.UserInputType) then
                            -- Activate
                            if activate == true then
                                ActivateMappedInput(MappedInput ,...)
                            else
                                DeactivateMappedInput(MappedInput,...)
                            end
                        end
                    end
                end
            end
        end
    end

    --// Detect controller change and load states
    local GamepadStates = {}
    local function LoadGamepadStates(GamepadEnum)
        local RawGamepadStates = UserInputService:GetGamepadState(GamepadEnum)
        GamepadStates = {}
        for _,State in pairs(RawGamepadStates) do
            GamepadStates[State.KeyCode] = State
        end
        CurrentGamepadEnum = GamepadEnum
    end
    LoadGamepadStates(Enum.UserInputType.Gamepad1)
    UserInputService.GamepadConnected:Connect(LoadGamepadStates)
    UserInputService.GamepadDisconnected:Connect(function(GamepadEnum)
        if GamepadEnum == CurrentGamepadEnum then
            for _,Gamepad in pairs(UserInputService:GetConnectedGamepads()) do
                LoadGamepadStates(GamepadEnum)
                break
            end
        end
    end)

    --// Detect controller analog input
    local ControllerAnalogInputs = {
        Enum.KeyCode.ButtonR2,
        Enum.KeyCode.ButtonL2
    }
    local ActivatedAnalogInputs = {}
    RunService:BindToRenderStep("InputController",150,function()
        if #UserInputService:GetConnectedGamepads() > 0 then
            for _,InputObject in pairs(GamepadStates) do
                if table.find(ControllerAnalogInputs,InputObject.KeyCode) then
                    if InputObject.Position.Z >= 0.5 and not ActivatedAnalogInputs[InputObject.KeyCode] then
                        ActivatedAnalogInputs[InputObject.KeyCode] = true
                        CheckAndTrigger(true, InputObject )
                    elseif InputObject.Position.Z < 0.5 and ActivatedAnalogInputs[InputObject.KeyCode] then
                        CheckAndTrigger(false, InputObject)
                        ActivatedAnalogInputs[InputObject.KeyCode] = false
                    end
                end
            end
        end
    end)

    --// Detect digital Inputs and fire their signals
    UserInputService.InputBegan:Connect(function(InputObject,GameProcessed)
        if not table.find(ControllerAnalogInputs,InputObject.KeyCode) or InputObject.KeyCode == Enum.KeyCode.ButtonSelect then
            CheckAndTrigger(true, InputObject, GameProcessed)
        end
    end)
    UserInputService.InputEnded:Connect(function(InputObject,GameProcessed)
        if not table.find(ControllerAnalogInputs,InputObject.KeyCode) or InputObject.KeyCode == Enum.KeyCode.ButtonSelect then
            CheckAndTrigger(false, InputObject, GameProcessed)
        end
    end)

    --// Set CurrentInputType
    if UserInputService.GamepadEnabled then
        InputController.CurrentInputType = "Controller"
    elseif UserInputService.TouchEnabled then
        InputController.CurrentInputType = "Touch"
    else
        InputController.CurrentInputType = "Keyboard"
    end

    --// Detect CurrentInputType changes from 'MouseMovement'
    local isLastInputObjectMouseMovement
    UserInputService.InputChanged:Connect(function(InputObject)
        if InputObject.UserInputType == Enum.UserInputType.MouseMovement then
            if isLastInputObjectMouseMovement and InputController.CurrentInputType ~= "Keyboard" then
                InputTypeChanged("Keyboard")
            end
        --// Detect changes from the unique 'MouseWheel'
        elseif InputObject.UserInputType == Enum.UserInputType.MouseWheel then
            if InputObject.Position.Z < 0 then
                -- implement Activate
            elseif InputObject.Position.Z > 0 then
                -- implement Activate again
            end
        end

        isLastInputObjectMouseMovement = InputObject.UserInputType == Enum.UserInputType.MouseMovement
    end)

    --// Detect CurrentInputType changes from 'LastInputType'
    UserInputService.LastInputTypeChanged:Connect(function(LastType)
        local NewType = InputController:GetInputTypeString(LastType)
        if NewType and NewType ~= InputController.CurrentInputType then
            InputTypeChanged(NewType)
        end
    end)
end

function InputController:Bind(InputMap : string | {}, Enums : {}) : {}
    if not Enums then
        Enums = InputMap
        InputMap = "Default"
    end
    
    if not self.Inputs[InputMap] then
        self.Inputs[InputMap] = {
            Active = true,
            Binds = {}
        }
    end
    
    local NewInputObject = { 
        Began = Signal.new(),
        Ended = Signal.new(),
        Changed = Signal.new(),
        Active = false,
        Config = {
            Enums = Enums,
            GameProcessed = false
        }
    }

    -- Catch button instances
    for Index, Button in Enums do
        if typeof(Button) == "Instance" then
            if Button:IsA("GuiButton") then
                Button.Activated:Connect(function()
                    if NewInputObject.Active == false then
                        ActivateMappedInput(NewInputObject)
                        task.wait()
                        DeactivateMappedInput(NewInputObject)
                    end
                end)
            end
        end
    end
    --

    table.insert(self.Inputs[InputMap].Binds,NewInputObject)
    return NewInputObject
end

function InputController:SetMapEnabled(mapName: string, enabled: boolean)
    if self.Inputs[mapName] then
        self.Inputs[mapName].Active = enabled
    end
end

function InputController:GetInputTypeString(InputEnum)
    if InputEnum == Enum.UserInputType.Keyboard then
        return "Keyboard"
    elseif InputEnum == Enum.UserInputType.Touch then
        return "Touch"
    elseif string.match(tostring(InputEnum),"Gamepad") then
        return "Controller"
    end
end

return InputController