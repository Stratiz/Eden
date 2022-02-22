local Weld = {}

function Weld.WeldPair(x, y, ToObject)
	local weld = Instance.new("Weld",x)
	weld.Part0 = x
	weld.Part1 = y
	if ToObject then
		weld.C1 = y.CFrame:toObjectSpace(x.CFrame)
	end
    return weld
end

function Weld:WeldModelToPrimary(Model)
    if Model.PrimaryPart then
        for _,Part in ipairs(Model:GetDescendants()) do
            if Part:IsA("BasePart") and Part ~= Model.PrimaryPart then
                self.WeldPair(Model.PrimaryPart,Part,true)
                Part.Anchored = false
            end
        end
    else
        error("Cannot weld model, model has no primary part")
    end
end

return Weld