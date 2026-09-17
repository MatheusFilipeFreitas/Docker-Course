#!/usr/bin/env bash
# Runs on the server, next to docker-compose.yml and .env.
# Usage: deploy.sh <image-tag>   (the CD pipeline passes the commit hash)
# Pins the new version in .env, pulls it and recreates the app. If the new container
# does not become healthy, the previous version is restored.
set -euo pipefail

NEW_VERSION="$1"
cd "$(dirname "$0")"

PREVIOUS_VERSION=$(grep '^APP_VERSION=' .env | cut -d= -f2)

set_version() {
  sed -i.bak "s/^APP_VERSION=.*/APP_VERSION=$1/" .env && rm -f .env.bak
}

echo "[deploy] $PREVIOUS_VERSION -> $NEW_VERSION"
set_version "$NEW_VERSION"

if docker compose pull app && docker compose up -d --wait --wait-timeout 180 app; then
  echo "[deploy] version $NEW_VERSION is healthy"
else
  echo "[deploy] version $NEW_VERSION failed, rolling back to $PREVIOUS_VERSION"
  set_version "$PREVIOUS_VERSION"
  docker compose up -d --wait --wait-timeout 180 app
  exit 1
fi
