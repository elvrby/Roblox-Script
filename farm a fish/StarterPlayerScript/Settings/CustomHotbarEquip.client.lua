-- StarterPlayerScripts/CustomHotbarEquip.client.lua
-- Klik slot / tekan 1..0:
-- - Jika Tool pada slot tersebut sudah di-equip -> UNEQUIP
-- - Jika belum, EQUIP Tool yang ter-bind pada slot itu (berdasarkan HotbarBindings)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local function getHumanoid(): Humanoid?
	local char = player.Character or player.CharacterAdded:Wait()
	return char:FindFirstChildOfClass("Humanoid")
end

local function toolEquippedWithName(name: string): boolean
	local char = player.Character
	if not char then return false end
	for _, ch in ipairs(char:GetChildren()) do
		if ch:IsA("Tool") and ch.Name == name then
			return true
		end
	end
	return false
end

local function findToolByName(name: string): Tool?
	local char = player.Character
	if char then
		for _, ch in ipairs(char:GetChildren()) do
			if ch:IsA("Tool") and ch.Name == name then return ch end
		end
	end
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp then
		for _, ch in ipairs(bp:GetChildren()) do
			if ch:IsA("Tool") and ch.Name == name then return ch end
		end
	end
	return nil
end

local function waitForUI()
	local pg = player:WaitForChild("PlayerGui")
	local invGui = pg:WaitForChild("InventoryGui")
	-- Bindables
	local bus = invGui:FindFirstChild("HotbarEquip_SelectSlot")
	if not bus then
		bus = Instance.new("BindableEvent")
		bus.Name = "HotbarEquip_SelectSlot"
		bus.Parent = invGui
	end
	-- Binding folder
	local bindings = invGui:FindFirstChild("HotbarBindings")
	while not bindings do
		RunService.RenderStepped:Wait()
		bindings = invGui:FindFirstChild("HotbarBindings")
	end
	-- Hotbar frame
	local bar = invGui:FindFirstChild("BackpackBar")
	while not (bar and bar:IsA("Frame")) do
		RunService.RenderStepped:Wait()
		bar = invGui:FindFirstChild("BackpackBar")
	end
	return invGui, bar, bus, bindings
end

local invGui, bar, bus, bindings = waitForUI()

local function slotKey(i: number): string
	return ("Slot%d"):format(i)
end

local function getBinding(i: number): string
	local sv = bindings:FindFirstChild(slotKey(i))
	return (sv and sv.Value) or ""
end

local function equipToggleSlot(i: number)
	if i < 1 or i > 10 then return end
	local toolName = getBinding(i)
	if toolName == "" then return end

	local hum = getHumanoid()
	if not hum then return end

	if toolEquippedWithName(toolName) then
		-- sudah equip -> unequip semua
		hum:UnequipTools()
	else
		-- equip tool sesuai nama (dari Character/Backpack)
		local tool = findToolByName(toolName)
		if tool then
			pcall(function()
				hum:EquipTool(tool)
			end)
		end
	end
end

-- Klik slot -> toggle equip
local function hookClickSlots()
	for _, slot in ipairs(bar:GetChildren()) do
		if slot:IsA("Frame") then
			slot.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch then
					local name = slot.Name
					local n = tonumber(string.match(name, "^Slot_(%d)$"))
					if n == 0 then n = 10 end
					if not n then
						-- fallback by order
						local idx = 0
						for _, s in ipairs(bar:GetChildren()) do
							if s:IsA("Frame") then
								idx += 1
								if s == slot then n = idx; break end
							end
						end
					end
					if n then equipToggleSlot(n) end
				end
			end)
		end
	end
end
hookClickSlots()

-- Rehook bila UI hotbar dibangun ulang
bar.ChildAdded:Connect(function(ch)
	if ch:IsA("Frame") then
		task.defer(hookClickSlots)
	end
end)

-- Terima event dari HideCoreBackpack (key 1..0)
bus.Event:Connect(function(slotIndex: number)
	equipToggleSlot(slotIndex)
end)
