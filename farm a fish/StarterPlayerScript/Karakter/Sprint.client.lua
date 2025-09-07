-- Client: Sprint tahan Shift, drain stamina, regen saat berhenti
-- R15 compatible

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- Konfigurasi
local WALK_SPEED = 16
local SPRINT_SPEED = 24

local STAMINA_DRAIN_PER_SEC = 20
local STAMINA_REGEN_PER_SEC = 15
local REGEN_DELAY_AFTER_SPRINT = 0.75

local staminaValue: NumberValue = player:WaitForChild("Stamina")
local maxStaminaValue: NumberValue = player:WaitForChild("MaxStamina")

local humanoid: Humanoid
local function hookCharacter(char: Model)
	humanoid = char:WaitForChild("Humanoid")
	humanoid.WalkSpeed = WALK_SPEED
end
hookCharacter(player.Character or player.CharacterAdded:Wait())
player.CharacterAdded:Connect(hookCharacter)

local sprinting = false
local lastSprintStop = 0

local function canSprint()
	return staminaValue.Value > 0 and humanoid.MoveDirection.Magnitude > 0
end

local function startSprint()
	if not sprinting and canSprint() then
		sprinting = true
		humanoid.WalkSpeed = SPRINT_SPEED
	end
end

local function stopSprint()
	if sprinting then
		sprinting = false
		humanoid.WalkSpeed = WALK_SPEED
		lastSprintStop = tick()
	end
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		startSprint()
	end
end)

UserInputService.InputEnded:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		stopSprint()
	end
end)

-- Berhenti sprint kalau tidak bergerak
task.spawn(function()
	while true do
		RunService.RenderStepped:Wait()
		if humanoid and humanoid.MoveDirection.Magnitude <= 0 then
			stopSprint()
		else
			if (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)) and canSprint() then
				startSprint()
			end
		end
	end
end)

-- Loop drain/regen
local last = tick()
RunService.RenderStepped:Connect(function()
	local now = tick()
	local dt = now - last
	last = now

	if sprinting then
		local newS = math.max(0, staminaValue.Value - STAMINA_DRAIN_PER_SEC * dt)
		staminaValue.Value = newS
		if newS <= 0 then
			stopSprint()
		end
	else
		if (now - lastSprintStop) >= REGEN_DELAY_AFTER_SPRINT then
			local maxS = maxStaminaValue.Value
			staminaValue.Value = math.min(maxS, staminaValue.Value + STAMINA_REGEN_PER_SEC * dt)
		end
	end
end)
