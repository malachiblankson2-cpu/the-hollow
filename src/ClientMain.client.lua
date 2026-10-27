-- ClientMain (LocalScript in StarterPlayer > StarterPlayerScripts)
-- HUD, flashlight, sprint/stamina, shop, jumpscares and the "it's close" effects.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local camera = workspace.CurrentCamera

local function make(className, props, parent)
	local obj = Instance.new(className)
	for k, v in pairs(props) do
		obj[k] = v
	end
	obj.Parent = parent
	return obj
end

local function sound(id, props)
	if id == "" then
		return nil
	end
	local s = make("Sound", { SoundId = id }, SoundService)
	for k, v in pairs(props or {}) do
		s[k] = v
	end
	return s
end

---------------------------------------------------------------------------
-- Sound design
---------------------------------------------------------------------------

-- Everything echoes like it's bouncing down concrete halls
SoundService.AmbientReverb = Enum.ReverbType.StoneCorridor

local sounds = {} -- slot name -> Sound, only for slots that loaded

local function loadSlot(slot, props)
	for _, id in ipairs(Config.Sounds[slot] or {}) do
		local s = sound(id, props)
		local loaded = false
		pcall(function()
			ContentProvider:PreloadAsync({ s }, function(_, status)
				loaded = status == Enum.AssetFetchStatus.Success
			end)
		end)
		if loaded then
			s.Name = slot
			sounds[slot] = s
			return s
		end
		s:Destroy()
	end
	warn("[The Hollow] No working sound for '" .. slot .. "'. Put a new ID first in Config.Sounds." .. slot)
	return nil
end

local function play(slot, props)
	local s = sounds[slot]
	if not s then
		return
	end
	for k, v in pairs(props or {}) do
		s[k] = v
	end
	s:Play()
end

-- Plays a copy of a sound from a point in the world, so it comes from a direction
local function playAt(slot, position, props)
	local template = sounds[slot]
	if not template then
		return
	end
	local emitter = make("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(0.2, 0.2, 0.2),
		Position = position,
	}, workspace)
	local s = template:Clone()
	s.RollOffMinDistance = 10
	s.RollOffMaxDistance = 120
	for k, v in pairs(props or {}) do
		s[k] = v
	end
	s.Parent = emitter
	s:Play()
	Debris:AddItem(emitter, 12)
end

local function inMaze()
	return ReplicatedStorage:GetAttribute("State") == "Round" and player:GetAttribute("Status") == "Alive"
end

-- Growl that comes from the monster itself, so you can hear which way it is
local function attachGrowl(monster)
	local head = monster:WaitForChild("Head", 5)
	if not head or not sounds.Growl or head:FindFirstChild("Growl") then
		return
	end
	local growl = sounds.Growl:Clone()
	growl.RollOffMinDistance = 8
	growl.RollOffMaxDistance = 90
	growl.Parent = head
	task.spawn(function()
		while monster.Parent do
			task.wait(math.random(40, 90) / 10)
			if monster.Parent then
				growl.PlaybackSpeed = math.random(75, 95) / 100
				growl:Play()
			end
		end
	end)
end

task.spawn(function()
	loadSlot("Jumpscare", { Volume = 1 })
	loadSlot("Key", { Volume = 0.6 })
	loadSlot("Stinger", { Volume = 0.6 })
	loadSlot("Whisper", { Volume = 0.7 })
	loadSlot("Growl", { Volume = 1 })
	local ambient = loadSlot("Ambient", { Looped = true, Volume = 0.35 })
	if ambient then
		ambient:Play()
	end
	local heartbeat = loadSlot("Heartbeat", { Looped = true, Volume = 0 })
	if heartbeat then
		heartbeat:Play()
	end

	local existing = workspace:FindFirstChild("Monster")
	if existing then
		attachGrowl(existing)
	end
end)

