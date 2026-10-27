-- GameServer (Script in ServerScriptService)
-- Builds the world, runs rounds, drives the monster, saves stats and handles purchases.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

-- We spawn characters ourselves so nobody loads in before the map exists.
Players.CharacterAutoLoads = false

---------------------------------------------------------------------------
-- Remotes and shared state
---------------------------------------------------------------------------

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local jumpscareEvent = Instance.new("RemoteEvent")
jumpscareEvent.Name = "Jumpscare"
jumpscareEvent.Parent = remotes

local notifyEvent = Instance.new("RemoteEvent")
notifyEvent.Name = "Notify"
notifyEvent.Parent = remotes

local function setShared(name, value)
	ReplicatedStorage:SetAttribute(name, value)
end

local function notifyAll(text, color)
	notifyEvent:FireAllClients(text, color)
end

local function notify(player, text, color)
	notifyEvent:FireClient(player, text, color)
end

setShared("State", "Waiting")
setShared("TimeLeft", 0)
setShared("KeysFound", 0)
setShared("KeysNeeded", Config.KEYS_TO_ESCAPE)

---------------------------------------------------------------------------
-- Lighting: pitch dark, heavy fog
---------------------------------------------------------------------------

for _, child in ipairs(Lighting:GetChildren()) do
	if child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("PostEffect") then
		child:Destroy()
	end
end

Lighting.ClockTime = 0
Lighting.Brightness = 0
Lighting.Ambient = Color3.fromRGB(8, 8, 12)
Lighting.OutdoorAmbient = Color3.fromRGB(8, 8, 12)
Lighting.EnvironmentDiffuseScale = 0
Lighting.EnvironmentSpecularScale = 0
Lighting.GlobalShadows = true
Lighting.FogColor = Color3.new(0, 0, 0)
Lighting.FogStart = 0
Lighting.FogEnd = Config.FOG_DISTANCE

local grade = Instance.new("ColorCorrectionEffect")
grade.Saturation = -0.45
grade.Contrast = 0.15
grade.TintColor = Color3.fromRGB(215, 225, 255)
grade.Parent = Lighting

---------------------------------------------------------------------------
-- Building helpers
---------------------------------------------------------------------------

