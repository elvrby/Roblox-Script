-- StarterPlayerScripts/MerchantShopClient.client.lua
-- Versi simple: cukup duplikasi frame item & rename (PascalCase), script akan:
-- 1) Konversi Nama Frame -> id (snake_case) otomatis
-- 2) Render nama/harga/stock dari server
-- 3) Tombol BUY per item (beli 1)

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local gui    = player:WaitForChild("PlayerGui")

-- ====== GUI tree sesuai punyamu ======
local GUI_NAME   = "MerchantShop"
local dialogGui  = gui:WaitForChild(GUI_NAME)

local shopRoot   = dialogGui:WaitForChild("Shop")
local shopImage  = shopRoot:WaitForChild("Shop Image")
local scroller   = shopImage:WaitForChild("ScrollingFrame")

local btnExitShop = shopRoot:FindFirstChild("exit") :: TextButton?
local lblRestock  = shopRoot:FindFirstChild("restock") :: TextLabel?

-- (opsional) kalau masih ada DialogFrame/BtnShop
local dialogFrame = dialogGui:FindFirstChild("DialogFrame")
local btnShop     = dialogFrame and dialogFrame:FindFirstChild("BtnShop")

-- ===== Remotes =====
local Remotes      = ReplicatedStorage:WaitForChild("ShopRemotes")
local REQ_OPEN     = Remotes:WaitForChild("RequestOpen")
local INV_UPDATE   = Remotes:WaitForChild("InventoryUpdate")
local REQ_PURCHASE = Remotes:WaitForChild("PurchaseRequest")
local RES_PURCHASE = Remotes:WaitForChild("PurchaseResult")

-- ===== State =====
local serverNextRestockAt = 0
local heartbeatConn: RBXScriptConnection? = nil
local latestById: {[string]: any} = {} -- map id -> item data

-- ===== Helpers =====

-- Konversi "FishingRod" / "Fish Food" / "fishFood" → "fishing_rod", "fish_food"
local function toSnakeIdFromFrameName(frameName: string): string
	-- ganti spasi/dash jadi underscore
	local s = frameName:gsub("[%s%-]+", "_")
	-- sisipkan underscore sebelum huruf besar yang bukan di awal, contoh: FishingRod -> Fishing_Rod
	s = s:gsub("(%l)(%u)", "%1_%2")
	-- turunkan semua
	s = s:lower()
	return s
end

local function setPromptsVisible(on: boolean)
	ProximityPromptService.Enabled = on
end

local function openShop()
	if not (shopRoot:IsA("GuiObject") or shopRoot:IsA("LayerCollector")) then
		warn("Node 'Shop' harus GuiObject (Frame/ImageLabel/ScreenGui), bukan Folder.")
		return
	end
	shopRoot.Visible = true
	setPromptsVisible(false)
	REQ_OPEN:FireServer()

	if heartbeatConn then heartbeatConn:Disconnect() end
	heartbeatConn = RunService.Heartbeat:Connect(function()
		if not lblRestock then return end
		if serverNextRestockAt <= 0 then
			lblRestock.Text = "Restock: --"
			return
		end
		local remain = math.max(0, math.floor(serverNextRestockAt - Workspace:GetServerTimeNow()))
		lblRestock.Text = string.format("Restock dalam: %ds", remain)
	end)
end

local function closeShop()
	if shopRoot:IsA("GuiObject") or shopRoot:IsA("LayerCollector") then
		shopRoot.Visible = false
	end
	if heartbeatConn then heartbeatConn:Disconnect(); heartbeatConn = nil end
	setPromptsVisible(true)
end

-- ===== Wiring tombol/ESC =====
if btnShop then
	btnShop.MouseButton1Click:Connect(function()
		if dialogFrame then dialogFrame.Visible = false end
		openShop()
	end)
end

if btnExitShop then
	btnExitShop.MouseButton1Click:Connect(function()
		closeShop()
	end)
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.Escape then
		if shopRoot:IsA("GuiObject") and shopRoot.Visible then
			closeShop()
		elseif dialogFrame and dialogFrame.Visible then
			dialogFrame.Visible = false
			setPromptsVisible(true)
		end
	end