workspace.ChildAdded:Connect(function(child)
	if child.Name == "Monster" then
		attachGrowl(child)
		-- It's awake
		task.delay(Config.MONSTER_WAKE_DELAY, function()
			if child.Parent and inMaze() then
				play("Stinger", { Volume = 0.7, PlaybackSpeed = 0.7 })
			end
		end)
	end
end)

-- Key pickups chime; the last key sets off a scream somewhere in the dark
local lastKeys = 0
ReplicatedStorage:GetAttributeChangedSignal("KeysFound"):Connect(function()
	local keys = ReplicatedStorage:GetAttribute("KeysFound") or 0
	if keys > lastKeys then
		play("Key")
		if keys >= (ReplicatedStorage:GetAttribute("KeysNeeded") or math.huge) then
			play("Stinger", { Volume = 0.9, PlaybackSpeed = 0.85 })
		end
	end
	lastKeys = keys
end)

-- Random distant screams while you're in the maze
task.spawn(function()
	while true do
		task.wait(math.random(20, 50))
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and inMaze() then
			local angle = math.random() * math.pi * 2
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * math.random(35, 60)
			playAt("Stinger", hrp.Position + offset, { Volume = 0.45, PlaybackSpeed = math.random(70, 100) / 100 })
		end
	end
end)

local lastWhisper = 0

---------------------------------------------------------------------------
-- HUD
---------------------------------------------------------------------------

local gui = make("ScreenGui", {
	Name = "HorrorHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player:WaitForChild("PlayerGui"))

-- Red danger overlay that fades in as the monster gets close
local danger = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(120, 0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 1,
}, gui)

local statusLabel = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 44),
	Size = UDim2.fromOffset(420, 40),
	BackgroundTransparency = 1,
	Font = Enum.Font.Creepster,
	TextSize = 34,
	TextColor3 = Color3.fromRGB(230, 230, 230),
	TextStrokeTransparency = 0.4,
	Text = "",
	ZIndex = 5,
}, gui)

local notifyLabel = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 90),
	Size = UDim2.fromOffset(600, 32),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 22,
	TextColor3 = Color3.new(1, 1, 1),
	TextStrokeTransparency = 0.3,
	TextTransparency = 1,
	TextStrokeColor3 = Color3.new(0, 0, 0),
	TextWrapped = true,
	ZIndex = 5,
}, gui)

local staminaBack = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -24),
	Size = UDim2.fromOffset(220, 8),
	BackgroundColor3 = Color3.fromRGB(30, 30, 30),
	BorderSizePixel = 0,
	ZIndex = 5,
}, gui)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, staminaBack)
local staminaFill = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(200, 200, 200),
	BorderSizePixel = 0,
	ZIndex = 6,
}, staminaBack)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, staminaFill)

make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -38),
	Size = UDim2.fromOffset(400, 20),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 14,
	TextColor3 = Color3.fromRGB(150, 150, 150),
	Text = UserInputService.TouchEnabled and "" or "SHIFT run   F flashlight",
	ZIndex = 5,
}, gui)