local function makePart(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

---------------------------------------------------------------------------
-- Lobby (safe, lit room players wait in)
---------------------------------------------------------------------------

local LOBBY_CENTER = Vector3.new(Config.MAZE_WIDTH * Config.CELL_SIZE / 2, 0, -90)

local function buildLobby()
	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	lobby.Parent = workspace

	local size, h = 50, 16
	makePart({
		Name = "Floor",
		Size = Vector3.new(size, 1, size),
		Position = LOBBY_CENTER - Vector3.new(0, 0.5, 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(70, 50, 40),
	}, lobby)
	makePart({
		Name = "Roof",
		Size = Vector3.new(size, 1, size),
		Position = LOBBY_CENTER + Vector3.new(0, h + 0.5, 0),
		Color = Color3.fromRGB(30, 25, 25),
	}, lobby)
	local walls = {
		{ Vector3.new(0, h / 2, size / 2), Vector3.new(size, h, 1) },
		{ Vector3.new(0, h / 2, -size / 2), Vector3.new(size, h, 1) },
		{ Vector3.new(size / 2, h / 2, 0), Vector3.new(1, h, size) },
		{ Vector3.new(-size / 2, h / 2, 0), Vector3.new(1, h, size) },
	}
	for i, w in ipairs(walls) do
		makePart({
			Name = "Wall" .. i,
			Size = w[2],
			Position = LOBBY_CENTER + w[1],
			Material = Enum.Material.Brick,
			Color = Color3.fromRGB(60, 40, 38),
		}, lobby)
	end

	local lamp = makePart({
		Name = "Lamp",
		Size = Vector3.new(2, 1, 2),
		Position = LOBBY_CENTER + Vector3.new(0, h - 0.5, 0),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 190, 120),
		CanCollide = false,
	}, lobby)
	local light = Instance.new("PointLight")
	light.Range = 40
	light.Brightness = 1.5
	light.Color = Color3.fromRGB(255, 190, 120)
	light.Parent = lamp

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = LOBBY_CENTER + Vector3.new(0, 0.1, 0)
	spawn.Color = Color3.fromRGB(40, 30, 30)
	spawn.Material = Enum.Material.Slate
	spawn.Parent = lobby

	-- Sign on the wall explaining the game
	local sign = makePart({
		Name = "Sign",
		Size = Vector3.new(24, 9, 0.5),
		Position = LOBBY_CENTER + Vector3.new(0, 8, size / 2 - 1),
		Color = Color3.fromRGB(15, 10, 10),
	}, lobby)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.Creepster
	label.TextColor3 = Color3.fromRGB(200, 30, 30)
	label.Text = Config.GAME_NAME
		.. "\nFind "
		.. Config.KEYS_TO_ESCAPE
		.. " keys. Reach the gate.\nDon't let it see you."
	label.Parent = gui
	-- The sign faces into the room
	sign.CFrame = CFrame.lookAt(sign.Position, LOBBY_CENTER + Vector3.new(0, 8, 0))
end

buildLobby()

---------------------------------------------------------------------------
-- Maze generation (new layout every round)
---------------------------------------------------------------------------

local CELL = Config.CELL_SIZE
local W, H = Config.MAZE_WIDTH, Config.MAZE_HEIGHT
local WALL_T = 2

local mazeFolder: Folder? = nil
local exitDoor: BasePart? = nil
local exitOpen = false
local keysFound = 0

local function cellCenter(x, y)
	return Vector3.new((x - 0.5) * CELL, 0, (y - 0.5) * CELL)
end

local function generateCells(rng)
	local cells = {}
	for x = 1, W do
		cells[x] = {}
		for y = 1, H do
			cells[x][y] = { n = true, s = true, e = true, w = true, visited = false }
		end
	end

	-- Recursive backtracker
	local stack = { { 1, 1 } }
	cells[1][1].visited = true
	while #stack > 0 do
		local cur = stack[#stack]
		local x, y = cur[1], cur[2]
		local options = {}
		if y > 1 and not cells[x][y - 1].visited then
			table.insert(options, { x, y - 1, "n", "s" })
		end
		if y < H and not cells[x][y + 1].visited then
			table.insert(options, { x, y + 1, "s", "n" })
		end
		if x < W and not cells[x + 1][y].visited then
			table.insert(options, { x + 1, y, "e", "w" })
		end
		if x > 1 and not cells[x - 1][y].visited then
			table.insert(options, { x - 1, y, "w", "e" })
		end
		if #options == 0 then
			table.remove(stack)
		else
			local o = options[rng:NextInteger(1, #options)]
			cells[x][y][o[3]] = false
			cells[o[1]][o[2]][o[4]] = false
			cells[o[1]][o[2]].visited = true
			table.insert(stack, { o[1], o[2] })
		end
	end

	-- Knock out a few extra walls so there are loops to escape through
	for x = 1, W do
		for y = 1, H do
			if x < W and rng:NextNumber() < Config.EXTRA_OPENINGS then
				cells[x][y].e = false
				cells[x + 1][y].w = false
			end
			if y < H and rng:NextNumber() < Config.EXTRA_OPENINGS then
				cells[x][y].s = false
				cells[x][y + 1].n = false
			end
		end
	end
	return cells
end

local function wallPart(parent, position, size)
	return makePart({
		Name = "Wall",
		Size = size,
		Position = position,
		Material = Enum.Material.Concrete,
		Color = Color3.fromRGB(55, 55, 60),
	}, parent)
end

local function startFlicker(lampPart, light, rng)
	task.spawn(function()
		while lampPart.Parent do
			light.Enabled = rng:NextNumber() > 0.3
			lampPart.Transparency = light.Enabled and 0 or 0.8
			task.wait(rng:NextNumber(0.05, 0.6))
		end
	end)
end

local onKeyTouched -- defined below, needs round state
local onExitTouched

local function buildMaze()
	if mazeFolder then
		mazeFolder:Destroy()
	end
	local rng = Random.new()
	local cells = generateCells(rng)

	mazeFolder = Instance.new("Folder")
	mazeFolder.Name = "Maze"
	mazeFolder.Parent = workspace
	local wallsFolder = Instance.new("Folder")
	wallsFolder.Name = "Walls"
	wallsFolder.Parent = mazeFolder

	makePart({
		Name = "Floor",
		Size = Vector3.new(W * CELL + WALL_T, 1, H * CELL + WALL_T),
		Position = Vector3.new(W * CELL / 2, -0.5, H * CELL / 2),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(35, 33, 33),
	}, mazeFolder)

	local yMid = Config.WALL_HEIGHT / 2
	for x = 1, W do
		for y = 1, H do
			local c = cells[x][y]
			local center = cellCenter(x, y)
			if c.n then
				wallPart(
					wallsFolder,
					Vector3.new(center.X, yMid, (y - 1) * CELL),
					Vector3.new(CELL + WALL_T, Config.WALL_HEIGHT, WALL_T)
				)
			end
			if c.w then
				wallPart(
					wallsFolder,
					Vector3.new((x - 1) * CELL, yMid, center.Z),
					Vector3.new(WALL_T, Config.WALL_HEIGHT, CELL + WALL_T)
				)
			end
			if y == H then
				wallPart(
					wallsFolder,
					Vector3.new(center.X, yMid, y * CELL),
					Vector3.new(CELL + WALL_T, Config.WALL_HEIGHT, WALL_T)
				)
			end
			-- East border, except the exit gate in the far corner
			if x == W and y ~= H then
				wallPart(
					wallsFolder,
					Vector3.new(x * CELL, yMid, center.Z),
					Vector3.new(WALL_T, Config.WALL_HEIGHT, CELL + WALL_T)
				)
			end
		end
	end

	-- Exit gate
	local exitCenter = cellCenter(W, H)
	exitOpen = false
	exitDoor = makePart({
		Name = "ExitGate",
		Size = Vector3.new(WALL_T, Config.WALL_HEIGHT, CELL + WALL_T),
		Position = Vector3.new(W * CELL, yMid, exitCenter.Z),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(140, 0, 0),
	}, mazeFolder)
	local gateLight = Instance.new("PointLight")
	gateLight.Name = "GateLight"
	gateLight.Range = 18
	gateLight.Color = Color3.fromRGB(255, 0, 0)
	gateLight.Parent = exitDoor
	exitDoor.Touched:Connect(onExitTouched)

	-- Keys in random cells away from the start
	keysFound = 0
	setShared("KeysFound", 0)
	local used = { ["1,1"] = true, [W .. "," .. H] = true }
	local placed = 0
	while placed < Config.KEYS_TO_ESCAPE do
		local x, y = rng:NextInteger(1, W), rng:NextInteger(1, H)
		local id = x .. "," .. y
		if not used[id] and (x + y) > 4 then
			used[id] = true
			placed += 1
			local key = makePart({
				Name = "Key",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(1.5, 1.5, 1.5),
				Position = cellCenter(x, y) + Vector3.new(0, 2.5, 0),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 200, 40),
				CanCollide = false,
			}, mazeFolder)
			local glow = Instance.new("PointLight")
			glow.Range = 10
			glow.Brightness = 2
			glow.Color = Color3.fromRGB(255, 200, 40)
			glow.Parent = key
			key.Touched:Connect(function(hit)
				onKeyTouched(key, hit)
			end)
		end
	end

	-- Flickering lamps for atmosphere
	for _ = 1, Config.FLICKER_LAMPS do
		local pos = cellCenter(rng:NextInteger(1, W), rng:NextInteger(1, H))
		local lamp = makePart({
			Name = "Lamp",
			Size = Vector3.new(1, 0.4, 1),
			Position = pos + Vector3.new(0, Config.WALL_HEIGHT - 1, 0),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 140, 80),
			CanCollide = false,
		}, mazeFolder)
		local light = Instance.new("PointLight")
		light.Range = 16
		light.Brightness = 0.8
		light.Color = Color3.fromRGB(255, 140, 80)
		light.Parent = lamp
		startFlicker(lamp, light, rng)
	end

	return wallsFolder
end

---------------------------------------------------------------------------
-- Player state, stats, saving
---------------------------------------------------------------------------

local roundActive = false
local status: { [Player]: string } = {} -- "Lobby" | "Alive" | "Dead" | "Escaped"
local reviveTokens: { [Player]: number } = {}
local pendingStuns = 0

local function setStatus(player, s)
	status[player] = s
	player:SetAttribute("Status", s)
end

local store
pcall(function()
	store = DataStoreService:GetDataStore("HollowStats_v1")
end)

local function loadStats(player, escapes)
	if not store then
		return
	end
	local ok, value = pcall(function()
		return store:GetAsync("escapes_" .. player.UserId)
	end)
	if ok and typeof(value) == "number" then
		escapes.Value = value
	end
end

local function saveStats(player)
	local stats = player:FindFirstChild("leaderstats")
	if not store or not stats then
		return
	end
	local escapes = stats:FindFirstChild("Escapes")
	pcall(function()
		store:SetAsync("escapes_" .. player.UserId, escapes.Value)
	end)
end

local function addEscape(player)
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		stats.Escapes.Value += 1
	end
end

local function getAliveParts(player)
	local char = player.Character
	if not char then
		return nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hrp and hum and hum.Health > 0 then
		return hrp, hum
	end
	return nil
end

local function aliveCount()
	local n = 0
	for _, s in pairs(status) do
		if s == "Alive" then
			n += 1
		end
	end
	return n
end

---------------------------------------------------------------------------
-- Game passes
---------------------------------------------------------------------------

local function checkPasses(player)
	for name, id in pairs(Config.GamePasses) do
		if id > 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
			end)
			if ok and owns then
				player:SetAttribute(name, true)
			end
		end
	end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then
		return
	end
	for name, id in pairs(Config.GamePasses) do
		if id == passId then
			player:SetAttribute(name, true)
			notify(player, "Unlocked: " .. (Config.ShopText[name] or name), Color3.fromRGB(120, 255, 120))
		end
	end
end)

