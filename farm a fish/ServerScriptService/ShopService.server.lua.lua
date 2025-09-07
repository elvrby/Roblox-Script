-- ServerScriptService/ShopService.server.lua
-- Restock sinkron, purchase ? Inventory counter, Withdraw/Deposit ? Tool stack.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local StarterPack       = game:GetService("StarterPack")

local Remotes        = ReplicatedStorage:WaitForChild("ShopRemotes")
local REQ_OPEN       = Remotes:WaitForChild("RequestOpen")
local INV_UPDATE     = Remotes:WaitForChild("InventoryUpdate")
local REQ_PURCHASE   = Remotes:WaitForChild("PurchaseRequest")
local RES_PURCHASE   = Remotes:WaitForChild("PurchaseResult")
local REQ_WITHDRAW   = Remotes:WaitForChild("WithdrawRequest")
local REQ_DEPOSIT    = Remotes:WaitForChild("DepositRequest")
local INV_STATE      = Remotes:WaitForChild("InventoryState")

-- ================== RESTOCK ==================
local RESTOCK_PERIOD = 60 -- detik
local nextRestockAt  = Workspace:GetServerTimeNow() + RESTOCK_PERIOD

-- ================== TEMPLATE TOOLS ==================
local ItemTemplates = ReplicatedStorage:FindFirstChild("ItemTemplates") or Instance.new("Folder", ReplicatedStorage)
ItemTemplates.Name = "ItemTemplates"

local function ensureToolTemplate(toolName: string, builderIfMissing: (() -> Tool)?)
	-- 1) Sudah ada di ItemTemplates?
	local t = ItemTemplates:FindFirstChild(toolName)
	if t and t:IsA("Tool") then return t end
	-- 2) Ada di StarterPack? Pindahkan (biar tidak auto-diberi saat respawn)
	local sp = StarterPack:FindFirstChild(toolName)
	if sp and sp:IsA("Tool") then
		sp.Parent = ItemTemplates
		return sp
	end
	-- 3) Tidak ada ? bangun minimal jika ada builder
	if builderIfMissing then
		local newTool = builderIfMissing()
		newTool.Name = toolName
		newTool.Parent = ItemTemplates
		return newTool
	end
	error(("Template Tool '%s' tidak ditemukan. Taruh di ReplicatedStorage/ItemTemplates."):format(toolName))
end

local function buildFishFood()
	local tool = Instance.new("Tool")
	tool.CanBeDropped = true
	tool.RequiresHandle = true
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.6, 0.6, 0.6)
	handle.Color = Color3.fromRGB(255, 216, 93)
	handle.Material = Enum.Material.Plastic
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool
	local nv = Instance.new("NumberValue"); nv.Name = "Stack"; nv.Value = 0; nv.Parent = tool
	return tool
end

local FishFoodTemplate   = ensureToolTemplate("FishFood", buildFishFood)
local FishingRodTemplate = ensureToolTemplate("FishingRod") -- kamu sudah punya modelnya

-- ================== DATA SHOP ==================
local ITEMS = {
	{
		id = "fish_food",
		name = "Fish Food",
		price = 10,
		stock = 0, stockMin = 1, stockMax = 10,
		inventoryName = "FishFood",
		templateToolName = "FishFood",
	},
	{
		id = "fishing_rod",
		name = "Fishing Rod",
		price = 10,
		stock = 0, stockMin = 1, stockMax = 3,
		inventoryName = "FishingRod",
		templateToolName = "FishingRod",
	},
	{
		id = "nasi",
		name = "Nasi",
		price = 2,
		stock = 0, stockMin = 2, stockMax = 8,
		inventoryName = "Nasi",
		templateToolName = "Nasi",
	},

	
}

local ITEM_INDEX = {}
for i, it in ipairs(ITEMS) do ITEM_INDEX[it.id] = i end

-- ================== HELPERS ==================
local function randomizeStock(item) item.stock = math.random(item.stockMin, item.stockMax) end
for _, it in ipairs(ITEMS) do randomizeStock(it) end

