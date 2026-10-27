# Store art

Upload these on create.roblox.com under your experience's icon and thumbnails settings.

| File | Use | Size |
|---|---|---|
| `icon.png` | Game icon | 512×512 |
| `title.png` | Thumbnail 1 (shown first) | 1920×1080 |
| `keys.png` | Thumbnail 2 | 1920×1080 |
| `behind.png` | Thumbnail 3 | 1920×1080 |
| `jumpscare.png` | Thumbnail 4 | 1920×1080 |
| `gate.png` | Thumbnail 5 | 1920×1080 |

## Shop item icons

Upload these on each item's page under Monetization (512×512; passes are shown cropped to a circle, so everything sits in the middle).

| File | Item |
|---|---|
| `flashlight.png` | Super Flashlight (pass) |
| `stamina.png` | Infinite Stamina (pass) |
| `revive.png` | Revive (developer product) |
| `freeze.png` | Freeze Monster (developer product) |

## Changing the art

The images are drawn in code in `scenes.html`. To re-render them after editing it, run this from this folder (needs Node and Playwright):

```
node render.js
```