---------------------------------------------------------------------------
-- Characters
---------------------------------------------------------------------------

local function onCharacterAdded(player, char)
	local hum = char:WaitForChild("Humanoid")
	char:WaitForChild("HumanoidRootPart")
	hum.WalkSpeed = Config.WALK_SPEED

	if roundActive and status[player] == "Alive" then
		task.wait()
		char:PivotTo(CFrame.new(cellCenter(1, 1) + Vector3.new(0, 3, 0)))
	end

	hum.Died:Connect(function()
		if player.Character ~= char then
			return
		end
		if roundActive and status[player] == "Alive" then
			if (reviveTokens[player] or 0) > 0 then
				-- Pre-bought revive: status stays Alive, they respawn back in the maze
				reviveTokens[player] -= 1
				notifyAll(player.DisplayName .. " used a revive!", Color3.fromRGB(120, 255, 120))
			else
				setStatus(player, "Dead")
				notifyAll(player.DisplayName .. " was taken...", Color3.fromRGB(255, 60, 60))
			end
		end
		task.wait(3)
		if player.Parent and player.Character == char then
			player:LoadCharacter()
		end
	end)
end

local function onPlayerAdded(player)
	setStatus(player, "Lobby")
	reviveTokens[player] = 0
	player.CameraMode = Enum.CameraMode.LockFirstPerson

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player
	local escapes = Instance.new("IntValue")
	escapes.Name = "Escapes"
	escapes.Parent = stats

	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(player, char)
	end)

	task.spawn(loadStats, player, escapes)
	task.spawn(checkPasses, player)
	player:LoadCharacter()
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	saveStats(player)
	status[player] = nil
	reviveTokens[player] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveStats(player)
	end
