local UtilFunctions = {}

function UtilFunctions:Lerp(v0, v1, t)
	return v0 + t * (v1 - v0)
end

function UtilFunctions:LerpColor(Color1,Color2,Alpha)
    return Color3.new(
        UtilFunctions:Lerp(Color1.R,Color2.R,Alpha),
        UtilFunctions:Lerp(Color1.G,Color2.G,Alpha),
        UtilFunctions:Lerp(Color1.B,Color2.B,Alpha)
    )
end

function UtilFunctions:QuadBezier(t, p0, p1, p2)
	local l1 = UtilFunctions:Lerp(p0, p1, t)
	local l2 = UtilFunctions:Lerp(p1, p2, t)
	local quad = UtilFunctions:Lerp(l1, l2, t)
	return quad
end

function UtilFunctions:FindFirstChildPath(Root : Instance,Path : string)
    local PathTable = string.split(Path,".")
    local CurrentRoot = Root
    for _,NextString in pairs(PathTable) do
        CurrentRoot = CurrentRoot:FindFirstChild(NextString)
        if not CurrentRoot then
            return nil
        end
    end
    return CurrentRoot
end

function UtilFunctions:WaitForChildPath(Root : Instance,Path : string,Timeout : number)
    local PathTable = string.split(Path,".")
    local CurrentRoot = Root
    for _,NextString in pairs(PathTable) do
        CurrentRoot = CurrentRoot:WaitForChild(NextString,Timeout)
        if not CurrentRoot then
            return nil
        end
    end
    return CurrentRoot
end

function UtilFunctions:MakeTableFromValuesFolder(Folder : Instance)
    local NewTable = {}
    for _,ValueInstance in ipairs(Folder:GetChildren()) do
        if ValueInstance:IsA("ValueBase") then
            NewTable[ValueInstance.Name] = ValueInstance.Value
        end
    end
    return NewTable
end

function UtilFunctions:AddCommasToNumber(number: number) : string
    local NumberString = tostring(number)
    if #NumberString <= 3 then
        return NumberString 
    end
    local CommaCount = math.floor(#NumberString / 3)
    
    local StartIndex = (#NumberString % 3)

    local CommaString = string.sub(NumberString,1,StartIndex)
    StartIndex += 1

    for i = 1, CommaCount do
        if i ~= 1 or #CommaString ~= 0 then
            CommaString = CommaString .. ","
        end
        CommaString ..= string.sub(NumberString,StartIndex,StartIndex+2)
        StartIndex += 2
    end
    return CommaString

end

local Suffix = {"","K","M","B","T","q","Q","s"}
function UtilFunctions:ReadableNumber(num, places)
    places = places or 1
    local Zeros = #tostring(math.floor(num)) - 1
    local Index = math.floor(Zeros/3) + 1
    local Rounded = (math.floor((num/(10^((Index-1)*3)))*10^places)/10^places)

    return Rounded .. Suffix[Index]
end

return UtilFunctions