local notifyToken = 0
remotes:WaitForChild("Notify").OnClientEvent:Connect(function(text, color)
	notifyToken += 1
	local myToken = notifyToken
	notifyLabel.Text = text
	notifyLabel.TextColor3 = color or Color3.new(1, 1, 1)
	notifyLabel.TextTransparency = 0
	notifyLabel.TextStrokeTransparency = 0.3
	task.delay(3.5, function()
		if notifyToken == myToken then
			TweenService:Create(notifyLabel, TweenInfo.new(1), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
		end
	end)
end)

local function formatTime(t)
	return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

local function refreshStatus()
	local state = ReplicatedStorage:GetAttribute("State")
	local t = ReplicatedStorage:GetAttribute("TimeLeft") or 0
	local myStatus = player:GetAttribute("Status")
	if state == "Waiting" then
		statusLabel.Text = "Waiting for players..."
	elseif state == "Intermission" then
		statusLabel.Text = "Next round in " .. t
	elseif state == "Round" then
		local keys = (ReplicatedStorage:GetAttribute("KeysFound") or 0) .. "/" .. (ReplicatedStorage:GetAttribute("KeysNeeded") or 0)
		if myStatus == "Dead" then
			statusLabel.Text = "You were taken   " .. formatTime(t)
		elseif myStatus == "Escaped" then
			statusLabel.Text = "You escaped   " .. formatTime(t)
		elseif myStatus == "Alive" then
			statusLabel.Text = "Keys " .. keys .. "   " .. formatTime(t)
		else
			statusLabel.Text = "Round in progress   " .. formatTime(t)
		end
	else
		statusLabel.Text = ""
	end
end

---------------------------------------------------------------------------
-- Shop
---------------------------------------------------------------------------

local shop = make("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	-- On phones the jump button sits bottom-right, so the shop goes above it
	Position = UserInputService.TouchEnabled and UDim2.new(1, -16, 1, -200) or UDim2.new(1, -16, 1, -16),
	Size = UDim2.fromOffset(180, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	ZIndex = 5,
}, gui)
make("UIListLayout", {
	Padding = UDim.new(0, 6),
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, shop)

local function shopButton(text, color, order, onClick)
	local b = make("TextButton", {
		Size = UDim2.fromOffset(180, 38),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.15,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = Color3.new(1, 1, 1),
		Text = text,
		LayoutOrder = order,
		AutoButtonColor = true,
		ZIndex = 6,
	}, shop)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
	b.Activated:Connect(onClick)
	return b
end

-- Prices come from the Roblox website, so they're always the real ones
local prices = {} -- shop name -> " · R$ 25"
local function label(name, text)
	return (text or Config.ShopText[name] or name) .. (prices[name] or "")
end
local function fetchPrice(name, id, infoType, button)
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(id, infoType)
		end)
		if ok and info and info.PriceInRobux then
			prices[name] = "  ·  R$ " .. info.PriceInRobux
			if button.Text == (Config.ShopText[name] or name) then
				button.Text = label(name)
			end
		end
	end)
end

local passButtons = {}
for name, id in pairs(Config.GamePasses) do
	if id > 0 then
		passButtons[name] = shopButton(Config.ShopText[name] or name, Color3.fromRGB(90, 60, 160), 1, function()
			MarketplaceService:PromptGamePassPurchase(player, id)
		end)
		fetchPrice(name, id, Enum.InfoType.GamePass, passButtons[name])
	end
end

local reviveButton, stunButton
if Config.Products.Revive > 0 then
	reviveButton = shopButton(Config.ShopText.Revive, Color3.fromRGB(30, 140, 70), 3, function()
		MarketplaceService:PromptProductPurchase(player, Config.Products.Revive)
	end)
	fetchPrice("Revive", Config.Products.Revive, Enum.InfoType.Product, reviveButton)
end
if Config.Products.StunMonster > 0 then
	stunButton = shopButton(Config.ShopText.StunMonster, Color3.fromRGB(40, 110, 180), 2, function()
		MarketplaceService:PromptProductPurchase(player, Config.Products.StunMonster)
	end)
	fetchPrice("StunMonster", Config.Products.StunMonster, Enum.InfoType.Product, stunButton)
end

local function refreshShop()
	for name, button in pairs(passButtons) do
		button.Visible = not player:GetAttribute(name)
	end
	local inRound = ReplicatedStorage:GetAttribute("State") == "Round"
	if reviveButton then
		-- Biggest impulse buy in the game: show it the moment you die
		local dead = inRound and player:GetAttribute("Status") == "Dead"
		reviveButton.Visible = dead
		reviveButton.Size = dead and UDim2.fromOffset(180, 54) or UDim2.fromOffset(180, 38)
		reviveButton.Text = dead and label("Revive", "REVIVE NOW") or label("Revive")
	end
	if stunButton then
		stunButton.Visible = inRound
	end
end

