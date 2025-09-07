-- Underwater.client.lua (HYBRID++ v3: Raycast voting → Voxel → State)
-- Tujuan: O2 drain hanya saat kepala benar2 di bawah permukaan.
-- Jika kepala di atas permukaan (termasuk mengambang diam), O2 regen meski Humanoid masih Swimming.
-- Aman untuk StreamingEnabled = true. R15 compatible.

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local Workspace   = game:GetService("Workspace")
local player      = Players.LocalPlayer
local terrain     = Workspace.Terrain

-- ================== KONFIG ==================
local OXYGEN_DRAIN_PER_SEC      = 20
local OXYGEN_REGEN_PER_SEC      = 25
local SUFFOCATE_DAMAGE_PER_SEC  = 15
local REGEN_DELAY               = 0.40

-- Bonus “ambil napas” sesaat setelah muncul
local JUST_SURFACED_BONUS       = 35
local JUST_SURFACED_TIME        = 0.60

-- [HEAL REGEN] Parameter kesehatan saat napas kembali
local HEALTH_REGEN_PER_SEC      = 8       -- laju heal normal saat bernapas
local JUST_SURFACED_HEAL_BONUS  = 10      -- bonus heal ekstra sesaat setelah muncul (per detik)
local HEAL_REGEN_DELAY          = 0.40    -- jeda kecil sebelum Health mulai regen (sinkron dengan O2)

-- Raycast probes (sekitar kepala)
local RC_OFFSETS = {
	Vector3.new(0, 0, 0),
	Vector3.new(0.25, 0, 0),
	Vector3.new(-0.25, 0, 0),
	Vector3.new(0, 0, 0.25),
	Vector3.new(0, 0, -0.25),
}
local RC_UP_LEN   = 3.0
local RC_DOWN_LEN = 3.0

-- Voxel multiprobe (backup)
local VOXEL_PROBES = {
	Vector3.new(0,   -0.5,  0),
	Vector3.new(0,   -1.0,  0),
	Vector3.new(0,   -1.5,  0),
	Vector3.new(0,   -2.0,  0),
	Vector3.new(0.25,-1.25, 0),
	Vector3.new(-0.25,-1.25,0),
	Vector3.new(0,   -1.25, 0.25),
	Vector3.new(0,   -1.25,-0.25),
}
local CELL_RADIUS  = 1
local VOXEL_RES    = 4

-- Debug overlay
local DEBUG = true -- set ke false jika sudah stabil

-- ================== REFERENSI NILAI ==================
local oxygenValue: NumberValue     = player:WaitForChild("Oxygen")
local maxOxygenValue: NumberValue  = player:WaitForChild("MaxOxygen")

-- ================== R15 HOOK ==================
local humanoid: Humanoid
local head: BasePart
local function hookCharacter(char: Model)
	humanoid = char:WaitForChild("Humanoid")
	head     = char:WaitForChild("Head")
end
hookCharacter(player.Character or player.CharacterAdded:Wait())
player.CharacterAdded:Connect(hookCharacter)

local function makeDebug()
	local gui = Instance.new("ScreenGui")
	gui.Name = "UnderwaterDebug"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Info"
	lbl.Size = UDim2.new(0, 560, 0, 110)
	lbl.Position = UDim2.new(0, 8, 0, 8)
	lbl.BackgroundTransparency = 0.25
	lbl.BackgroundColor3 = Color3.fromRGB(0,0,0)
	lbl.TextColor3 = Color3.fromRGB(255,255,255)
	lbl.Font = Enum.Font.GothamMedium
	lbl.TextSize = 14
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Top
	lbl.BorderSizePixel = 0
	lbl.Parent = gui
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,8); corner.Parent = lbl
	return lbl
end


-- ================== RAYCAST (UP/DOWN voting) ==================
local rcParams = RaycastParams.new()
rcParams.FilterType = Enum.RaycastFilterType.Exclude
rcParams.IgnoreWater = false
rcParams.FilterDescendantsInstances = {}

