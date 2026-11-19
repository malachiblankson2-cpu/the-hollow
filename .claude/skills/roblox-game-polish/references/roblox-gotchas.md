# Roblox traps that look fine in code

Each of these shipped in a real game and was only caught by a playtester. Search the code for them.

**Revive nobody sees.** The round loop ends when no one is alive, so a solo player's death ends the round immediately, and any "Revive" button that only shows during a round never appears. Fix: when everyone is down, run a short revive window before ending the round.

**Spawning into a void.** With `Players.CharacterAutoLoads = false` and `LoadCharacter()`, Roblox picks *any* SpawnLocation, including a template's default spawn somewhere dark. Fix: in `CharacterAdded`, `PivotTo` the character to the intended spot (lobby or play area) based on their state.

**Flashlight shadowed by your own body.** A SpotLight placed at the camera, in third person, sits behind the character, so the character casts a shadow down the middle of the beam. Fix: place it at the head (plus a little forward) and aim it along the camera's look vector. When spectating, use the camera subject's head.

**Fog does nothing.** When an `Atmosphere` exists in Lighting, `FogStart`/`FogEnd` are ignored. Don't tune both.

**Light limits.** PointLight/SpotLight `Range` caps at 60. A client renders only a limited number of `Highlight`s at once (about 31), so use them for a handful of objectives, not every pickup.

**Dark colour grading.** A `ColorCorrectionEffect` with negative saturation and positive contrast crushes an already-dark scene to black. Check it whenever "players can't see".

**Camera for spectating.** A LocalScript can set `LocalPlayer.CameraMode` (e.g. Classic while spectating, back to LockFirstPerson after) and `camera.CameraSubject`. Respawning resets the subject, so reapply it in `CharacterAdded`. Raise `CameraMinZoomDistance` while spectating so the view isn't stuck in first person.

**Cutscene camera.** Set `CameraType = Scriptable` for a scripted shot and always restore `Custom` (and the old FieldOfView) afterwards, including when the target disappears mid-shot.

**Purchases.**
- `ProcessReceipt` must be idempotent (remember handled `PurchaseId`s) and return `NotProcessedYet` when the player isn't in the server, so Roblox retries.
- Prompting a product in the lobby needs a meaning (e.g. a saved revive token, a freeze queued for next round), otherwise players pay for nothing.
- Fetch real prices with `MarketplaceService:GetProductInfo` instead of hard-coding them in UI text.

**Saving.** Only save a player's data if it loaded successfully, otherwise a DataStore outage overwrites real progress with zeros. Wrap DataStore, Badge and Analytics calls in `pcall`.

**Sound IDs disappear.** Roblox removes uploads over time. Keep a fallback list per sound, preload, use the first that loads, and warn in Output when none do.

**Pathfinding after rebuilding the map.** Give the navigation mesh a moment (`task.wait(1)`) after generating new walls before the AI computes paths.

**You can't run the game outside Studio.** Syntax-check with `luau-compile --null file.lua`. Use `luau-analyze` and ignore "Unknown global/type" for Roblox APIs. Tell the user exactly what to verify in Studio.
