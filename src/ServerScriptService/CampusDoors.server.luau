-- CampusDoors: every part tagged "CampusDoor" (the university's room and building doors) swings open
-- or shut on its hinge when someone uses its prompt. The hinge is on the door's -X edge (attribute
-- HingeX); OpenAngle says how far and which way it swings.
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local SWING = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local function hook(door: Instance)
	if not door:IsA("BasePart") or door:GetAttribute("DoorHooked") then return end
	door:SetAttribute("DoorHooked", true)
	local prompt = door:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then return end
	local closed = door.CFrame
	local hinge = closed * CFrame.new((door:GetAttribute("HingeX") :: number?) or -door.Size.X / 2, 0, 0)
	local offset = hinge:ToObjectSpace(closed)
	local openAngle = math.rad((door:GetAttribute("OpenAngle") :: number?) or 92)
	local angle = Instance.new("NumberValue")
	angle.Changed:Connect(function(a)
		door.CFrame = hinge * CFrame.Angles(0, a, 0) * offset
	end)
	local open = false
	prompt.Triggered:Connect(function()
		open = not open
		prompt.ActionText = if open then "Close" else "Open"
		TweenService:Create(angle, SWING, { Value = if open then openAngle else 0 }):Play()
	end)
end
for _, d in CollectionService:GetTagged("CampusDoor") do hook(d) end
CollectionService:GetInstanceAddedSignal("CampusDoor"):Connect(hook)
