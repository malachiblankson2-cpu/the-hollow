-- GameServer (Script in ServerScriptService)
-- Builds the world, runs rounds, drives the monster, saves stats and handles purchases.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local BadgeService = game:GetService("BadgeService")
local AnalyticsService = game:GetService("AnalyticsService")

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
setShared("ReviveWindow", 0)

---------------------------------------------------------------------------
-- Lighting: very dark, thick air
---------------------------------------------------------------------------

for _, child in ipairs(Lighting:GetChildren()) do
	if child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("PostEffect") then
		child:Destroy()
	end
end

Lighting.ClockTime = 0
Lighting.Brightness = 0
Lighting.Ambient = Config.AMBIENT
Lighting.OutdoorAmbient = Config.AMBIENT
Lighting.EnvironmentDiffuseScale = 0
Lighting.EnvironmentSpecularScale = 0
Lighting.GlobalShadows = true

-- Atmosphere replaces fog: you can see what's near, the distance just fades to black
local atmosphere = Instance.new("Atmosphere")
atmosphere.Density = Config.ATMOSPHERE_DENSITY
atmosphere.Offset = 0
atmosphere.Color = Color3.fromRGB(18, 18, 22)
atmosphere.Decay = Color3.fromRGB(8, 8, 10)
atmosphere.Glare = 0
atmosphere.Haze = 1.5
atmosphere.Parent = Lighting

local grade = Instance.new("ColorCorrectionEffect")
grade.Saturation = -0.3
grade.Contrast = 0.05
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
local LOBBY_SPAWN = CFrame.new(LOBBY_CENTER + Vector3.new(0, 3, 0))
local escapeBoard: TextLabel? = nil -- the top escapes board in the lobby, filled in below

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
	spawn.Color = Color3.fromRGB(90, 22, 22)
	spawn.Material = Enum.Material.Slate
	spawn.Parent = lobby
	local padGlow = Instance.new("PointLight")
	padGlow.Color = Color3.fromRGB(255, 40, 30)
	padGlow.Range = 10
	padGlow.Brightness = 0.8
	padGlow.Parent = spawn

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

	-- Top escapes board on the opposite wall
	local board = makePart({
		Name = "TopEscapes",
		Size = Vector3.new(16, 11, 0.5),
		Position = LOBBY_CENTER + Vector3.new(0, 8, -size / 2 + 1),
		Color = Color3.fromRGB(15, 10, 10),
	}, lobby)
	board.CFrame = CFrame.lookAt(board.Position, LOBBY_CENTER + Vector3.new(0, 8, 0))
	local boardGui = Instance.new("SurfaceGui")
	boardGui.Face = Enum.NormalId.Front
	boardGui.Parent = board
	local boardText = Instance.new("TextLabel")
	boardText.Size = UDim2.fromScale(1, 1)
	boardText.BackgroundTransparency = 1
	boardText.TextScaled = true
	boardText.RichText = true
	boardText.Font = Enum.Font.GothamBold
	boardText.TextColor3 = Color3.fromRGB(225, 225, 225)
	boardText.Text = '<font face="Creepster" color="#dc1e1e">TOP ESCAPES</font>'
	boardText.Parent = boardGui
	escapeBoard = boardText

	-- Shop kiosks along the east wall: walk up and press E to buy
	local items = {}
	for name, id in pairs(Config.GamePasses) do
		if id > 0 then
			table.insert(items, { name = name, id = id, pass = true })
		end
	end
	for name, id in pairs(Config.Products) do
		if id > 0 then
			table.insert(items, { name = name, id = id, pass = false })
		end
	end
	table.sort(items, function(a, b)
		return a.name < b.name
	end)
	for i, item in ipairs(items) do
		local title = Config.ShopText[item.name] or item.name
		local stand = makePart({
			Name = "Kiosk",
			Size = Vector3.new(3, 4, 3),
			Position = LOBBY_CENTER + Vector3.new(size / 2 - 4, 2, (i - (#items + 1) / 2) * 9),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(25, 20, 20),
		}, lobby)
		makePart({
			Name = "KioskGlow",
			Size = Vector3.new(3.2, 0.3, 3.2),
			Position = stand.Position + Vector3.new(0, 2.15, 0),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(150, 15, 15),
			CanCollide = false,
		}, lobby)
		local tag = Instance.new("BillboardGui")
		tag.Size = UDim2.fromOffset(200, 40)
		tag.StudsOffset = Vector3.new(0, 4.5, 0)
		tag.MaxDistance = 45
		tag.Parent = stand
		local tagText = Instance.new("TextLabel")
		tagText.Size = UDim2.fromScale(1, 1)
		tagText.BackgroundTransparency = 1
		tagText.Font = Enum.Font.GothamBold
		tagText.TextSize = 20
		tagText.TextColor3 = Color3.new(1, 1, 1)
		tagText.TextStrokeTransparency = 0.3
		tagText.Text = title
		tagText.Parent = tag
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Buy"
		prompt.ObjectText = title
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = stand
		prompt.Triggered:Connect(function(player)
			if item.pass then
				MarketplaceService:PromptGamePassPurchase(player, item.id)
			else
				MarketplaceService:PromptProductPurchase(player, item.id)
			end
		end)
	end
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
		Material = Enum.Material.Brick,
		Color = Color3.fromRGB(120, 118, 115),
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
		Color = Color3.fromRGB(60, 57, 55),
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
				Size = Vector3.new(2, 2, 2),
				Position = cellCenter(x, y) + Vector3.new(0, 2.5, 0),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 200, 40),
				CanCollide = false,
			}, mazeFolder)
			local glow = Instance.new("PointLight")
			glow.Range = 12
			glow.Brightness = 2.5
			glow.Color = Color3.fromRGB(255, 190, 70)
			glow.Parent = key
			-- Outline shows through the dark, but not through walls
			local outline = Instance.new("Highlight")
			outline.DepthMode = Enum.HighlightDepthMode.Occluded
			outline.FillColor = Color3.fromRGB(255, 200, 60)
			outline.FillTransparency = 0.6
			outline.OutlineColor = Color3.fromRGB(255, 230, 140)
			outline.OutlineTransparency = 0
			outline.Parent = key
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
		light.Range = 24
		light.Brightness = 1.2
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
local roundStartedAt = 0
local roundPlayerCount = 0
local caughtCount: { [Player]: number } = {}
local fellAt: { [Player]: Vector3 } = {} -- where a revived player comes back
local protectedUntil: { [Player]: number } = {} -- the monster ignores freshly revived players

