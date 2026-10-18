#!/usr/bin/env bash
# Snapshot ./data (config, SQLite DB with the login CA, certificates) to ./backups.
# The server is stopped for a few seconds so the SQLite file is consistent.
#   bash backup.sh            keeps the newest 14 backups
#   KEEP=30 bash backup.sh    keeps 30
set -euo pipefail
cd "$(dirname "$0")"

keep="${KEEP:-14}"
stamp="$(date +%Y%m%d-%H%M%S)"
out="backups/bvc-data-${stamp}.tar.gz"
mkdir -p backups

was_running=false
if [ -n "$(docker compose ps -q --status running bvc 2>/dev/null)" ]; then
  was_running=true
  docker compose stop bvc
fi

# Make sure the server comes back even if tar fails.
restart() { if $was_running; then docker compose start bvc; fi; }
trap restart EXIT

# Files are owned by the container user (uid 100), so read them with sudo. Logs are skipped.
sudo tar --exclude='data/logs' -czf "$out" data
sudo chown "$(id -u):$(id -g)" "$out"
chmod 600 "$out"
echo "Backup written: $out"

# Rotate old backups.
ls -1t backups/bvc-data-*.tar.gz 2>/dev/null | tail -n +"$((keep + 1))" | xargs -r rm -f
