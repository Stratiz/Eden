-- Stratiz 2021 :)
local SoundService = game:GetService("SoundService")

local SoundFolder = workspace:FindFirstChild("_SOUNDS") or Instance.new("Folder")
SoundFolder.Name = "_SOUNDS"
SoundFolder.Parent = workspace

-- Aggregate sounds
local Sounds = {}
for _,Sound in pairs(SoundService:GetDescendants()) do
	if Sound:IsA("Sound") then
		Sounds[Sound.Name] = Sound
		Sound.SoundGroup = Sound:FindFirstAncestorOfClass("SoundGroup")
	end
end
----
local SoundSystem = {}

function SoundSystem:PlaySound(SoundName,Static)
	if Sounds[SoundName] then
		local NewSound = not Static and Sounds[SoundName]:Clone() or Sounds[SoundName]
		if not Static then
			NewSound.Parent = SoundFolder
			NewSound:Play()
			coroutine.resume(coroutine.create(function()
				NewSound.Ended:Wait()
				NewSound:Destroy()
			end))
		end
		return NewSound
	else
		error("Invalid sound name: "..SoundName)
	end
end

return SoundSystem