-- return: decided:boolean, headSubmerged:boolean, votesSub:number, votesAbove:number, upW:number, upA:number, downW:number, downA:number
local function headRaycastVote(headPart: BasePart)
	if not headPart or not headPart.Parent then
		return false, false, 0, 0, 0, 0, 0, 0
	end

	rcParams.FilterDescendantsInstances = { headPart.Parent }
	local base = headPart.Position

	local votesSubmerged = 0
	local votesAbove     = 0
	local upW, upA, downW, downA = 0,0,0,0
	local anyHit = false

	for _, off in ipairs(RC_OFFSETS) do
		local origin = base + off

		local up = Workspace:Raycast(origin, Vector3.new(0, RC_UP_LEN, 0), rcParams)
		if up then
			anyHit = true
			if up.Material == Enum.Material.Water then
				upW += 1
				votesSubmerged += 1 -- air di atas kepala → terendam
			else
				upA += 1
				votesAbove += 1     -- non-water di atas kepala → di atas permukaan
			end
		end

		local down = Workspace:Raycast(origin, Vector3.new(0, -RC_DOWN_LEN, 0), rcParams)
		if down then
			anyHit = true
			if down.Material == Enum.Material.Water then
				downW += 1
				-- Jika UP tidak memberi suara, ray DOWN yang kena Water menyiratkan permukaan di bawah kepala → di atas
				if not up then
					votesAbove += 1
				end
			else
				downA += 1
				-- down non-water tidak memberi informasi posisi kepala relatif ke permukaan
			end
		end
	end

	local decided = (votesSubmerged > 0) or (votesAbove > 0)
	decided = decided and anyHit

	local headSubmerged = (votesSubmerged > 0)
	return decided, headSubmerged, votesSubmerged, votesAbove, upW, upA, downW, downA
end

-- ================== VOXEL (backup) ==================
local function readVoxelAt(worldPos: Vector3)
	local cellVec = terrain:WorldToCellPreferSolid(worldPos)
	if not cellVec then
		return false, false, 0
	end

	local cx, cy, cz = math.floor(cellVec.X), math.floor(cellVec.Y), math.floor(cellVec.Z)
	local minCell = Vector3int16.new(cx - CELL_RADIUS, cy - CELL_RADIUS, cz - CELL_RADIUS)
	local maxCell = Vector3int16.new(cx + CELL_RADIUS, cy + CELL_RADIUS, cz + CELL_RADIUS)

	local minX = math.min(minCell.X, maxCell.X)
	local minY = math.min(minCell.Y, maxCell.Y)
	local minZ = math.min(minCell.Z, maxCell.Z)
	local maxX = math.max(minCell.X, maxCell.X)
	local maxY = math.max(minCell.Y, maxCell.Y)
	local maxZ = math.max(minCell.Z, maxCell.Z)

	local region = Region3int16.new(
		Vector3int16.new(minX, minY, minZ),
		Vector3int16.new(maxX, maxY, maxZ)
	)

	local ok, materials, occupancy = pcall(function()
		return terrain:ReadVoxels(region, VOXEL_RES)
	end)
	if not ok or not materials or not occupancy then
		return false, false, 0
	end

	local occMax, waterFound = 0, false
	for x = 1, #materials do
		for y = 1, #materials[x] do
			for z = 1, #materials[x][y] do
				if materials[x][y][z] == Enum.Material.Water then
					waterFound = true
					local occ = occupancy[x][y][z]
					if occ > occMax then occMax = occ end
				end
			end
		end
	end
	return (waterFound and occMax > 0), true, occMax
end

