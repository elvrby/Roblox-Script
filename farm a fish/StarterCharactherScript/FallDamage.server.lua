-- Server: Falling Damage berbasis tinggi jatuh (studs)
-- R15: gunakan HumanoidRootPart untuk posisi
-- Damage = max(0, (drop - SAFE_HEIGHT) * DAMAGE_PER_STUD)

local SAFE_HEIGHT = 12          -- tinggi aman tanpa damage
local DAMAGE_PER_STUD = 3       -- damage tiap stud melewati ambang
local MIN_APPLY = 1             -- antispam damage sangat kecil

local character = script.Parent
local humanoid: Humanoid = character:WaitForChild("Humanoid")
local hrp: BasePart = character:WaitForChild("HumanoidRootPart")

local fallStartY: number? = nil
local inFreefall = false

humanoid.StateChanged:Connect(function(_, new)
	if new == Enum.HumanoidStateType.Freefall then
		inFreefall = true
		fallStartY = hrp.Position.Y
	elseif inFreefall and (new == Enum.HumanoidStateType.Landed
		or new == Enum.HumanoidStateType.Running
		or new == Enum.HumanoidStateType.Seated) then

		inFreefall = false
		if fallStartY then
			local drop = fallStartY - hrp.Position.Y
			if drop > SAFE_HEIGHT then
				local damage = math.max(0, (drop - SAFE_HEIGHT) * DAMAGE_PER_STUD)
				if damage >= MIN_APPLY then
					humanoid:TakeDamage(damage)
				end
			end
		end
		fallStartY = nil
	end
end)