local function getCoinsValue(player: Player): IntValue
	local ls = player:FindFirstChild("leaderstats")
	if not ls then ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = player end
	local coins = ls:FindFirstChild("Coins")
	if not coins then coins = Instance.new("IntValue"); coins.Name = "Coins"; coins.Value = 100; coins.Parent = ls end
	return coins
end

local function getInventoryEntry(player: Player, invName: string): IntValue
	local inv = player:FindFirstChild("Inventory")
	if not inv then inv = Instance.new("Folder"); inv.Name = "Inventory"; inv.Parent = player end
	local entry = inv:FindFirstChild(invName)
	if not entry then entry = Instance.new("IntValue"); entry.Name = invName; entry.Value = 0; entry.Parent = inv end
	return entry
end

local function buildInventoryPayload()
	local payload = {}
	for _, it in ipairs(ITEMS) do
		table.insert(payload, { id = it.id, name = it.name, price = it.price, stock = it.stock })
	end
	return payload
end

local function sendInventoryTo(player: Player)
	INV_UPDATE:FireClient(player, buildInventoryPayload(), nextRestockAt)
end

local function sendInventoryToAll()
	local payload = buildInventoryPayload()
	for _, plr in ipairs(Players:GetPlayers()) do
		INV_UPDATE:FireClient(plr, payload, nextRestockAt)
	end
end

local function buildPlayerInventory(player: Player)
	local arr = {}
	for _, it in ipairs(ITEMS) do
		local entry = getInventoryEntry(player, it.inventoryName)
		table.insert(arr, {
			id = it.id,
			name = it.name,
			count = entry.Value,
			inventoryName = it.inventoryName,
			toolName = it.templateToolName, -- <<=== KIRIM ke client
		})
	end
	return arr
end


local function sendInventoryStateTo(player: Player)
	INV_STATE:FireClient(player, buildPlayerInventory(player))
end

-- Tool stack helpers
local function findExistingTool(player: Player, templateName: string): Tool?
	local char = player.Character
	if char then
		for _, ch in ipairs(char:GetChildren()) do
			if ch:IsA("Tool") and ch.Name == templateName then
				return ch
			end
		end
	end
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp then
		for _, ch in ipairs(bp:GetChildren()) do
			if ch:IsA("Tool") and ch.Name == templateName then
				return ch
			end
		end
	end
	return nil
end

local function getToolStack(tool: Tool): number
	local attr = tool:GetAttribute("Stack")
	if typeof(attr) == "number" then return attr end
	local nv = tool:FindFirstChild("Stack")
	if nv and nv:IsA("NumberValue") then return nv.Value end
	return 1
end

local function setToolStack(tool: Tool, newStack: number)
	tool:SetAttribute("Stack", newStack)
	local nv = tool:FindFirstChild("Stack")
	if nv and nv:IsA("NumberValue") then nv.Value = newStack end
	tool.ToolTip = string.format("%s (x%d)", tool.Name, newStack)
end

local function giveToolStack(player: Player, template: Tool, amount: number, stackable: boolean?)
	local bp = player:FindFirstChildOfClass("Backpack")
	if not bp then return false, "Backpack tidak ditemukan." end

	if stackable == false then
		-- buat satu per satu tool terpisah
		for i = 1, amount do
			local t = template:Clone()
			setToolStack(t, 1)
			t.Parent = bp
		end
		return true
	end

	local existing = findExistingTool(player, template.Name)
	if existing then
		local cur = getToolStack(existing)
		setToolStack(existing, cur + amount)
		return true
	else
		local tool = template:Clone()
		setToolStack(tool, amount)
		tool.Parent = bp
		return true
	end
end

local function takeToolStack(player: Player, templateName: string, amount: number): number
	local remaining = amount
	while remaining > 0 do
		local tool = findExistingTool(player, templateName)
		if not tool then break end
		local cur = getToolStack(tool)
		local take = math.min(cur, remaining)
		local newStack = cur - take
		if newStack <= 0 then
			tool:Destroy()
		else
			setToolStack(tool, newStack)
		end
		remaining -= take
	end
	return amount - remaining
end

