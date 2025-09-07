local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remoteEvents = ReplicatedStorage:WaitForChild("FishingRemotes")
local startFishingRemote = remoteEvents:WaitForChild("StartFishing")
local stopFishingRemote = remoteEvents:WaitForChild("StopFishing")
local catchFishRemote = remoteEvents:WaitForChild("CatchFish")

-- Track players yang sedang memancing
local fishingPlayers = {}

-- Jenis ikan dengan rarity berbeda
local fishTypes = {
	{name = "Ikan Kecil", rarity = 60, value = 10},
	{name = "Ikan Sedang", rarity = 25, value = 25},
	{name = "Ikan Besar", rarity = 10, value = 50},
	{name = "Ikan Langka", rarity = 4, value = 100},
	{name = "Ikan Legendaris", rarity = 1, value = 500}
}

function getFishType()
	local totalRarity = 0
	for _, fish in pairs(fishTypes) do
		totalRarity = totalRarity + fish.rarity
	end

	local randomNum = math.random(1, totalRarity)
	local currentRarity = 0

	for _, fish in pairs(fishTypes) do
		currentRarity = currentRarity + fish.rarity
		if randomNum <= currentRarity then
			return fish
		end
	end

	return fishTypes[1] -- Fallback
end

startFishingRemote.OnServerEvent:Connect(function(player)
	fishingPlayers[player] = true
	print(player.Name .. " started fishing")
end)

stopFishingRemote.OnServerEvent:Connect(function(player)
	fishingPlayers[player] = nil
	print(player.Name .. " stopped fishing")
end)

catchFishRemote.OnServerEvent:Connect(function(player)
	if not fishingPlayers[player] then return end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local fishStat = leaderstats:FindFirstChild("Fish")
	local coinsStat = leaderstats:FindFirstChild("Coins")

	if fishStat and coinsStat then
		local caughtFish = getFishType()

		fishStat.Value = fishStat.Value + 1
		coinsStat.Value = coinsStat.Value + caughtFish.value

		print(player.Name .. " caught a " .. caughtFish.name .. "! (+" .. caughtFish.value .. " coins)")

		-- Kirim pesan ke player
		local message = "Tertangkap: " .. caughtFish.name .. " (+" .. caughtFish.value .. " coins)"
		player:SendNotification("Fishing Success", message, "rbxasset://textures/ui/TopBar/inventoryIcon.png")
	end

	fishingPlayers[player] = nil
end)

-- Cleanup saat player leave
Players.PlayerRemoving:Connect(function(player)
	fishingPlayers[player] = nil
end)