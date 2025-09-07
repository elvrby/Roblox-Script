-- StarterPlayerScripts/MerchantDialog.client.lua

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")

-- UI buatanmu
local dialogGui   = gui:WaitForChild("MerchantShop")
local dialogFrame = dialogGui:WaitForChild("DialogFrame")
local btnShop     = dialogFrame:WaitForChild("BtnShop")
-- BtnExit sifatnya opsional: jangan block kalau belum ada
local btnExit     = dialogFrame:FindFirstChild("BtnExit")

-- Referensi SHOP (Container utama yang mau ditampilkan)
local shopRoot = dialogGui:WaitForChild("Shop")  -- PASTIKAN "Shop" adalah Frame/GuiObject (bukan Folder)
-- (opsional) tombol exit di Shop
local btnExitShop = shopRoot:FindFirstChild("exit")

-- Remotes
local remotes  = ReplicatedStorage:WaitForChild("ShopRemotes")
local REQ_OPEN = remotes:WaitForChild("RequestOpen")

-- Helpers
local function openDialog()
	dialogFrame.Visible = true
	ProximityPromptService.Enabled = false
end
local function closeDialog()
	dialogFrame.Visible = false
	-- Jangan langsung true kalau habis buka Shop; biarkan Shop yang mengatur
end
local function openShop()
	-- Pastikan node Shop memang GuiObject (bukan Folder), kalau Folder tidak punya property Visible.
	if shopRoot:IsA("GuiObject") or shopRoot:IsA("LayerCollector") then
		shopRoot.Visible = true
	else
		warn("Node 'Shop' bukan GuiObject. Ganti 'Shop' jadi Frame agar bisa Visible = true.")
	end
	ProximityPromptService.Enabled = false
	-- minta stok terbaru
	REQ_OPEN:FireServer()
end
local function closeShop()
	if shopRoot:IsA("GuiObject") or shopRoot:IsA("LayerCollector") then
		shopRoot.Visible = false
	end
	ProximityPromptService.Enabled = true
end

-- Prompt → buka dialog
local function connectPrompt(prompt)
	if not prompt:IsA("ProximityPrompt") then return end
	if (prompt.ObjectText == "Merchant") or (prompt.Name == "MerchantPrompt") then
		prompt.Triggered:Connect(openDialog)
	end
end
for _, d in ipairs(Workspace:GetDescendants()) do
	if d:IsA("ProximityPrompt") then connectPrompt(d) end
end
Workspace.DescendantAdded:Connect(function(d)
	if d:IsA("ProximityPrompt") then connectPrompt(d) end
end)

-- Aksi tombol dialog
btnShop.MouseButton1Click:Connect(function()
	-- 1) Tutup dialog
	closeDialog()
	-- 2) Tampilkan Shop + minta stok
	openShop()
end)

if btnExit then
	btnExit.MouseButton1Click:Connect(function()
		dialogFrame.Visible = false
		ProximityPromptService.Enabled = true
	end)
end

-- Exit dari Shop (kalau ada)
if btnExitShop then
	btnExitShop.MouseButton1Click:Connect(function()
		closeShop()
	end)
end

-- ESC untuk menutup yang terbuka
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.Escape then
		if shopRoot:IsA("GuiObject") and shopRoot.Visible then
			closeShop()
		elseif dialogFrame.Visible then
			dialogFrame.Visible = false
			ProximityPromptService.Enabled = true
		end
	end
end)

-- Pastikan tertutup saat respawn
player.CharacterAdded:Connect(function()
	if shopRoot:IsA("GuiObject") then shopRoot.Visible = false end
	dialogFrame.Visible = false
	ProximityPromptService.Enabled = true
end)
