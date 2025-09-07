-- StarterPlayerScripts/InventoryClient.client.lua
-- Hotbar slot PERSISTEN (1..0), drag & drop ALL qty
-- Mapping ToolName <-> itemId dibangun OTOMATIS dari INV_STATE (server mengirim toolName per item)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")

-- ===== GUI refs =====
local inventoryGui     = gui:WaitForChild("InventoryGui")              :: ScreenGui
local inventoryFrame   = inventoryGui:WaitForChild("InventoryFrame")   :: Frame
local scrolling        = inventoryFrame:WaitForChild("ScrollingFrame") :: ScrollingFrame
local btnInvExit       = inventoryFrame:FindFirstChild("exit")         :: TextButton?
local btnInventoryMenu = inventoryGui:WaitForChild("InventoryMenu")    :: TextButton
local hotbar           = inventoryGui:FindFirstChild("BackpackBar")    :: Frame?

-- posisikan kursor akurat pada GUI (hilangkan inset topbar)
inventoryGui.IgnoreGuiInset = true

-- ===== Remotes =====
local Remotes      = ReplicatedStorage:WaitForChild("ShopRemotes")
local INV_STATE    = Remotes:WaitForChild("InventoryState")
local REQ_WITHDRAW = Remotes:WaitForChild("WithdrawRequest")
local REQ_DEPOSIT  = Remotes:WaitForChild("DepositRequest")
local RES_PURCHASE = Remotes:WaitForChild("PurchaseResult")

-- ===== State =====
local lastInventory = {}  -- [{id,name,count,inventoryName,toolName}, ...]
local dragging = false
local dragGhost: Frame? = nil
-- payload: { kind="inventory"|"hotbar", id=itemId, qty:number, fromSlotIndex:number? }
local dragPayload: any = nil

-- ===== Mapping dinamis (diisi saat INV_STATE datang) =====
local TOOLNAME_TO_ID: {[string]: string} = {}
local ID_TO_TOOLNAME: {[string]: string} = {}

local function rebuildMappingsFromInventory(arr)
	-- kosongkan dulu
	table.clear(TOOLNAME_TO_ID)
	table.clear(ID_TO_TOOLNAME)

	for _, it in ipairs(arr or {}) do
		-- Preferensi toolName dari server; fallback ke inventoryName jika kosong
		local toolName = it.toolName or it.inventoryName
		if typeof(toolName) == "string" and toolName ~= "" then
			TOOLNAME_TO_ID[toolName] = it.id
			ID_TO_TOOLNAME[it.id] = toolName
		end
	end
end

-- ===== Helpers =====
local function getMousePosNoInset(): Vector2
	local m = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	return Vector2.new(m.X - inset.X, m.Y - inset.Y)
end

local function pointInGui(px: number, py: number, guiObj: Instance?): boolean
	if not guiObj or not guiObj:IsA("GuiObject") then return false end
	local absPos = guiObj.AbsolutePosition
	local absSize = guiObj.AbsoluteSize
	return px >= absPos.X and px <= absPos.X + absSize.X
		and py >= absPos.Y and py <= absPos.Y + absSize.Y
end

