#!/usr/bin/env bash
# Add a Realm player to BVC and print a one-time login code for them.
# Realms can't register players automatically, so every player must be added once.
#   bash add-player.sh <XboxGamertag> [valid-seconds, default 86400 = 24h max]
set -euo pipefail
cd "$(dirname "$0")"

player="${1:?usage: bash add-player.sh <XboxGamertag> [valid-seconds]}"
duration="${2:-86400}"

docker compose exec bvc bvc-server admin generate-code \
  -c /data/config.hcl -p "$player" -g minecraft -d "$duration"
