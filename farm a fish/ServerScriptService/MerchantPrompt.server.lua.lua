-- ServerScriptService/MerchantPrompt.server.lua
local Workspace = game:GetService("Workspace")

local function ensurePrompt(part: BasePart)
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "MerchantPrompt"
		prompt.ObjectText = "Merchant"
		prompt.ActionText = "Interaksi"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 12
		prompt.Parent = part
	end
	return prompt
end

for _, obj in ipairs(Workspace:GetDescendants()) do
	if obj:IsA("BasePart") and obj.Name == "MerchantStand" then
		ensurePrompt(obj)
	end
end

Workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("BasePart") and obj.Name == "MerchantStand" then
		ensurePrompt(obj)
	end
end)