-- ===== Hotbar UI =====
local function ensureHotbar(): Frame
	if hotbar and hotbar:IsA("Frame") then return hotbar end

	local bar = Instance.new("Frame")
	bar.Name = "BackpackBar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -10)
	bar.Size = UDim2.new(0.6, 0, 0, 70)
	bar.BackgroundTransparency = 1
	bar.Parent = inventoryGui

	local uiList = Instance.new("UIListLayout")
	uiList.FillDirection = Enum.FillDirection.Horizontal
	uiList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	uiList.SortOrder = Enum.SortOrder.LayoutOrder
	uiList.Padding = UDim.new(0, 6)
	uiList.Parent = bar

	for i = 1, 10 do
		local visualIndex = (i == 10) and 0 or i
		local slot = Instance.new("Frame")
		slot.Name = ("Slot_%d"):format(visualIndex)
		slot.Size = UDim2.new(0, 56, 0, 56)
		slot.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
		slot.BackgroundTransparency = 0.2
		slot.Active = true
		slot.Parent = bar

		local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 10); corner.Parent = slot
		local stroke = Instance.new("UIStroke"); stroke.Thickness = 1; stroke.Color = Color3.fromRGB(80,80,80); stroke.Parent = slot

		local key = Instance.new("TextLabel")
		key.Name = "Key"
		key.Size = UDim2.new(1, -6, 0, 16)
		key.Position = UDim2.new(0, 3, 0, 3)
		key.BackgroundTransparency = 1
		key.Font = Enum.Font.GothamBold
		key.TextSize = 12
		key.TextXAlignment = Enum.TextXAlignment.Left
		key.TextColor3 = Color3.fromRGB(200, 200, 200)
		key.Text = (i == 10) and "0" or tostring(i)
		key.Parent = slot

		local icon = Instance.new("TextLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(1, 0, 1, -16)
		icon.Position = UDim2.new(0, 0, 0, 16)
		icon.BackgroundTransparency = 1
		icon.Font = Enum.Font.Gotham
		icon.TextScaled = true
		icon.TextColor3 = Color3.new(1,1,1)
		icon.Text = ""
		icon.Parent = slot

		local count = Instance.new("TextLabel")
		count.Name = "Count"
		count.AnchorPoint = Vector2.new(1,1)
		count.Position = UDim2.new(1, -4, 1, -4)
		count.Size = UDim2.new(0, 28, 0, 16)
		count.BackgroundTransparency = 0.3
		count.BackgroundColor3 = Color3.fromRGB(0,0,0)
		local cCorner = Instance.new("UICorner"); cCorner.CornerRadius = UDim.new(1,0); cCorner.Parent = count
		count.Font = Enum.Font.GothamBold
		count.TextSize = 12
		count.TextColor3 = Color3.fromRGB(255,255,255)
		count.Text = ""
		count.Parent = slot
	end

	hotbar = bar
	return hotbar
end

local function getToolStack(tool: Tool): number
	local attr = tool:GetAttribute("Stack")
	if typeof(attr) == "number" then return attr end
	local nv = tool:FindFirstChild("Stack")
	if nv and nv:IsA("NumberValue") then return nv.Value end
	return 1
end

local function findFirstToolByName(name: string): Tool?
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

-- Render hotbar **berdasarkan binding**
local function getBindingFolder(): Folder
	local f = inventoryGui:FindFirstChild("HotbarBindings") :: Folder?
	if not f then
		f = Instance.new("Folder")
		f.Name = "HotbarBindings"
		f.Parent = inventoryGui
	end
	return f
end

local function slotKey(slotIndex: number): string
	return ("Slot%d"):format(slotIndex)
end

local function setBinding(slotIndex: number, toolName: string?)
	local folder = getBindingFolder()
	local key = slotKey(slotIndex)
	local sv = folder:FindFirstChild(key)
	if not sv then
		sv = Instance.new("StringValue")
		sv.Name = key
		sv.Parent = folder
	end
	sv.Value = toolName or ""
end

local function getBinding(slotIndex: number): string
	local folder = getBindingFolder()
	local sv = folder:FindFirstChild(slotKey(slotIndex))
	return (sv and sv.Value) or ""
end

local function refreshHotbar()
	local bar = ensureHotbar()

	for i = 1, 10 do
		local visualIndex = (i == 10) and 0 or i
		local slot = bar:FindFirstChild(("Slot_%d"):format(visualIndex))
		if slot and slot:IsA("Frame") then
			local icon = slot:FindFirstChild("Icon") :: TextLabel
			local count = slot:FindFirstChild("Count") :: TextLabel
			local boundName = getBinding(i)

			if boundName ~= "" then
				local tool = findFirstToolByName(boundName)
				icon.Text = boundName
				if tool then
					local stack = getToolStack(tool)
					count.Text = (stack > 1) and ("x"..stack) or ""
				else
					count.Text = ""
				end
			else
				icon.Text = ""
				count.Text = ""
			end
		end
	end
end

-- Utility: dapatkan index slot hotbar yang dilewati kursor
local function slotIndexAtPosition(p: Vector2): number?
	local bar = ensureHotbar()
	for i = 1, 10 do
		local visualIndex = (i == 10) and 0 or i
		local slot = bar:FindFirstChild(("Slot_%d"):format(visualIndex))
		if slot and pointInGui(p.X, p.Y, slot) then
			return i
		end
	end
	return nil
end

-- ===== Drag & Drop =====
local function destroyGhost()
	if dragGhost then dragGhost:Destroy(); dragGhost = nil end
end

local function createGhost(textLabel: string)
	destroyGhost()
	local g = Instance.new("Frame")
	g.Name = "DragGhost"
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Size = UDim2.fromOffset(50, 50)
	g.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	g.BackgroundTransparency = 0.1
	g.BorderSizePixel = 0
	g.ZIndex = 1000
	g.Parent = inventoryGui

	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = g
	local stroke = Instance.new("UIStroke"); stroke.Thickness = 2; stroke.Color = Color3.fromRGB(180,180,180); stroke.Parent = g

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, -6, 1, -6)
	text.Position = UDim2.new(0, 3, 0, 3)
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.fromRGB(255,255,255)
	text.Text = textLabel
	text.Parent = g

	dragGhost = g
