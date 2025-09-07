-- StarterPlayerScripts/CarryClient.local.lua
local Players = game:GetService("Players")
local PPS = game:GetService("ProximityPromptService")
local CAS = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarryControl = ReplicatedStorage:WaitForChild("CarryControl")
local LP = Players.LocalPlayer

local function getHRP(model) return model and model:FindFirstChild("HumanoidRootPart") end
local function getHum(model) return model and model:FindFirstChildOfClass("Humanoid") end

-- Sembunyikan prompt "Gendong" milik diri sendiri
local function hideSelfPrompts()
	if not LP.Character then return end
	for _, d in ipairs(LP.Character:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "CarryMePrompt" then
			d.Enabled = false
		end
	end
end

LP.CharacterAdded:Connect(function()
	task.wait(0.2)
	hideSelfPrompts()
end)
task.defer(hideSelfPrompts)

-- Set teks & username setiap prompt ditampilkan
PPS.PromptShown:Connect(function(prompt)
	-- Jangan tampilkan prompt "Gendong" milik diri sendiri
	if prompt.Name == "CarryMePrompt" and LP.Character and prompt:IsDescendantOf(LP.Character) then
		prompt.Enabled = false
		return
	end

	-- Default: set ActionText sesuai jenis
	if prompt.Name == "CarryMePrompt" then
		prompt.ActionText = "Gendong"
		-- ObjectText = nama target (model pemilik prompt)
		local model = prompt:FindFirstAncestorOfClass("Model")
		local hum = getHum(model)
		if hum and hum.DisplayName and hum.DisplayName ~= "" then
			prompt.ObjectText = hum.DisplayName
		elseif model then
			prompt.ObjectText = model.Name
		end
	elseif prompt.Name == "PutDownPrompt" then
		prompt.ActionText = "Turunkan"
		-- ObjectText = nama carried (cari pemain yg punya CarryWeld.Part0 == HRP kita)
		if LP.Character then
			local myHRP = getHRP(LP.Character)
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= LP and plr.Character then
					local hrp = getHRP(plr.Character)
					local weld = hrp and hrp:FindFirstChild("CarryWeld")
					if weld and weld.Part0 == myHRP then
						local hum = getHum(plr.Character)
						if hum and hum.DisplayName and hum.DisplayName ~= "" then
							prompt.ObjectText = hum.DisplayName
						else
							prompt.ObjectText = plr.Name
						end
						break
					end
				end
			end
		end
	elseif prompt.Name == "DropSelfPrompt" then
		prompt.ActionText = "Turun"
		-- ObjectText = nama carrier (cari CarryWeld di HRP-ku)
		if LP.Character then
			local myHRP = getHRP(LP.Character)
			local weld = myHRP and myHRP:FindFirstChild("CarryWeld")
			local carrierHRP = weld and weld.Part0
			local carrierChar = carrierHRP and carrierHRP.Parent
			local hum = getHum(carrierChar)
			if hum and hum.DisplayName and hum.DisplayName ~= "" then
				prompt.ObjectText = hum.DisplayName
			elseif carrierChar then
				prompt.ObjectText = carrierChar.Name
			end
		end
	end
end)

-- Tombol X = kirim Drop & DropSelf (server yang validasi peranmu)
local function dropAction(_, state)
	if state == Enum.UserInputState.Begin then
		CarryControl:FireServer("Drop")      -- jika kita carrier
		CarryControl:FireServer("DropSelf")  -- jika kita carried
	end
end
CAS:BindAction("Carry_DropKey", dropAction, true, Enum.KeyCode.X)

print("[Carry] Tekan E pada prompt untuk Gendong/Turunkan/Turun. Tekan X sebagai shortcut.")
