---
name: roblox-game-polish
description: Review and polish a Roblox game to launch quality, the way a sharp playtester and a store-page reviewer would, then fix what can be fixed in code and list exact Creator Dashboard steps for the rest. Use this whenever someone wants a Roblox experience reviewed, playtested, "made better", made ready to launch or publish, or asks why players leave, why it isn't earning, or what to fix next — including after a big feature lands, before a first publish, and when starting the next game so the same mistakes aren't repeated. Covers gameplay readability, the first minute, death and revive flow, late joiners, monetization, store page, settings, badges and analytics.
---

# Roblox game polish

The goal is a game a brand-new player can understand, enjoy, and come back to, and a store page that earns the click. Reviews fail when they are vague ("lighting could be better"). Every finding should say what the player experiences, why it costs players or money, and the concrete fix with numbers.

## Workflow

1. **Gather what exists.** Read the scripts, the README or design notes, and any store details the user shares (description, icon, thumbnails, prices, settings screenshots). Note what the game *claims* to have ("glowing keys") so you can check it's really there.
2. **Play it in your head as a new player.** Walk the real path: join, lobby, first round start, the first 60 seconds, the first death, coming back, joining late, the store. For each step ask: can they see it, do they understand it, is it fair, is it fun, does it make them want another round? Read `references/checklist.md` and go through every section; it holds the full list of what to check and the numbers that tend to work.
3. **Check the code for the known traps** in `references/roblox-gotchas.md`. These are bugs that look fine in code but break the game for players (a revive button nobody ever sees, players spawning in a void, a flashlight shadowed by your own body).
4. **Write the review** in the format below, ranked by how much each issue costs players or money.
5. **Fix what you can in code**, smallest safe change first, in the order of the "Order to fix" list. Keep tuning numbers in a config module so the user can adjust them without hunting through code.
6. **Hand over the rest** as dashboard steps with exact menu paths, and copy the user can paste (descriptions, taglines).

## Review format

Use this structure. Severity is about impact on players and revenue, not effort.

```
🔴 Blockers: the game doesn't work for a new player
1. <What the player experiences>. <Why it happens, if known>. <Fix, with numbers>.

🟠 High: hurts retention and money
<Same shape. Include monetization balance here.>

🟡 Medium: polish
<Same shape.>

Game page
| Item | Status |
| Icon | ✅/❌ + one line |
| Thumbnails | ... |
| Description | ... (does it match reality?) |
| Maturity / audience | ... |
| Likes / favourites | ... |

Order to fix
1. <Short step> (group things that are done in one sitting)
...
```

Write findings as experiences, not implementation: "I couldn't see any keys" beats "key PointLight range is 10". Then give the implementation detail as the fix.

## Fixing in code

- Change behaviour in small, reviewable steps, and keep the game working at each step.
- Put every tuning number (light levels, speeds, timers, prices shown) in the config module with a comment saying what it does to the player.
- You usually cannot run Roblox. Say so plainly. Syntax-check Luau with `luau-compile --null` and `luau-analyze` if you can get the tools (official releases at github.com/luau-lang/luau). Ignore analyzer noise about Roblox globals, and act on anything else. Then tell the user exactly what to test in Studio and which config value to change if it feels off.
- When something can only be done on the Creator Dashboard, don't pretend you did it: list it under "For you to do on create.roblox.com" with the menu path.

## Store art

If the project draws its art in code (an HTML/SVG scene file rendered with Playwright), redraw rather than describe: keep every icon on one background and glow style, make the jumpscare/hero image show the same creature as the icon, and look at the rendered PNG before handing it over. Thumbnails that show something the game no longer has are worse than none.

## Next game

When the user starts a new game, run the checklist against the *design* before code exists: decide light levels, the first-minute grace period, the death screen, late-join behaviour, server size and the store set-up up front. These are far cheaper to design in than to patch after a bad first playtest.
