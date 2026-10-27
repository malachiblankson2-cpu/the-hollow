# THE HOLLOW: a Roblox horror game

A round-based maze horror game. Players spawn in a lit lobby. Each round, a new pitch-black maze is generated and players drop into it. They have to find 5 glowing keys and reach the exit gate while something hunts them. If it catches you, you get a jumpscare.

## What's in it

- **A new maze every round**, built with random generation and some extra loops so players can escape the monster
- **The monster**: a tall black figure with glowing red eyes. It always knows roughly where you are and walks toward you. When it can see you, it runs.
- **First-person camera, a flashlight (F), and sprinting (Shift) with a stamina bar.** Phones get on-screen buttons.
- **Jumpscare**: a face fills the screen with shaking and red flashes
- **Danger effects**: the screen turns red and shakes as the monster gets closer
- **Leaderboard**: an "Escapes" count, saved between sessions
- **Shop**, with 4 ways to charge players:

| Item | Type | Suggested price | What it does |
|---|---|---|---|
| Super Flashlight | Game Pass (buy once) | 99 R$ | Brighter, wider, longer beam |
| Infinite Stamina | Game Pass (buy once) | 149 R$ | Sprint forever |
| Revive | Developer Product (buy again and again) | 25 R$ | Come back to life mid-round. The button pops up the moment you die. |
| Freeze Monster | Developer Product (buy again and again) | 35 R$ | Freezes the monster for 10 seconds for everyone |

## 1. Open it in Roblox Studio

1. Install Roblox Studio from create.roblox.com and log in with your account.
2. Open `TheHollow.rbxlx` with **File > Open from File**.
3. Press **Play** to test. The map, lobby and monster are all built when the game starts, so the editor looks empty until you press Play. That's normal.

## 2. Publish it to your account

1. **File > Publish to Roblox As... > Create new experience**. Give it a name and description.
2. On create.roblox.com, open the experience and go to **Configure > Questionnaire**. Fill out the maturity questionnaire. Jumpscares and horror themes are allowed, but you have to declare them.
3. To make it public, go to **Configure > Basic Settings** and set it to Public.
4. For saved stats in Studio, turn on **Game Settings > Security > Enable Studio Access to API Services**. They work in the live game either way.

## 3. Turn on the paid items

1. On create.roblox.com, open your experience and go to **Monetization > Passes**. Create "Super Flashlight" and "Infinite Stamina", set them **On Sale**, and set a price.
2. Go to **Monetization > Developer Products**. Create "Revive" and "Freeze Monster" with a price.
3. Copy each item's ID number into `Config` (ReplicatedStorage > Config in Studio):
   ```lua
   Config.GamePasses = { SuperFlashlight = 123456, InfiniteStamina = 123457 }
   Config.Products = { Revive = 987654, StunMonster = 987655 }
   ```
4. Publish again. Items left at `0` stay hidden, so the game works even before you set them up.

**How the money works:** players pay in Robux. You keep about 70% of a sale, minus a small fee. To turn Robux into real money (DevEx), you need to be 13 or older and have a verified email. You also need at least 30,000 earned Robux, and your account has to be in good standing.

## 4. Add sound (recommended)

Sound makes a huge difference in horror. In Studio, open the **Toolbox > Audio** tab. Find a jumpscare scream, an ambient drone and a pickup sound. Right-click each one, choose **Copy Asset ID**, then paste the IDs into Config:
```lua
Config.JUMPSCARE_SOUND_ID = "rbxassetid://..."
Config.AMBIENT_SOUND_ID = "rbxassetid://..."
```

## Tuning

Every setting is in `Config`: round length, maze size, number of keys, monster speeds, fog, stamina and so on. If the game is too hard, lower `MONSTER_CHASE_SPEED`. If it's too easy, raise it or set `KEYS_TO_ESCAPE` to 7.

## Editing the code outside Studio

The scripts live in `src/`. After you edit them, run `python3 build.py` to rebuild `TheHollow.rbxlx`. You can also just edit the scripts inside Studio.
