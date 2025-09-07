-- ServerScriptService/BootShopRemotes.server.lua
local RS = game:GetService("ReplicatedStorage")
local folder = RS:FindFirstChild("ShopRemotes") or Instance.new("Folder")
folder.Name = "ShopRemotes"
folder.Parent = RS

local function ensureEvent(name: string)
	local ev = folder:FindFirstChild(name)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = folder
	end
	return ev
end

ensureEvent("RequestOpen")
ensureEvent("InventoryUpdate")
ensureEvent("PurchaseRequest")
ensureEvent("PurchaseResult")
ensureEvent("WithdrawRequest") -- Inventory -> Backpack (Tool)
ensureEvent("DepositRequest")  -- Backpack (Tool) -> Inventory
ensureEvent("InventoryState")  -- <<< snapshot inventory pemain ke client
