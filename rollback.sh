#!/bin/bash
# Roll one service back to a specific previously-built image tag (a commit
# SHA — every image is pushed as both :latest and :<sha>, so any past
# commit on main is a valid rollback target as long as GHCR hasn't
# garbage-collected it).
#
# Usage: ./rollback.sh backend a1b2c3d
#
# This does NOT touch .env permanently — it's a one-shot override for this
# invocation only. To make a rollback stick across the next scheduled
# deploy tick, add e.g. BACKEND_TAG=a1b2c3d to .env directly (and remove it
# again once you're ready to track :latest again).

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: ./rollback.sh <backend|bot|frontend> <sha>"
    exit 1
fi

SERVICE="$1"
SHA="$2"

case "$SERVICE" in
    backend) VAR="BACKEND_TAG" ;;
    bot) VAR="BOT_TAG" ;;
    frontend) VAR="FRONTEND_TAG" ;;
    *) echo "Unknown service '$SERVICE' (expected backend, bot, or frontend)"; exit 1 ;;
esac

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$INFRA_DIR"

echo "→ Rolling $SERVICE back to $SHA..."
env "$VAR=$SHA" docker compose pull "$SERVICE"
env "$VAR=$SHA" docker compose up -d "$SERVICE"
echo "→ Done. This is a one-shot override — the next scheduled deploy will"
echo "  pull :latest again unless you add $VAR=$SHA to .env."