---------------------------------------------------------------------------
-- Flashlight (local only, follows the camera)
---------------------------------------------------------------------------

local lightPart = make("Part", {
	Name = "FlashlightLocal",
	Anchored = true,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	Transparency = 1,
	Size = Vector3.new(0.2, 0.2, 0.2),
}, workspace)
local spot = make("SpotLight", {
	Face = Enum.NormalId.Front,
	Shadows = true,
	Color = Color3.fromRGB(255, 244, 220),
}, lightPart)

local flashlightOn = true
local function applyFlashlight()
	local super = player:GetAttribute("SuperFlashlight")
	spot.Enabled = flashlightOn
	spot.Range = super and 60 or 32
	spot.Angle = super and 70 or 45
	spot.Brightness = super and 3 or 1.6
end
applyFlashlight()

local clickSound = sound("rbxasset://sounds/switch.wav", { Volume = 0.4 })

local function toggleFlashlight()
	flashlightOn = not flashlightOn
	if clickSound then
		clickSound:Play()
	end
	applyFlashlight()
end

---------------------------------------------------------------------------
-- Sprint and stamina
---------------------------------------------------------------------------

local stamina = 1
local wantsSprint = false

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift then
		wantsSprint = true
	elseif input.KeyCode == Enum.KeyCode.F then
		toggleFlashlight()
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		wantsSprint = false
	end
end)

-- Mobile buttons
if UserInputService.TouchEnabled then
	local run = make("TextButton", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -210, 1, -110),
		Size = UDim2.fromOffset(70, 70),
		BackgroundColor3 = Color3.fromRGB(40, 40, 40),
		BackgroundTransparency = 0.3,
		Text = "RUN",
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 6,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, run)
	local sprintTouch = nil
	run.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			sprintTouch = input
			wantsSprint = true
		end
	end)
	-- Fires even if the finger slides off the button, so sprint never gets stuck on
	UserInputService.TouchEnded:Connect(function(input)
		if input == sprintTouch then
			sprintTouch = nil
			wantsSprint = false
		end
	end)
	local light = make("TextButton", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -290, 1, -110),
		Size = UDim2.fromOffset(60, 60),
		BackgroundColor3 = Color3.fromRGB(40, 40, 40),
		BackgroundTransparency = 0.3,
		Text = "LIGHT",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 6,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, light)
	light.Activated:Connect(toggleFlashlight)
end

---------------------------------------------------------------------------
-- Jumpscare
---------------------------------------------------------------------------

local scaring = false

