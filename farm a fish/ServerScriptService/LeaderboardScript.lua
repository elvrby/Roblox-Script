local Players = game:GetService("Players")

function onPlayerAdded(player)
	-- Buat leaderstats
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	-- Buat stats
	local fish = Instance.new("IntValue")
	fish.Name = "Fish"
	fish.Value = 0
	fish.Parent = leaderstats

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = 100 -- Starting coins
	coins.Parent = leaderstats

	print(player.Name .. " joined the game!")
end

Players.PlayerAdded:Connect(onPlayerAdded)