end)

---------------------------------------------------------------------------
-- Monster
---------------------------------------------------------------------------

type Monster = {
	model: Model,
	root: BasePart,
	waypoints: { Vector3 },
	index: number,
	speed: number,
	wakeAt: number,
	stunnedUntil: number,
	catching: { [Player]: boolean },
}

local monster: Monster? = nil
local wallsFolder: Folder? = nil
local MONSTER_ROOT_Y = 5.5

local function buildMonster(position: Vector3): Monster
	local model = Instance.new("Model")
	model.Name = "Monster"

	local rootCF = CFrame.new(position.X, MONSTER_ROOT_Y, position.Z)
	local function bodyPart(name, size, offset, color, material)
		return makePart({
			Name = name,
			Size = size,
			CFrame = rootCF * offset,
			Color = color or Color3.fromRGB(10, 10, 10),
			Material = material or Enum.Material.SmoothPlastic,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = true,
		}, model)
	end

	local root = bodyPart("Root", Vector3.new(2, 2, 2), CFrame.new(), nil, nil)
	root.Transparency = 1
	model.PrimaryPart = root

	local black = Color3.fromRGB(8, 8, 8)
	bodyPart("Torso", Vector3.new(3, 5, 1.4), CFrame.new(0, 1.5, 0), black)
	bodyPart("LeftLeg", Vector3.new(0.9, 5, 0.9), CFrame.new(-0.8, -3, 0), black)
	bodyPart("RightLeg", Vector3.new(0.9, 5, 0.9), CFrame.new(0.8, -3, 0), black)
	bodyPart("LeftArm", Vector3.new(0.7, 7, 0.7), CFrame.new(-2, 0.5, -0.6) * CFrame.Angles(math.rad(25), 0, math.rad(-8)), black)
	bodyPart("RightArm", Vector3.new(0.7, 7, 0.7), CFrame.new(2, 0.5, -0.6) * CFrame.Angles(math.rad(25), 0, math.rad(8)), black)
	local head = bodyPart("Head", Vector3.new(2, 2.6, 2), CFrame.new(0, 5.4, 0) * CFrame.Angles(0, 0, math.rad(12)), black)
	local red = Color3.fromRGB(255, 0, 0)
	bodyPart("LeftEye", Vector3.new(0.35, 0.25, 0.1), CFrame.new(-0.5, 5.6, -1.02), red, Enum.Material.Neon)
	bodyPart("RightEye", Vector3.new(0.35, 0.25, 0.1), CFrame.new(0.5, 5.4, -1.02), red, Enum.Material.Neon)
	bodyPart("Mouth", Vector3.new(1.1, 0.15, 0.1), CFrame.new(0, 4.7, -1.02), Color3.fromRGB(90, 0, 0), Enum.Material.Neon)

	local eyeGlow = Instance.new("PointLight")
	eyeGlow.Color = red
	eyeGlow.Range = 12
	eyeGlow.Brightness = 2
	eyeGlow.Parent = head

	model.Parent = workspace
	return {
		model = model,
		root = root,
		waypoints = {},
		index = 1,
		speed = Config.MONSTER_HUNT_SPEED,
		wakeAt = os.clock() + Config.MONSTER_WAKE_DELAY,
		stunnedUntil = 0,
		catching = {},
	}