end

-- payload: { kind="inventory"|"hotbar", id=itemId, qty:number, fromSlotIndex:number? }
local function beginDrag(fromKind: string, itemId: string, qty: number, labelText: string, fromSlotIndex: number?)
	dragging = true
	dragPayload = { kind = fromKind, id = itemId, qty = math.max(1, qty or 1), fromSlotIndex = fromSlotIndex }
	createGhost(labelText)

	local function follow()
		if not dragging or not dragGhost then return end
		local p = getMousePosNoInset()
		dragGhost.Position = UDim2.fromOffset(p.X, p.Y)
	end

	local mConn = RunService.RenderStepped:Connect(follow)
	local endedConn; endedConn = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if mConn then mConn:Disconnect() end
			if endedConn then endedConn:Disconnect() end

			local p = getMousePosNoInset()
			local targetSlot = slotIndexAtPosition(p)
			local droppedOnInventory = pointInGui(p.X, p.Y, scrolling)

			if dragPayload then
				if dragPayload.kind == "inventory" and targetSlot then
					-- Withdraw ALL -> bind slot ke ToolName item tsb
					REQ_WITHDRAW:FireServer(dragPayload.id, dragPayload.qty)

					-- Optimistic local UI: kurangi lokal & bind slot
					for _, it in ipairs(lastInventory) do
						if it.id == dragPayload.id then
							it.count = math.max(0, (it.count or 0) - dragPayload.qty)
							break
						end
					end
					local toolName = ID_TO_TOOLNAME[dragPayload.id]
					if toolName and toolName ~= "" then
						setBinding(targetSlot, toolName)
					end

					-- repaint UI inventory
					task.defer(function()
						for _, ch in ipairs(scrolling:GetChildren()) do
							if ch:IsA("Frame") then ch:Destroy() end
						end
					end)
					refreshHotbar()

				elseif dragPayload.kind == "hotbar" and droppedOnInventory then
					-- Deposit ALL -> unbind slot asal
					local fromSlot = dragPayload.fromSlotIndex
					REQ_DEPOSIT:FireServer(dragPayload.id, dragPayload.qty)
					if fromSlot then
						setBinding(fromSlot, "")
						refreshHotbar()
					end
				end
			end

			dragging = false
			dragPayload = nil
			destroyGhost()
		end
	end)
end

-- ===== Inventory Tiles (50x50 + nama) =====
local function clearTiles()
	for _, ch in ipairs(scrolling:GetChildren()) do
		if ch:IsA("Frame") then ch:Destroy() end
	end
end

