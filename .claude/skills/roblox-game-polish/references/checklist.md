# Launch checklist

Go through every section. Numbers are starting points that worked for a co-op horror maze; adjust for the genre, but always give a number.

## Contents
1. Blockers: can a new player play at all?
2. Retention and money
3. Monetization balance
4. Polish
5. Settings on the Creator Dashboard
6. Game page
7. Order to fix

## 1. Blockers

**Can they see?**
- Dark games still need light to bounce off something. Ambient around (12,12,15) lets wall shapes read at 3–4 studs without a torch; pure black reads as "broken", not "scary".
- Use an `Atmosphere` with high Density and a dark Color for "can't see far" instead of "can't see anything". Darkness should hide distance, not the floor in front of you.
- Walls mid-grey (around 120,118,115) in a textured material like Brick, not near-black. Dark surfaces swallow light.
- The free light source (torch, lantern) must be usable: range ~45, angle ~60°, brightness ~2.5–3. A paid upgrade only sells if the free one works but is limited.
- Compare against a place that already looks right (often the lobby): if the lobby reads well and the play area doesn't, it's the play area's lighting, not the textures.

**Can they find the objective?**
- If the description says "glowing", it must visibly glow from a distance: PointLight range ~12, warm colour, plus a `Highlight` with `DepthMode = Occluded` (shows through darkness, not walls).
- Give a second sense: a quiet 3D sound on each objective that gets louder as you approach turns searching into hunting.

**Is the first minute fair?**
- Count how long a new player lasts. Caught inside ~20 seconds of the threat waking = they leave.
- Spawn the threat on the far side of the map from players.
- Give it a slow "searching" phase for the first 30–45 seconds: wanders, slower than walking, only notices players who get close.
- The player should achieve one thing (first key, first coin) before the first chase. That first win is what makes them queue again.

**Does death lead somewhere?**
- After the death moment, show a screen: "YOU WERE CAUGHT", what they achieved (keys, time survived), and the paid/free ways back.
- Offer spectating teammates. It keeps them in the session and watching others play sells the game.
- Check solo play: if the round ends the instant the last player dies, the Revive button is never seen by solo players. Add a short revive window (~10–15 s) when everyone is down.
- A revive should put them back where they fell with a few seconds of protection, or it feels like a waste of Robux.
- Make sure every purchasable thing actually has a visible prompt at the moment it's wanted.

**Late joiners**
- Joining mid-round must land in a safe, lit place (lobby) with "Round in progress, next round in X", and ideally a spectate button. A black void looks broken.

## 2. Retention and money

**The signature moment** (jumpscare, boss reveal, big win): it's what people clip for TikTok and what the store screenshot sells.
- Prefer 3D over flat 2D: snap the camera onto the creature's face for ~0.6 s with shake, a loud sting, red vignette.
- It must match the icon and thumbnails: same creature, same colours.
- A flat clipart face reads as goofy, not scary.

**Server size**: co-op horror wants ~6 max. Large servers spread few players across empty servers and kill tension.

**Private servers**: on, ~50–100 R$/month. Friend groups are the buyers.

**Product descriptions**: never blank. One punchy line each, matching what the item really does.

**Icons**: all shop items in one style, on the game's brand colours (e.g. black background with red or white glow). Mixed styles make the store feel like a different game.

## 3. Monetization balance

- Passes that remove the core tension (infinite stamina in a chase game) sell but hurt the game for the buyer. Consider "+50%" instead. If the pass has already sold, don't change what buyers paid for; rename or add a new pass.
- Panic-moment products (freeze the monster) are usually the best sellers. Show the button when the danger is on screen (e.g. it grows and turns red when the creature is close), not hidden in a menu.
- Rewarded video ads can give a free revive once per round. That earns from players who will never buy.
- Prices: check each one against what it saves the player. Revive ~25, panic item ~35, convenience passes ~99–149 are common.

## 4. Polish

- **Spawn pad**: a black square looks like a hole or a missing texture. Give it colour or a dim glow.
- **Lobby downtime**: 15–30 seconds of nothing is where people leave. Add a rules board, a physical top leaderboard, and a store kiosk (ProximityPrompt per item).
- **HUD state**: every toggle shows its state (torch ON/OFF). Meters change colour when low (stamina red under 25%).
- **Devices**: if Console/VR are enabled, bind gamepad (e.g. R2 sprint, X torch) and show the controls; otherwise untick them. A broken console experience earns thumbs-down.
- **Avatar settings**: animations set to Standard (a ninja-run pack breaks horror). Consider a fixed scale so tiny avatars don't get odd hitboxes.
- **Badges**: free goals that bring players back: first win, solo win, 10 wins, a "failed 50 times" joke badge.
- **Analytics**: log custom events for round start, objective found, death (with time survived), win, purchases. Revisit round length once data exists.
- **Community**: a Roblox group linked on the game page, so updates have somewhere to go.

## 5. Settings on the Creator Dashboard

Give the user the path for each:
- Places → (place) → Settings → Server Fill → max players
- Monetization → Private Servers → enable + price
- Monetization → Passes / Developer Products → description, icon, price
- Engagement → Badges → create, then put IDs in config
- Avatar settings → Animation: Standard; Scale
- Basic settings → name (check for trailing spaces), description, promotional tagline (e.g. "Can you escape before it finds you?"), devices
- Social links → group
- Questionnaire → maturity; check the audience the rating reaches

## 6. Game page

| Item | What good looks like |
|---|---|
| Icon | Readable at small size; the creature or core idea; brand colours |
| Thumbnails | At least 3–5, uploaded (grey placeholder = looks unfinished). Real gameplay once the game looks right, plus a hook line each |
| Description | Clear structure and controls, and every claim true in the current build |
| Maturity / audience | Know who the rating reaches; younger audiences (e.g. Roblox's 9–15 bracket) may need extra publishing requirements |
| Name | No typos or trailing spaces |
| Likes / favourites | 0/0 looks dead; seed with friends and playtesters before promoting |

## 7. Order to fix

A sensible default; adapt to the game:
1. Visibility and objective findability (one Studio session)
2. Threat spawn distance and grace period
3. Death screen with spectate and revive/panic prompts
4. Late-join fix, server size, private servers
5. Signature moment (jumpscare)
6. Product descriptions and matching icons
7. Thumbnails (screenshot the game after the lighting fix)
8. Badges, lobby boards, analytics events
