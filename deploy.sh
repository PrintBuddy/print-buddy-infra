#!/bin/bash

set -euo pipefail

# This script lives in print-buddy-infra/, alongside docker-compose.yml
# and .env. backend/, bot/, and frontend/ are expected as sibling
# directories one level up (the layout docker-compose.yml's build
# contexts — ../backend, ../bot, ../frontend/app — already assume).
INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="$(cd "$INFRA_DIR/.." && pwd)"
SERVICES=("frontend" "backend" "bot")

# --- Default Values ---
SERVICE="all"
FROM_CLEAN=false
BUMP_TYPE=""

# --- Help Function ---
show_help() {
    echo "Usage: ./deploy.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -s, --service [name]    Service to deploy (frontend, backend, bot, all). Default: all"
    echo "  -b, --bump [type]       Version bump type (major, minor, fix)."
    echo "  -c, --clean             Perform a clean build using --no-cache."
    echo "  -h, --help              Show this help message."
}


# --- Parse Arguments ---
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
        -c|--clean)
            FROM_CLEAN=true
            shift
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

# --- 2. Update Repositories ---
for service_name in "${SERVICES[@]}"; do
    if [[ "$SERVICE" == "all" || "$SERVICE" == "$service_name" ]]; then
        echo "→ Updating $service_name..."
        cd "$APPS_DIR/$service_name"
        git fetch origin main
        git reset --hard origin/main
        git clean -fd
        cd "$INFRA_DIR"
    fi
done

# --- 3. Build and Start ---
BUILD_CMD="docker compose build"
if [ "$FROM_CLEAN" = true ]; then
    echo "→ Forcing clean rebuild..."
    BUILD_CMD+=" --no-cache"
fi

if [[ "$SERVICE" == "all" ]]; then
    echo "→ Building and starting all services..."
    $BUILD_CMD
    docker compose up -d
else
    echo "→ Building and starting $SERVICE..."
    $BUILD_CMD "$SERVICE"
    docker compose up -d "$SERVICE"
fi

# --- 4. Cleanup ---
echo "→ Cleaning up dangling images..."
docker image prune -f

echo "==== DEPLOY COMPLETED ===="