local function setStatus(player, s)
	status[player] = s
	player:SetAttribute("Status", s)
end

local store, escapeRanking
pcall(function()
	store = DataStoreService:GetDataStore("HollowStats_v1")
	escapeRanking = DataStoreService:GetOrderedDataStore("HollowEscapes_v1")
end)

-- Only players whose saved data loaded get saved, so a failed load never overwrites
-- real progress with zeros.
local statsLoaded: { [Player]: boolean } = {}

local function loadStats(player, escapes)
	if not store then
		return
	end
	local ok, value, revives, caught = pcall(function()
		return store:GetAsync("escapes_" .. player.UserId),
			store:GetAsync("revives_" .. player.UserId),
			store:GetAsync("caught_" .. player.UserId)
	end)
	if not ok or not player.Parent then
		return
	end
	if typeof(value) == "number" then
		escapes.Value = value
	end
	-- Revives are paid for, so unused ones carry over between sessions
	if typeof(revives) == "number" then
		reviveTokens[player] = (reviveTokens[player] or 0) + revives
	end
	if typeof(caught) == "number" then
		caughtCount[player] = (caughtCount[player] or 0) + caught
	end
	statsLoaded[player] = true
end

local function saveStats(player)
	local stats = player:FindFirstChild("leaderstats")
	if not store or not stats or not statsLoaded[player] then
		return
	end
	local escapes = stats:FindFirstChild("Escapes")
	local revives = reviveTokens[player] or 0
	pcall(function()
		store:SetAsync("escapes_" .. player.UserId, escapes.Value)
		store:SetAsync("revives_" .. player.UserId, revives)
		store:SetAsync("caught_" .. player.UserId, caughtCount[player] or 0)
		if escapeRanking and escapes.Value > 0 then
			escapeRanking:SetAsync(tostring(player.UserId), escapes.Value)
		end
	end)
