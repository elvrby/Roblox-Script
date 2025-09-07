-- ServerScriptService/CarrySystem.server.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- RemoteEvents
local CarryControl = ReplicatedStorage:FindFirstChild("CarryControl") or Instance.new("RemoteEvent")
CarryControl.Name = "CarryControl"
CarryControl.Parent = ReplicatedStorage
-- Client -> Server: minta mulai carry target (kirim Instance Character target)
local CarryRequest = ReplicatedStorage:FindFirstChild("CarryRequest") or Instance.new("RemoteEvent")
CarryRequest.Name = "CarryRequest"
CarryRequest.Parent = ReplicatedStorage

-- ====== State per carrier (Player) ======
-- key: player.UserId -> { carrying = Character }
local State = {}

-- ====== Helpers ======
local function getHRP(char) return char and char:FindFirstChild("HumanoidRootPart") end
local function getHum(char) return char and char:FindFirstChildOfClass("Humanoid") end
local function isAlive(h) return h and h.Health > 0 end
local function ensureState(plr)
	State[plr.UserId] = State[plr.UserId] or {carrying = nil}
	return State[plr.UserId]
end
local function isBeingCarried(char)
	local hrp = getHRP(char)
	return hrp and hrp:FindFirstChild("CarryWeld") ~= nil
end
local function playerFromChar(char)
	return Players:GetPlayerFromCharacter(char)
end

-- ====== Core: STOP carry ======
local function stopCarry(carrierPlr)
	local st = ensureState(carrierPlr)
	local carriedChar = st.carrying
	if not carriedChar then return end

	local carriedHRP, carriedHum = getHRP(carriedChar), getHum(carriedChar)

	-- Lepas weld
	if carriedHRP then
		local weld = carriedHRP:FindFirstChild("CarryWeld")
		if weld then weld:Destroy() end
	end

	-- Pulihkan target
	if carriedHum then
		carriedHum.PlatformStand = false
		local last = carriedChar:GetAttribute("Carry_LastWalkSpeed")
		carriedHum.WalkSpeed = typeof(last)=="number" and last or 16
		carriedChar:SetAttribute("Carry_LastWalkSpeed", nil)
	end

	-- Bersih status
	st.carrying = nil
end

-- Carried minta turun sendiri
local function stopCarryFromCarried(carriedPlr)
	local char = carriedPlr.Character
	if not char then return end
	local myHRP = getHRP(char); if not myHRP then return end
	local weld = myHRP:FindFirstChild("CarryWeld"); if not weld or not weld.Part0 then return end

	local carrierHRP = weld.Part0
	local carrierChar = carrierHRP.Parent
	local carrierPlr = playerFromChar(carrierChar)
	if carrierPlr then
		stopCarry(carrierPlr)
	else
		-- fallback kalau carrier bukan player
		weld:Destroy()
		local hum = getHum(char)
		if hum then hum.PlatformStand = false; hum.WalkSpeed = 16 end
	end
end

-- ====== Core: START carry ======
local function startCarry(carrierPlr, targetChar)
	local carrierChar = carrierPlr.Character
	if not carrierChar then return end
	local carHRP, tarHRP = getHRP(carrierChar), getHRP(targetChar)
	local carHum, tarHum = getHum(carrierChar), getHum(targetChar)
	if not (carHRP and tarHRP and carHum and tarHum) then return end
	if not (isAlive(carHum) and isAlive(tarHum)) then return end

	-- Larangan & validasi
	local st = ensureState(carrierPlr)
	if st.carrying then return end                         -- sudah bawa orang
	if carrierChar == targetChar then return end           -- jangan bawa diri sendiri
	if isBeingCarried(carrierChar) then return end         -- yang sedang digendong tak boleh menggendong
	if tarHRP:FindFirstChild("CarryWeld") then return end  -- target sudah sedang dibawa
	if (carHRP.Position - tarHRP.Position).Magnitude > 8 then return end -- jarak aman

	-- Weld piggyback
	local weld = Instance.new("Weld")
	weld.Name = "CarryWeld"
	weld.Part0 = carHRP
	weld.Part1 = tarHRP
	weld.C0 = CFrame.new(0, 1.2, -0.6)
	weld.C1 = CFrame.Angles(0, math.rad(180), 0)
	weld.Parent = tarHRP

	-- Bekukan target & simpan speed
	local last = tarHum.WalkSpeed
	targetChar:SetAttribute("Carry_LastWalkSpeed", last)
	tarHum.WalkSpeed = 0
	tarHum.PlatformStand = true

	-- Catat status
	st.carrying = targetChar

	-- Safety-net: bila weld hancur (drop/die/desync), pulihkan kontrol
	weld.Destroying:Connect(function()
		task.defer(function()
			if tarHum and tarHum.Parent then
				tarHum.PlatformStand = false
				if targetChar:GetAttribute("Carry_LastWalkSpeed") ~= nil then
					local sp = targetChar:GetAttribute("Carry_LastWalkSpeed")
					tarHum.WalkSpeed = typeof(sp)=="number" and sp or 16
					targetChar:SetAttribute("Carry_LastWalkSpeed", nil)
				end
			end
			-- pastikan status carrier bersih
			local p = playerFromChar(carrierChar)
			if p and State[p.UserId] and State[p.UserId].carrying == targetChar then
				State[p.UserId].carrying = nil
			end
		end)
	end)
end

-- ====== Remote handlers ======
-- Client meminta mulai carry via klik UI
CarryRequest.OnServerEvent:Connect(function(player, targetChar)
	-- Validasi Instance
	if typeof(targetChar) ~= "Instance" then return end
	if not targetChar:IsA("Model") then return end
	-- Target harus punya Humanoid
	if not getHum(targetChar) then return end
	startCarry(player, targetChar)
end)

-- Kontrol umum (drop)
CarryControl.OnServerEvent:Connect(function(player, msg)
	if msg == "Drop" then
		stopCarry(player)
	elseif msg == "DropSelf" then
		stopCarryFromCarried(player)
	end
end)

-- ====== Bersih saat player keluar ======
Players.PlayerRemoving:Connect(function(plr)
	if State[plr.UserId] and State[plr.UserId].carrying then
		stopCarry(plr)
	end
	State[plr.UserId] = nil
end)

-- ====== BONUS: Auto-drop kalau terlalu jauh ======
RunService.Heartbeat:Connect(function()
	for userId, st in pairs(State) do
		if st.carrying then
			local carrierPlr = Players:GetPlayerByUserId(userId)
			if carrierPlr and carrierPlr.Character and st.carrying then
				local a = getHRP(carrierPlr.Character)
				local b = getHRP(st.carrying)
				if a and b and (a.Position - b.Position).Magnitude > 20 then
					stopCarry(carrierPlr)
				end
			end
		end
	end
end)