local function jumpscare()
	if scaring then
		return
	end
	scaring = true
	play("Jumpscare")

	local layer = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 50,
	}, gui)

	-- A crude, pale, stretched face built from UI shapes (swap for an image asset later)
	local face = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.45, 0.85),
		BackgroundColor3 = Color3.fromRGB(205, 200, 190),
		BorderSizePixel = 0,
		ZIndex = 51,
	}, layer)
	make("UICorner", { CornerRadius = UDim.new(0.45, 0) }, face)
	local scale = make("UIScale", { Scale = 0.2 }, face)

	local function feature(pos, size, color, z, round)
		local f = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = pos,
			Size = size,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = z,
		}, face)
		if round then
			make("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
		end
		return f
	end
	local black = Color3.new(0, 0, 0)
	local red = Color3.fromRGB(255, 0, 0)
	feature(UDim2.fromScale(0.3, 0.35), UDim2.fromScale(0.26, 0.17), black, 52, true)
	feature(UDim2.fromScale(0.7, 0.33), UDim2.fromScale(0.26, 0.19), black, 52, true)
	feature(UDim2.fromScale(0.3, 0.36), UDim2.fromScale(0.06, 0.04), red, 53, true)
	feature(UDim2.fromScale(0.7, 0.34), UDim2.fromScale(0.06, 0.04), red, 53, true)
	local mouth = feature(UDim2.fromScale(0.5, 0.72), UDim2.fromScale(0.5, 0.3), black, 52, true)
	for i = 1, 7 do
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(i / 8, 0),
			Size = UDim2.fromScale(0.07, 0.3 + (i % 2) * 0.15),
			Rotation = (i % 2 == 0) and 8 or -8,
			BackgroundColor3 = Color3.fromRGB(230, 225, 200),
			BorderSizePixel = 0,
			ZIndex = 53,
		}, mouth)
	end

	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.5 }):Play()

	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = math.max(0, 1 - (os.clock() - start) / 1.1)
		face.Position = UDim2.new(0.5, math.random(-25, 25) * k, 0.5, math.random(-25, 25) * k)
		layer.BackgroundColor3 = (math.random() < 0.3) and Color3.fromRGB(90, 0, 0) or black
	end)

	task.delay(1.2, function()
		conn:Disconnect()
		TweenService:Create(layer, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(face, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		for _, d in ipairs(face:GetDescendants()) do
			if d:IsA("Frame") then
				TweenService:Create(d, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			end
		end
		task.wait(0.6)
		layer:Destroy()
		scaring = false
	end)
end

remotes:WaitForChild("Jumpscare").OnClientEvent:Connect(jumpscare)

---------------------------------------------------------------------------
-- Per-frame: flashlight follow, sprint, monster proximity
---------------------------------------------------------------------------

RunService:BindToRenderStep("HorrorEffects", Enum.RenderPriority.Camera.Value + 1, function(dt)
	lightPart.CFrame = camera.CFrame

	-- Sprint
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local infinite = player:GetAttribute("InfiniteStamina")
	if hum and hum.Health > 0 and hum.WalkSpeed > 0 then
		local moving = hum.MoveDirection.Magnitude > 0.1
		local sprinting = wantsSprint and moving and (infinite or stamina > 0)
		hum.WalkSpeed = sprinting and Config.SPRINT_SPEED or Config.WALK_SPEED
		if sprinting and not infinite then
			stamina = math.max(0, stamina - dt / Config.STAMINA_SECONDS)
		elseif not sprinting then
			stamina = math.min(1, stamina + dt * Config.STAMINA_REGEN)
		end
	end
	staminaFill.Size = UDim2.fromScale(infinite and 1 or stamina, 1)
	staminaFill.BackgroundColor3 = infinite and Color3.fromRGB(170, 120, 255)
		or (stamina < 0.25 and Color3.fromRGB(220, 60, 60) or Color3.fromRGB(200, 200, 200))

	-- Monster proximity: red tint + camera shake
	local monster = workspace:FindFirstChild("Monster")
	local root = monster and monster.PrimaryPart
	local intensity = 0
	if root then
		local d = (root.Position - camera.CFrame.Position).Magnitude
		intensity = math.clamp(1 - d / 45, 0, 1)
	end
	danger.BackgroundTransparency = 1 - 0.35 * intensity

	-- Heartbeat gets louder and faster as it closes in; whispers when it's very close
	local heartbeat = sounds.Heartbeat
	if heartbeat then
		heartbeat.Volume = intensity * 0.9
		heartbeat.PlaybackSpeed = 0.9 + intensity * 0.6
	end
	if intensity > 0.55 and os.clock() - lastWhisper > 12 then
		lastWhisper = os.clock()
		play("Whisper")
	end
	if intensity > 0 then
		local s = 0.006 * intensity
		camera.CFrame *= CFrame.Angles((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0)
	end
end)

---------------------------------------------------------------------------
-- Keep HUD in sync
---------------------------------------------------------------------------

for _, attr in ipairs({ "State", "TimeLeft", "KeysFound", "KeysNeeded" }) do
	ReplicatedStorage:GetAttributeChangedSignal(attr):Connect(function()
		refreshStatus()
		refreshShop()
	end)
end
player.AttributeChanged:Connect(function()
	refreshStatus()
	refreshShop()
	applyFlashlight()
end)
refreshStatus()
refreshShop()