end

local function awardBadge(player, name)
	local id = Config.Badges[name]
	if not id or id <= 0 then
		return
	end
	task.spawn(function()
		pcall(function()
			if not BadgeService:UserHasBadgeAsync(player.UserId, id) then
				BadgeService:AwardBadge(player.UserId, id)
			end
		end)
	end)
end

-- Custom events show up in the Creator Dashboard under Analytics
local function logEvent(player, name, value)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, name, value or 1)
	end)
end

local function addEscape(player)
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		stats.Escapes.Value += 1
		awardBadge(player, "FirstEscape")
		if stats.Escapes.Value >= 10 then
			awardBadge(player, "TenEscapes")
		end
		if roundPlayerCount == 1 then
			awardBadge(player, "SoloEscape")
		end
		task.spawn(saveStats, player)
	end
end

-- Top escapes board in the lobby
local nameCache: { [number]: string } = {}
local function refreshEscapeBoard()
	if not escapeRanking or not escapeBoard then
		return
	end
	local ok, page = pcall(function()
		return escapeRanking:GetSortedAsync(false, 10):GetCurrentPage()
	end)
	if not ok then
		return
	end
	local lines = { '<font face="Creepster" color="#dc1e1e">TOP ESCAPES</font>' }
	for i, entry in ipairs(page) do
		local id = tonumber(entry.key)
		local name = id and nameCache[id]
		if id and not name then
			local okName, result = pcall(function()
				return Players:GetNameFromUserIdAsync(id)
			end)
			name = okName and result or "?"
			nameCache[id] = name
		end
		table.insert(lines, i .. ".  " .. (name or "?") .. "   " .. entry.value)
	end
	if #page == 0 then
		table.insert(lines, "Nobody has escaped yet.")
	end
	escapeBoard.Text = table.concat(lines, "\n")
end

task.spawn(function()
	while true do
		refreshEscapeBoard()
		task.wait(60)
	end
end)

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

local function countStatus(wanted)
	local n = 0
	for _, s in pairs(status) do
		if s == wanted then
			n += 1
		end
	end
	return n
end

local function isProtected(player)
	return (protectedUntil[player] or 0) > os.clock()
end