end

local function nearestTarget(from: Vector3)
	local best, bestDist, bestPos = nil, math.huge, nil
	for player, s in pairs(status) do
		if s == "Alive" then
			local hrp = getAliveParts(player)
			if hrp then
				local d = (hrp.Position - from).Magnitude
				if d < bestDist then
					best, bestDist, bestPos = player, d, hrp.Position
				end
			end
		end
	end
	return best, bestDist, bestPos
end

local function hasLineOfSight(from: Vector3, to: Vector3)
	if not wallsFolder then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { wallsFolder }
	return workspace:Raycast(from, to - from, params) == nil
end

local function runMonsterBrain(m: Monster)
	task.spawn(function()
		while monster == m and roundActive do
			local pos = m.root.Position
			local target, dist, goal = nearestTarget(pos)
			if target and goal then
				local sees = dist < Config.MONSTER_SIGHT and hasLineOfSight(pos, goal)
				m.speed = sees and Config.MONSTER_CHASE_SPEED or Config.MONSTER_HUNT_SPEED

				local path = PathfindingService:CreatePath({
					AgentRadius = 3,
					AgentHeight = 10,
					AgentCanJump = false,
					WaypointSpacing = 6,
				})
				local ok = pcall(function()
					path:ComputeAsync(Vector3.new(pos.X, 2, pos.Z), goal)
				end)
				if monster ~= m then
					break
				end
				if ok and path.Status == Enum.PathStatus.Success then
					local list = {}
					for i, wp in ipairs(path:GetWaypoints()) do
						if i > 1 then
							table.insert(list, wp.Position)
						end
					end
					m.waypoints, m.index = list, 1
				elseif sees then
					-- No path but a clear view: lunge straight at them
					m.waypoints, m.index = { goal }, 1
				end
			end
			task.wait(0.4)
		end
	end)
