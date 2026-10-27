-- Config (ModuleScript in ReplicatedStorage)
-- Every number you'd want to tweak lives here. Shared by server and client.

local Config = {}

Config.GAME_NAME = "THE HOLLOW"

-- Rounds
Config.MIN_PLAYERS = 1          -- set to 2+ once you have real traffic
Config.INTERMISSION = 15        -- seconds in the lobby between rounds
Config.ROUND_TIME = 240         -- seconds per round
Config.KEYS_TO_ESCAPE = 5

-- Maze (regenerated every round)
Config.MAZE_WIDTH = 10          -- cells
Config.MAZE_HEIGHT = 10
Config.CELL_SIZE = 16           -- studs
Config.WALL_HEIGHT = 14
Config.EXTRA_OPENINGS = 0.12    -- chance to knock out extra walls so there are escape loops
Config.FLICKER_LAMPS = 10

-- Atmosphere
Config.FOG_DISTANCE = 70

-- Player movement
Config.WALK_SPEED = 14
Config.SPRINT_SPEED = 22
Config.STAMINA_SECONDS = 4      -- free players can sprint this long before resting
Config.STAMINA_REGEN = 0.5      -- stamina regained per second (fraction of full bar)

-- Monster
Config.MONSTER_WAKE_DELAY = 10  -- seconds of head start at the start of a round
Config.MONSTER_HUNT_SPEED = 9   -- when it can't see you (it always knows roughly where you are)
Config.MONSTER_CHASE_SPEED = 17 -- when it has line of sight
Config.MONSTER_SIGHT = 60
Config.MONSTER_KILL_RANGE = 4.5

-- Sounds: each slot lists IDs to try in order. The first one that loads gets used,
-- so if Roblox removes one the game falls back to the next. If a slot stays silent,
-- the Output window says which one: put a working ID from the Creator Store at the front.
Config.Sounds = {
	Jumpscare = { "rbxassetid://6754147732", "rbxassetid://6349647514", "rbxassetid://194068083" },
	Ambient = { "rbxassetid://140704980462451", "rbxassetid://139765110669684", "rbxassetid://139743346356072" },
	Heartbeat = { "rbxassetid://9082241193", "rbxassetid://9204476603" },
	Growl = { "rbxassetid://276691872" },
	Whisper = { "rbxassetid://9001132274", "rbxassetid://8873346609" },
	Stinger = { "rbxassetid://160442088", "rbxassetid://150829983", "rbxassetid://6899144196" },
	Key = { "rbxasset://sounds/electronicpingshort.wav" },
}

-- MONETIZATION -------------------------------------------------------------
-- Create these on create.roblox.com (see README), then paste the numeric IDs.
-- Anything left at 0 is hidden from the shop, so the game works before you set them up.

Config.GamePasses = {
	SuperFlashlight = 2058532921, -- one-time purchase: brighter, wider, longer flashlight
	InfiniteStamina = 2058502914, -- one-time purchase: sprint forever
}

Config.Products = {
	Revive = 3722997829,      -- repeatable: come back to life mid-round
	StunMonster = 3722997944, -- repeatable: freeze the monster for everyone
}

Config.STUN_DURATION = 10

-- Shop labels (prices are set on the Roblox website, these are just display text)
Config.ShopText = {
	SuperFlashlight = "Super Flashlight",
	InfiniteStamina = "Infinite Stamina",
	Revive = "Revive",
	StunMonster = "Freeze Monster",
}

return Config