local function buildInventoryTiles()
	clearTiles()

	local grid = scrolling:FindFirstChildOfClass("UIGridLayout")
	if not grid then
		grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.new(0, 60, 0, 70)   -- ruang 50x50 + label
		grid.CellPadding = UDim2.new(0, 6, 0, 6)
		grid.FillDirectionMaxCells = 6
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = scrolling
	end

	for _, it in ipairs(lastInventory) do
		if (it.count or 0) > 0 then
			local cell = Instance.new("Frame")
			cell.Name = "Cell_"..it.id
			cell.Size = UDim2.new(0, 60, 0, 70)
			cell.BackgroundTransparency = 1
			cell.Parent = scrolling

			local square = Instance.new("Frame")
			square.Name = "Tile"
			square.Size = UDim2.new(0, 50, 0, 50)
			square.Position = UDim2.new(0, 5, 0, 0)
			square.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
			square.BackgroundTransparency = 0.1
			square.Active = true
			square.Parent = cell

			local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = square
			local stroke = Instance.new("UIStroke"); stroke.Thickness = 1; stroke.Color = Color3.fromRGB(80,80,80); stroke.Parent = square

			local countBadge = Instance.new("TextLabel")
			countBadge.Name = "Count"
			countBadge.AnchorPoint = Vector2.new(1,1)
			countBadge.Position = UDim2.new(1, -4, 1, -4)
			countBadge.Size = UDim2.new(0, 28, 0, 16)
			countBadge.BackgroundTransparency = 0.3
			countBadge.BackgroundColor3 = Color3.fromRGB(0,0,0)
			local cCorner = Instance.new("UICorner"); cCorner.CornerRadius = UDim.new(1,0); cCorner.Parent = countBadge
			countBadge.Font = Enum.Font.GothamBold
			countBadge.TextSize = 12
			countBadge.TextColor3 = Color3.fromRGB(255,255,255)
			countBadge.Text = "x"..tostring(it.count or 0)
			countBadge.Parent = square

			local name = Instance.new("TextLabel")
			name.Name  = "Name"
			name.Size  = UDim2.new(1, 0, 0, 16)
			name.Position = UDim2.new(0, 0, 0, 52)
			name.BackgroundTransparency = 1
			name.Font = Enum.Font.Gotham
			name.TextSize = 12
			name.TextColor3 = Color3.fromRGB(230,230,230)
			name.TextWrapped = true
			name.Text = tostring(it.name or it.id)
			name.Parent = cell

			-- Drag start: Inventory -> Hotbar SLOT (ALL qty)
			square.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					local qty = tonumber(it.count) or 0
					if qty > 0 then
						beginDrag("inventory", it.id, qty, name.Text, nil)
					end
				end
			end)
		end
	end
end

-- ===== Drag start dari Hotbar SLOT (Hotbar -> Inventory) =====
local function hookHotbarDrag()
	local bar = ensureHotbar()
	for i = 1, 10 do
		local visualIndex = (i == 10) and 0 or i
		local slot = bar:FindFirstChild(("Slot_%d"):format(visualIndex))
		if slot and slot:IsA("Frame") then
			slot.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					local boundName = getBinding(i)
					if boundName ~= "" then
						local itemId = TOOLNAME_TO_ID[boundName]
						if itemId then
							-- Cari stack aktual di Tool untuk qty
							local tool = findFirstToolByName(boundName)
							local qty = tool and getToolStack(tool) or 1
							beginDrag("hotbar", itemId, qty, boundName, i)
						end
					end
				end
			end)
		end
	end
end

-- ===== Wiring UI =====
btnInventoryMenu.MouseButton1Click:Connect(function()
	inventoryFrame.Visible = true
end)

if btnInvExit then
	btnInvExit.MouseButton1Click:Connect(function()
		inventoryFrame.Visible = false
	end)
end

-- ===== Remote listeners =====
INV_STATE.OnClientEvent:Connect(function(arr)
	lastInventory = arr or {}

	-- Bangun mapping otomatis dari server
	rebuildMappingsFromInventory(lastInventory)

	-- refresh UI
	buildInventoryTiles()
	refreshHotbar()
end)

RES_PURCHASE.OnClientEvent:Connect(function()
	refreshHotbar()
end)

-- ===== Hook perubahan Backpack/Character -> refresh hitungan stack =====
local function hookBackpack(bp: Backpack)
	bp.ChildAdded:Connect(refreshHotbar)
	bp.ChildRemoved:Connect(refreshHotbar)
	for _, ch in ipairs(bp:GetChildren()) do
		if ch:IsA("Tool") then
			ch.AttributeChanged:Connect(function(attr)
				if attr == "Stack" then refreshHotbar() end
			end)
		end
	end
end

local function hookCharacter(char: Model)
	char.ChildAdded:Connect(function(ch)
		if ch:IsA("Tool") then
			refreshHotbar()
			ch.AttributeChanged:Connect(function(attr)
				if attr == "Stack" then refreshHotbar() end
			end)
		end
	end)
	char.ChildRemoved:Connect(function(ch)
		if ch:IsA("Tool") then refreshHotbar() end
	end)
end

-- Initial hooks
local bpInit = player:FindFirstChildOfClass("Backpack")
if bpInit then hookBackpack(bpInit) end
player.ChildAdded:Connect(function(ch)
	if ch:IsA("Backpack") then hookBackpack(ch); refreshHotbar() end
end)

if player.Character then hookCharacter(player.Character) end
player.CharacterAdded:Connect(function(char)
	hookCharacter(char)
	task.defer(refreshHotbar)
end)

-- First paint
task.defer(function()
	refreshHotbar()
	buildInventoryTiles()
	hookHotbarDrag()
end)