end

local function catchPlayer(m: Monster, player: Player, hum: Humanoid)
	m.catching[player] = true
	hum.WalkSpeed = 0
	jumpscareEvent:FireClient(player)
	task.delay(0.7, function()
		if hum.Parent then
			hum.Health = 0
		end
		m.catching[player] = nil
	end)
end

RunService.Heartbeat:Connect(function(dt)
	local m = monster
	if not m or not roundActive then
		return
	end
	local now = os.clock()
	if now < m.wakeAt or now < m.stunnedUntil then
		return
	end

	local pos = m.root.Position
	local wp = m.waypoints[m.index]
	if wp then
		local target = Vector3.new(wp.X, MONSTER_ROOT_Y, wp.Z)
		local delta = target - pos
		local dist = delta.Magnitude
		local step = m.speed * dt
		local newPos
		if dist <= step then
			newPos = target
			m.index += 1
		else
			newPos = pos + delta.Unit * step
		end
		if dist > 0.05 then
			m.model:PivotTo(CFrame.lookAt(newPos, newPos + Vector3.new(delta.X, 0, delta.Z)))
		end
		pos = newPos
	end

	for player, s in pairs(status) do
		if s == "Alive" and not m.catching[player] then
			local hrp, hum = getAliveParts(player)
			if hrp and hum then
				local flat = Vector3.new(hrp.Position.X - pos.X, 0, hrp.Position.Z - pos.Z)
				if flat.Magnitude < Config.MONSTER_KILL_RANGE then
					catchPlayer(m, player, hum)
				end
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Keys and exit
---------------------------------------------------------------------------

local function playerFromHit(hit)
	local model = hit:FindFirstAncestorOfClass("Model")
	return model and Players:GetPlayerFromCharacter(model)
end

onKeyTouched = function(key, hit)
	if not roundActive or not key.Parent then
		return
	end
	local player = playerFromHit(hit)
	if not player or status[player] ~= "Alive" then
		return
	end
	key:Destroy()
	keysFound += 1
	setShared("KeysFound", keysFound)
	notifyAll(
		player.DisplayName .. " found a key (" .. keysFound .. "/" .. Config.KEYS_TO_ESCAPE .. ")",
		Color3.fromRGB(255, 210, 60)
	)
	if keysFound >= Config.KEYS_TO_ESCAPE and exitDoor then
		exitOpen = true
		exitDoor.Color = Color3.fromRGB(0, 255, 120)
		exitDoor.Transparency = 0.4
		exitDoor.CanCollide = false
		local light = exitDoor:FindFirstChild("GateLight")
		if light then
			light.Color = Color3.fromRGB(0, 255, 120)
		end
		notifyAll("THE GATE IS OPEN. RUN to the far corner!", Color3.fromRGB(0, 255, 120))
		-- Opening the gate breaks any active freeze: the endgame is always a chase
		if monster then
			monster.stunnedUntil = 0
		end
	end
end

onExitTouched = function(hit)
	if not roundActive or not exitOpen then
		return
	end
	local player = playerFromHit(hit)
	if not player or status[player] ~= "Alive" then
		return
	end
	setStatus(player, "Escaped")
	addEscape(player)
	notifyAll(player.DisplayName .. " ESCAPED!", Color3.fromRGB(0, 255, 120))
	player:LoadCharacter()
end

---------------------------------------------------------------------------
-- Developer products (repeatable purchases)
---------------------------------------------------------------------------

local function applyStun(byPlayer)
	if roundActive and monster then
		monster.stunnedUntil = os.clock() + Config.STUN_DURATION
		notifyAll(
			byPlayer.DisplayName .. " froze the monster for " .. Config.STUN_DURATION .. "s!",
			Color3.fromRGB(120, 200, 255)
		)
	else
		pendingStuns += 1
		notify(byPlayer, "Freeze saved. It will trigger at the start of the next round.", Color3.fromRGB(120, 200, 255))
	end
end

local function applyRevive(player)
	if roundActive and status[player] == "Dead" then
		setStatus(player, "Alive")
		notifyAll(player.DisplayName .. " came back from the dead!", Color3.fromRGB(120, 255, 120))
		player:LoadCharacter()
	else
		reviveTokens[player] = (reviveTokens[player] or 0) + 1
		notify(player, "Revive saved. You'll come back automatically next time you're caught.", Color3.fromRGB(120, 255, 120))
	end
end

local handledPurchases = {}

MarketplaceService.ProcessReceipt = function(receipt)
	if handledPurchases[receipt.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		-- Roblox will retry next time they join
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if receipt.ProductId == Config.Products.Revive then
		applyRevive(player)
	elseif receipt.ProductId == Config.Products.StunMonster then
		applyStun(player)
	else
		warn("Unknown product purchased: " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	handledPurchases[receipt.PurchaseId] = true
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

---------------------------------------------------------------------------
-- Round loop
---------------------------------------------------------------------------

local function startRound()
	wallsFolder = buildMaze()
	task.wait(1) -- let the navigation mesh catch up with the new walls

	roundActive = true
	setShared("State", "Round")
	for _, player in ipairs(Players:GetPlayers()) do
		setStatus(player, "Alive")
		task.spawn(function()
			player:LoadCharacter()
		end)
	end

	local m = buildMonster(cellCenter(W, 1))
	monster = m
	runMonsterBrain(m)
	if pendingStuns > 0 then
		pendingStuns -= 1
		m.wakeAt += Config.STUN_DURATION
	end

	notifyAll(
		"Find " .. Config.KEYS_TO_ESCAPE .. " keys. It wakes in " .. Config.MONSTER_WAKE_DELAY .. " seconds...",
		Color3.fromRGB(255, 80, 80)
	)
end

local function endRound(timedOut)
	roundActive = false
	if monster then
		monster.model:Destroy()
		monster = nil
	end

	local escaped = {}
	for player, s in pairs(status) do
		if s == "Escaped" then
			table.insert(escaped, player.DisplayName)
		end
	end
	if #escaped > 0 then
		notifyAll("Survivors: " .. table.concat(escaped, ", "), Color3.fromRGB(0, 255, 120))
	elseif timedOut then
		notifyAll("Time's up. The Hollow keeps you.", Color3.fromRGB(255, 60, 60))
	else
		notifyAll("Nobody escaped.", Color3.fromRGB(255, 60, 60))
	end

	setShared("State", "Ended")
	task.wait(3)
	for _, player in ipairs(Players:GetPlayers()) do
		local wasInMaze = status[player] == "Alive"
		setStatus(player, "Lobby")
		if wasInMaze then
			task.spawn(function()
				player:LoadCharacter()
			end)
		end
	end
end

while true do
	setShared("State", "Waiting")
	while #Players:GetPlayers() < Config.MIN_PLAYERS do
		task.wait(1)
	end

	setShared("State", "Intermission")
	for t = Config.INTERMISSION, 1, -1 do
		setShared("TimeLeft", t)
		task.wait(1)
	end

	if #Players:GetPlayers() >= Config.MIN_PLAYERS then
		startRound()
		local t = Config.ROUND_TIME
		while t > 0 and aliveCount() > 0 do
			setShared("TimeLeft", t)
			task.wait(1)
			t -= 1
		end
		endRound(t <= 0)
		task.wait(2)
	end
end