local function findItemById(id: string)
	local idx = ITEM_INDEX[id]
	return idx and ITEMS[idx] or nil
end

-- ================== EVENTS ==================
REQ_OPEN.OnServerEvent:Connect(function(player)
	sendInventoryTo(player)
	sendInventoryStateTo(player)
end)

REQ_PURCHASE.OnServerEvent:Connect(function(player, itemId, quantity)
	quantity = tonumber(quantity) or 1
	if quantity < 1 then quantity = 1 end

	local item = findItemById(itemId)
	if not item then RES_PURCHASE:FireClient(player, false, "Item tidak ditemukan."); return end
	if item.stock <= 0 or item.stock < quantity then
		RES_PURCHASE:FireClient(player, false, "Stok tidak mencukupi.")
		sendInventoryTo(player)
		return
	end

	local coins = getCoinsValue(player)
	local total = item.price * quantity
	if coins.Value < total then
		RES_PURCHASE:FireClient(player, false, "Coins kamu tidak cukup.")
		return
	end

	-- Commit
	coins.Value -= total
	item.stock -= quantity

	-- Tambah ke Inventory counter
	local entry = getInventoryEntry(player, item.inventoryName)
	entry.Value += quantity

	RES_PURCHASE:FireClient(player, true, ("Membeli %d %s (-%d Coins). Masuk ke Inventory."):format(quantity, item.name, total))
	sendInventoryToAll()
	sendInventoryStateTo(player)
end)

REQ_WITHDRAW.OnServerEvent:Connect(function(player, itemId, quantity)
	quantity = tonumber(quantity) or 1
	if quantity < 1 then quantity = 1 end

	local item = findItemById(itemId)
	if not item then RES_PURCHASE:FireClient(player, false, "Item tidak ditemukan."); return end

	local entry = getInventoryEntry(player, item.inventoryName)
	if entry.Value < quantity then
		RES_PURCHASE:FireClient(player, false, "Jumlah di Inventory tidak cukup.")
		return
	end

	local template = ItemTemplates:FindFirstChild(item.templateToolName)
	if not (template and template:IsA("Tool")) then
		RES_PURCHASE:FireClient(player, false, "Template Tool tidak ditemukan.")
		return
	end

	-- Kurangi counter terlebih dahulu
	entry.Value -= quantity

	local ok, err = giveToolStack(player, template, quantity, item.stackable) -- item.stackable optional
	if not ok then
		entry.Value += quantity -- rollback
		RES_PURCHASE:FireClient(player, false, err or "Gagal ambil ke Backpack.")
		return
	end

	RES_PURCHASE:FireClient(player, true, ("Ambil %d %s ke Backpack."):format(quantity, item.name))
	sendInventoryStateTo(player)
end)

REQ_DEPOSIT.OnServerEvent:Connect(function(player, itemId, quantity)
	quantity = tonumber(quantity) or 1
	if quantity < 1 then quantity = 1 end

	local item = findItemById(itemId)
	if not item then RES_PURCHASE:FireClient(player, false, "Item tidak ditemukan."); return end

	local removed = takeToolStack(player, item.templateToolName, quantity)
	if removed <= 0 then
		RES_PURCHASE:FireClient(player, false, "Tidak ada Tool yang cocok di tangan/Backpack.")
		return
	end

	local entry = getInventoryEntry(player, item.inventoryName)
	entry.Value += removed

	RES_PURCHASE:FireClient(player, true, ("Simpan %d %s ke Inventory."):format(removed, item.name))
	sendInventoryStateTo(player)
end)

-- ================== RESTOCK LOOP ==================
task.spawn(function()
	while true do
		task.wait(0.25)
		if Workspace:GetServerTimeNow() >= nextRestockAt then
			for _, it in ipairs(ITEMS) do randomizeStock(it) end
			nextRestockAt += RESTOCK_PERIOD
			sendInventoryToAll()
		end
	end
end)

-- Saat join
Players.PlayerAdded:Connect(function(plr)
	task.defer(function()
		sendInventoryTo(plr)
		sendInventoryStateTo(plr)
	end)
end)