-- A revived player gets a few seconds before the monster can take them again
local function protectRevived(player)
	protectedUntil[player] = os.clock() + Config.REVIVE_PROTECTION
	notify(player, "You have " .. Config.REVIVE_PROTECTION .. " seconds. RUN.", Color3.fromRGB(120, 255, 120))
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

	task.wait()
	if roundActive and status[player] == "Alive" then
		-- Round start puts you at the entrance; a revive puts you back where you fell
		local at = fellAt[player]
		fellAt[player] = nil
		char:PivotTo(CFrame.new((at or cellCenter(1, 1)) + Vector3.new(0, 3, 0)))
	else
		-- Everyone else goes to the lit lobby, never to wherever the place's default spawn is
		char:PivotTo(LOBBY_SPAWN)
	end

	hum.Died:Connect(function()
		if player.Character ~= char then
			return
		end
		if roundActive and status[player] == "Alive" then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then
				fellAt[player] = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
			end
			if (reviveTokens[player] or 0) > 0 then
				-- Pre-bought revive: status stays Alive, they respawn where they fell
				reviveTokens[player] -= 1
				protectRevived(player)
				notifyAll(player.DisplayName .. " used a revive!", Color3.fromRGB(120, 255, 120))
			else
				player:SetAttribute("SurvivedFor", math.floor(os.clock() - roundStartedAt))
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
	statsLoaded[player] = nil
	fellAt[player] = nil
	protectedUntil[player] = nil
	caughtCount[player] = nil
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
	wanderGoal: Vector3?,
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
		if s == "Alive" and not isProtected(player) then
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

local function computePath(from: Vector3, to: Vector3): { Vector3 }?
	local path = PathfindingService:CreatePath({
		AgentRadius = 3,
		AgentHeight = 10,
		AgentCanJump = false,
		WaypointSpacing = 6,
	})
	local ok = pcall(function()
		path:ComputeAsync(Vector3.new(from.X, 2, from.Z), to)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return nil
	end
	local list = {}
	for i, wp in ipairs(path:GetWaypoints()) do
		if i > 1 then
			table.insert(list, wp.Position)
		end
	end
	return list
end

local function runMonsterBrain(m: Monster)
	task.spawn(function()
		while monster == m and roundActive do
			local pos = m.root.Position
			local target, dist, goal = nearestTarget(pos)
			-- Early on it searches: slow, wandering, and only notices players who get close
			local searching = os.clock() < m.wakeAt + Config.MONSTER_SEARCH_TIME
			local sightRange = searching and Config.MONSTER_SEARCH_SIGHT or Config.MONSTER_SIGHT
			local sees = target ~= nil and dist < sightRange and hasLineOfSight(pos, goal)

			if searching and not sees then
				m.speed = Config.MONSTER_SEARCH_SPEED
				if not m.wanderGoal or m.index > #m.waypoints then
					m.wanderGoal = cellCenter(math.random(1, W), math.random(1, H)) + Vector3.new(0, 2, 0)
					local list = computePath(pos, m.wanderGoal)
					if monster ~= m then
						break
					end
					if list then
						m.waypoints, m.index = list, 1
					else
						m.wanderGoal = nil
					end
				end
			elseif goal then
				m.wanderGoal = nil
				m.speed = (sees and not searching) and Config.MONSTER_CHASE_SPEED or Config.MONSTER_HUNT_SPEED
				local list = computePath(pos, goal)
				if monster ~= m then
					break
				end
				if list then
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
	caughtCount[player] = (caughtCount[player] or 0) + 1
	if caughtCount[player] >= 50 then
		awardBadge(player, "Caught50")
	end
	logEvent(player, "Caught", math.floor(os.clock() - roundStartedAt))
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
		if s == "Alive" and not m.catching[player] and not isProtected(player) then
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
	logEvent(player, "KeyFound", keysFound)
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
	logEvent(player, "Escaped", math.floor(os.clock() - roundStartedAt))
	notifyAll(player.DisplayName .. " ESCAPED!", Color3.fromRGB(0, 255, 120))
	player:LoadCharacter()
end

---------------------------------------------------------------------------
-- Developer products (repeatable purchases)
---------------------------------------------------------------------------

local function applyStun(byPlayer)
	logEvent(byPlayer, "FreezeBought")
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
	logEvent(player, "ReviveBought")
	if roundActive and status[player] == "Dead" then
		setStatus(player, "Alive")
		protectRevived(player)
		notifyAll(player.DisplayName .. " came back from the dead!", Color3.fromRGB(120, 255, 120))
		player:LoadCharacter()
	else
		reviveTokens[player] = (reviveTokens[player] or 0) + 1
		task.spawn(saveStats, player)
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
	roundStartedAt = os.clock()
	roundPlayerCount = #Players:GetPlayers()
	table.clear(fellAt)
	table.clear(protectedUntil)
	setShared("State", "Round")
	for _, player in ipairs(Players:GetPlayers()) do
		setStatus(player, "Alive")
		logEvent(player, "RoundStarted", roundPlayerCount)
		task.spawn(function()
			player:LoadCharacter()
		end)
	end

	-- Far side of the maze from the entrance at (1, 1)
	local m = buildMonster(cellCenter(W, H - 1))
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
		local window = Config.REVIVE_WINDOW
		while t > 0 do
			if countStatus("Alive") > 0 then
				window = Config.REVIVE_WINDOW
				setShared("ReviveWindow", 0)
			elseif countStatus("Dead") > 0 and window > 0 then
				-- Everyone's down: a few seconds to buy a Revive before the round ends
				setShared("ReviveWindow", window)
				window -= 1
			else
				break
			end
			setShared("TimeLeft", t)
			task.wait(1)
			t -= 1
		end
		setShared("ReviveWindow", 0)
		endRound(t <= 0)
		task.wait(2)
	end
end
