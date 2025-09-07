-- StarterPlayerScripts/HideCoreBackpack.client.lua
-- Sembunyikan Backpack default + arahkan tombol 1..0 ke handler custom.

local StarterGui = game:GetService("StarterGui")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local NUMBER_KEYS = {
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
	Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine, Enum.KeyCode.Zero,
}

local function disableCore()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	-- (opsional) hilangkan topbar:
	-- pcall(function() StarterGui:SetCore("TopbarEnabled", false) end)
end

-- ====== Forward ke handler kita ======
-- Kita tidak hanya "sink", tapi memanggil RemoteBind "HotbarEquip_SelectSlot"
local function onNumberKey(actionName, inputState, input)
	if inputState ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end

	local key = input.KeyCode
	local slot
	if key == Enum.KeyCode.Zero then slot = 10
	elseif key == Enum.KeyCode.One then slot = 1
	elseif key == Enum.KeyCode.Two then slot = 2
	elseif key == Enum.KeyCode.Three then slot = 3
	elseif key == Enum.KeyCode.Four then slot = 4
	elseif key == Enum.KeyCode.Five then slot = 5
	elseif key == Enum.KeyCode.Six then slot = 6
	elseif key == Enum.KeyCode.Seven then slot = 7
	elseif key == Enum.KeyCode.Eight then slot = 8
	elseif key == Enum.KeyCode.Nine then slot = 9
	end

	if slot then
		-- Kirim sinyal lokal (Bindables) biar script hotbar yang equip
		local pg = player:FindFirstChild("PlayerGui")
		if pg then
			local invGui = pg:FindFirstChild("InventoryGui")
			if invGui then
				local binder = invGui:FindFirstChild("HotbarEquip_SelectSlot")
				if binder and binder:IsA("BindableEvent") then
					binder:Fire(slot)
				end
			end
		end
	end
	return Enum.ContextActionResult.Sink
end

local function bindKeys()
	ContextActionService:BindAction("CustomHotbar_EquipSlot", onNumberKey, false, table.unpack(NUMBER_KEYS))
end

disableCore()
bindKeys()

player.CharacterAdded:Connect(function()
	task.defer(disableCore)
	task.defer(bindKeys)
end)
