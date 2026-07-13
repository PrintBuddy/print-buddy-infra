#!/bin/bash
#
# Manual/emergency deploy — the normal path is the "Deploy" GitHub Actions
# workflow running automatically on the self-hosted runner every 5 minutes.
# Use this script when you want to force a deploy right now without
# waiting for the schedule, or if GitHub Actions itself is unreachable.

set -euo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES=("frontend" "backend" "bot")

SERVICE="all"
BUMP_TYPE=""

show_help() {
    echo "Usage: ./deploy.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -s, --service [name]    Service to deploy (frontend, backend, bot, all). Default: all"
    echo "  -b, --bump [type]       Version bump type (major, minor, fix)."
    echo "  -h, --help              Show this help message."
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--service)
            SERVICE="$2"
            shift 2
            ;;
        -b|--bump)
            BUMP_TYPE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

cd "$INFRA_DIR"

echo "==== DEPLOY STARTED ===="

# --- 1. Version Bump Logic ---
if [[ -n "$BUMP_TYPE" ]]; then
    ENV_FILE="$INFRA_DIR/.env"
    if [[ -f "$ENV_FILE" ]]; then
        CURRENT_VERSION=$(grep '^VERSION=' "$ENV_FILE" | cut -d '=' -f2 | tr -d '"' | tr -d "'")

        if [[ -n "$CURRENT_VERSION" ]]; then
            IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
            case "$BUMP_TYPE" in
                major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
                minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
                fix)   PATCH=$((PATCH + 1)) ;;
                *) echo "Error: Invalid bump type '$BUMP_TYPE'. Use major, minor, or fix."; exit 1 ;;
            esac
            NEW_VERSION="$MAJOR.$MINOR.$PATCH"
            echo "→ Bumping version: $CURRENT_VERSION -> $NEW_VERSION"
            sed -i "s/^VERSION=.*/VERSION=$NEW_VERSION/" "$ENV_FILE"
        fi
    else
        echo "⚠ .env file not found. Skipping version bump."
    fi
fi

# --- 2. Pull and start ---
if [[ "$SERVICE" == "all" ]]; then
    echo "→ Pulling and starting all services..."
    docker compose pull
    docker compose up -d
else
    echo "→ Pulling and starting $SERVICE..."
    docker compose pull "$SERVICE"
    docker compose up -d "$SERVICE"
fi

# --- 3. Cleanup ---
echo "→ Cleaning up dangling images..."
docker image prune -f

echo "==== DEPLOY COMPLETED ===="
