#!/usr/bin/env bash
# Rebuilds TheHollow.rbxlx and publishes it over the live game with Roblox Open Cloud.
# Needs ROBLOX_API_KEY in the environment (an Open Cloud key with Place Management write access).
set -euo pipefail

PLACE_ID="${ROBLOX_PLACE_ID:-138932885700266}"
cd "$(dirname "$0")/.."

if [ -z "${ROBLOX_API_KEY:-}" ]; then
	echo "ROBLOX_API_KEY is not set." >&2
	exit 1
fi

python3 build.py

UNIVERSE_ID="${ROBLOX_UNIVERSE_ID:-$(curl -sSf "https://apis.roblox.com/universes/v1/places/$PLACE_ID/universe" | python3 -c 'import json,sys; print(json.load(sys.stdin)["universeId"])')}"
echo "Publishing place $PLACE_ID (experience $UNIVERSE_ID)..."

curl -sSf -X POST \
	"https://apis.roblox.com/universes/v1/$UNIVERSE_ID/places/$PLACE_ID/versions?versionType=Published" \
	-H "x-api-key: $ROBLOX_API_KEY" \
	-H "Content-Type: application/xml" \
	--data-binary @TheHollow.rbxlx
echo
echo "Published."