end)

-- ===== Item frame part refs =====
-- Struktur di setiap frame item (hasil duplicate "Pellets"):
--   BuyShop (TextButton), Harga (TextLabel), stock (TextLabel), item (TextLabel? opsional)
local function getPartRefs(itemFrame: Frame)
	local buyBtn = itemFrame:FindFirstChild("BuyShop")
	local harga  = itemFrame:FindFirstChild("Harga")
	local stock  = itemFrame:FindFirstChild("stock")
	local nameLb = itemFrame:FindFirstChild("item")

	-- fallback defensif kalau namanya beda (tapi disarankan pakai nama di atas)
	if not buyBtn then buyBtn = itemFrame:FindFirstChildWhichIsA("TextButton", true) end
	if not harga  then harga  = itemFrame:FindFirstChild("Price") or itemFrame:FindFirstChildWhichIsA("TextLabel", true) end
	if not stock  then stock  = itemFrame:FindFirstChild("Stock") end

	return buyBtn, harga, stock, nameLb
end

-- Simpan koneksi per frame agar tidak double-bind
local clickConn: {[Instance]: RBXScriptConnection} = {}

local function renderItemFrame(itemFrame: Frame, data)
	local buyBtn, harga, stock, nameLb = getPartRefs(itemFrame)

	-- label
	if nameLb and nameLb:IsA("TextLabel") then
		nameLb.Text = data.name or (data.id or itemFrame.Name)
	end
	if harga and harga:IsA("TextLabel") then
		harga.Text = data.price and ("$"..tostring(data.price)) or "-"
	end
	if stock and stock:IsA("TextLabel") then
		stock.Text = tostring(data.stock or 0)
	end

	-- enable/disable BUY
	local canBuy = (data.stock or 0) > 0
	if buyBtn and buyBtn:IsA("TextButton") then
		buyBtn.Active = canBuy
		buyBtn.AutoButtonColor = canBuy
		buyBtn.BackgroundColor3 = canBuy and Color3.fromRGB(40,120,40) or Color3.fromRGB(80,80,80)

		-- bersihkan binding lama
		if clickConn[itemFrame] then
			clickConn[itemFrame]:Disconnect()
			clickConn[itemFrame] = nil
		end
		-- bind baru
		clickConn[itemFrame] = buyBtn.MouseButton1Click:Connect(function()
			REQ_PURCHASE:FireServer(data.id, 1)
		end)
	end
end

local function renderAll()
	-- Loop semua frame anak langsung ScrollingFrame (hasil duplicate Pellets)
	for _, ch in ipairs(scroller:GetChildren()) do
		if ch:IsA("Frame") then
			local id = toSnakeIdFromFrameName(ch.Name)
			local data = latestById[id]
			if data then
				renderItemFrame(ch, data)
				ch.Visible = true
			else
				-- Jika item ini belum ada di server (belum ditambahkan di ITEMS), sembunyikan
				ch.Visible = false
			end
		end
	end
end

-- ===== Remote handlers =====
INV_UPDATE.OnClientEvent:Connect(function(items, nextRestockAt)
	serverNextRestockAt = typeof(nextRestockAt) == "number" and nextRestockAt or 0

	latestById = {}
	for _, it in ipairs(items or {}) do
		latestById[it.id] = it
	end

	renderAll()
end)

RES_PURCHASE.OnClientEvent:Connect(function(ok, msg)
	if lblRestock and msg and msg ~= "" then
		lblRestock.Text = msg
		task.delay(1.2, function()
			if serverNextRestockAt > 0 then
				local remain = math.max(0, math.floor(serverNextRestockAt - Workspace:GetServerTimeNow()))
				lblRestock.Text = string.format("Restock dalam: %ds", remain)
			else
				lblRestock.Text = "Restock: --"
			end
		end)
	end
end)

-- ===== Reset saat respawn =====
player.CharacterAdded:Connect(function()
	if heartbeatConn then heartbeatConn:Disconnect(); heartbeatConn = nil end
	if dialogFrame then dialogFrame.Visible = false end
	if shopRoot:IsA("GuiObject") then shopRoot.Visible = false end
	setPromptsVisible(true)
end)