-- return: decided:boolean, headSubmerged:boolean, hits:number, occMax:number
local function headVoxelMultiProbe(headPart: BasePart)
	if not headPart or not headPart.Parent then
		return false, false, 0, 0
	end
	local base = headPart.Position
	local hits, maxOcc = 0, 0
	local anyVoxel = false

	for _, off in ipairs(VOXEL_PROBES) do
		local pos = base + off
		local found, hasVoxel, occ = readVoxelAt(pos)
		if hasVoxel then anyVoxel = true end
		if found then
			hits += 1
			if occ > maxOcc then maxOcc = occ end
		end
	end

	if anyVoxel then
		local headSubmerged = (hits > 0 and maxOcc > 0)
		return true, headSubmerged, hits, maxOcc
	else
		return false, false, 0, 0
	end
end

-- ================== LOOP LOGIKA OXYGEN ==================
local last                = tick()
local wasSubmergedHybrid  = false
local surfacedAt          = 0
local lastSubmergedTime   = tick()  -- untuk REGEN_DELAY yang benar

RunService.RenderStepped:Connect(function()
	if not humanoid or not head or not head.Parent then return end

	local now = tick()
	local dt  = now - last
	last = now

	-- 1) Raycast voting (utama)
	local rcDecided, rcSub, vSub, vAbove, upW, upA, downW, downA = headRaycastVote(head)

	-- 2) Voxel multiprobe (backup) bila raycast belum memutuskan
	local vxDecided, vxSub, vxHits, vxOccMax = false, false, 0, 0
	if not rcDecided then
		vxDecided, vxSub, vxHits, vxOccMax = headVoxelMultiProbe(head)
	end

	-- 3) Fallback ke State bila masih belum bisa memutuskan
	local state = humanoid:GetState()
	local inSwimming = (state == Enum.HumanoidStateType.Swimming)

	local submergedHybrid
	local decidedBy = "state"
	if rcDecided then
		submergedHybrid = rcSub
		decidedBy = "raycast"
	elseif vxDecided then
		submergedHybrid = vxSub
		decidedBy = "voxel"
	else
		submergedHybrid = inSwimming
		decidedBy = "state"
	end

	-- Transisi muncul
	if wasSubmergedHybrid and not submergedHybrid then
		surfacedAt = now
	end
	if submergedHybrid then
		lastSubmergedTime = now
	end
	wasSubmergedHybrid = submergedHybrid


	if submergedHybrid then
		-- Drain O2
		local newO2 = math.max(0, oxygenValue.Value - OXYGEN_DRAIN_PER_SEC * dt)
		oxygenValue.Value = newO2
		if newO2 <= 0 then
			-- Sesak napas
			humanoid:TakeDamage(SUFFOCATE_DAMAGE_PER_SEC * dt)
		end
	else
		-- Regen O2 (jalan walau masih Swimming) setelah delay singkat
		if oxygenValue.Value < maxOxygenValue.Value then
			if (now - lastSubmergedTime) >= REGEN_DELAY then
				local bonus = 0
				if (now - surfacedAt) < JUST_SURFACED_TIME then bonus = JUST_SURFACED_BONUS end
				local regen = (OXYGEN_REGEN_PER_SEC + bonus) * dt
				oxygenValue.Value = math.min(maxOxygenValue.Value, oxygenValue.Value + regen)
			end
		end

		-- [HEAL REGEN] Regen Health saat bernapas (kepala di atas permukaan)
		-- Disinkronkan dengan REGEN_DELAY & bonus "baru muncul"
		if (now - lastSubmergedTime) >= HEAL_REGEN_DELAY then
			if humanoid.Health < humanoid.MaxHealth then
				-- Opsional: hanya heal bila O2 sudah mulai terisi (menghindari heal di 0 O2)
				if oxygenValue.Value > 0 then
					local healBonus = 0
					if (now - surfacedAt) < JUST_SURFACED_TIME then
						healBonus = JUST_SURFACED_HEAL_BONUS
					end
					local healAmount = (HEALTH_REGEN_PER_SEC + healBonus) * dt
					humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + healAmount)
				end
			end
		end
	end
end)
