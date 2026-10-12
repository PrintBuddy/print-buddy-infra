#!/bin/bash
#
# Unattended deploy, meant to be run from cron on the VM (see README —
# "Automatic deploys"). Each run:
#   1. fast-forwards this repo's checkout if origin/main moved (so changes
#      to docker-compose.yml / scripts here are picked up too), and
#   2. pulls the latest backend/bot/frontend images from GHCR and restarts
#      only the containers whose image actually changed.
#
# Images are built by each app repo's own CI, never on the VM — so "is
# there a new version?" is answered by `docker compose pull` comparing
# image digests against GHCR, which is cheap when nothing changed.
#
# Safe to run as often as you like: it holds a lock so overlapping runs
# can't happen, and it's a no-op (apart from the log line) when neither
# this repo nor any image changed.

set -euo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_FILE="/tmp/print-buddy-auto-deploy.lock"
BRANCH="main"

cd "$INFRA_DIR"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "$(date -Is) another deploy is still running, skipping"
    exit 0
fi

log() { echo "$(date -Is) $*"; }

# --- 1. Sync this repo ---
git fetch --quiet origin "$BRANCH"
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse "origin/$BRANCH")" ]]; then
    log "infra repo changed: $(git rev-parse --short HEAD) -> $(git rev-parse --short "origin/$BRANCH")"
    git merge --ff-only --quiet "origin/$BRANCH"
fi

# --- 2. Pull images and restart whatever changed ---
before="$(docker compose images --quiet | sort)"
docker compose pull --quiet
docker compose up -d --quiet-pull
after="$(docker compose images --quiet | sort)"

if [[ "$before" != "$after" ]]; then
    log "deployed new image(s)"
    docker compose ps
    docker image prune -f >/dev/null
else
    log "no changes"
fi
