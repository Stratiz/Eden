-- Stratiz 9/21/2021
local UICore = {}
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundSystem = _G.require("SoundSystem")
local UtilFunctions = _G.require("UtilFunctions")

function UICore:Init()
    --local HoverTweenInfo = TweenInfo.new(0.25,Enum.EasingStyle.Quint,Enum.EasingDirection.In)
    local ClickTweenInfo = TweenInfo.new(0.1,Enum.EasingStyle.Quint,Enum.EasingDirection.In,0,true)
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
    for _,UI in pairs(PlayerGui:GetChildren()) do
        if UI:IsA("ScreenGui") then
            UICore[UI.Name] = UI
        end
    end
    --require("WindowHandler"):Init()
    -- Sounds
    for _,Button in ipairs(PlayerGui:GetDescendants()) do
        if Button:IsA("GuiButton") then
            local ButtonSize = Button.Size
            --local HoverTween = TweenService:Create(Button,HoverTweenInfo,{Rotation = 20})
            --local LeaveTween = TweenService:Create(Button,HoverTweenInfo,{Rotation = 0})
            local ClickTween = TweenService:Create(Button,ClickTweenInfo,{Rotation = 10})
            Button.MouseEnter:Connect(function()
                --SoundSystem:PlaySound("UiHover")
                
            end)
            Button.Activated:Connect(function()
                --SoundSystem:PlaySound("UiClick")
                --local TweenToPosition = UDim2.new(0,Button.AbsolutePosition.X + (Button.AbsoluteSize.X/2),0,Button.AbsolutePosition.Y + (Button.AbsoluteSize.Y/2))
                --ClickTween:Play() --Size = UDim2.new(ButtonSize.X.Scale * 0.5,ButtonSize.X.Offset * 0.5,ButtonSize.Y.Scale * 0.5,ButtonSize.Y.Offset * 0.5)
            end)
        end
    end
end

function UICore:GetUI(Start,Path)
    if not Path then
        Path = Start
        Start = nil
    end
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
    return UtilFunctions:WaitForChildPath(Start or PlayerGui,Path)
end

return UICore