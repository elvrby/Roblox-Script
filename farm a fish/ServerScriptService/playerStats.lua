-- Server: menyiapkan nilai yang direplikasi ke client
-- R15 compatible

local Players = game:GetService("Players")

-- Konfigurasi default
local MAX_STAMINA = 100
local MAX_OXYGEN  = 100

local function ensureNumberValue(parent: Instance, name: string, default: number)
	local nv = parent:FindFirstChild(name)
	if not nv or not nv:IsA("NumberValue") then
		nv = Instance.new("NumberValue")
		nv.Name = name
		nv.Parent = parent
	end
	nv.Value = default
	return nv
end

Players.PlayerAdded:Connect(function(player)
	ensureNumberValue(player, "Stamina", MAX_STAMINA)
	ensureNumberValue(player, "MaxStamina", MAX_STAMINA)
	ensureNumberValue(player, "Oxygen", MAX_OXYGEN)
	ensureNumberValue(player, "MaxOxygen", MAX_OXYGEN)
end)

-- (Opsional) Players.PlayerRemoving:Connect(function(player) end)
