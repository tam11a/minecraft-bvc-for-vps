#!/usr/bin/env bash
# One-time setup on the voice VPS. Run from this directory:  bash setup.sh
set -euo pipefail
cd "$(dirname "$0")"

command -v docker >/dev/null || { echo "Docker is not installed: https://docs.docker.com/engine/install/"; exit 1; }
docker compose version >/dev/null || { echo "Docker Compose plugin is missing."; exit 1; }

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env from .env.example"
fi

# Generate the shared Minecraft <-> BVC access token if it is still the placeholder.
if grep -q '^BVC_ACCESS_TOKEN=change-me$' .env; then
  token="$(openssl rand -hex 32)"
  sed -i "s/^BVC_ACCESS_TOKEN=change-me$/BVC_ACCESS_TOKEN=${token}/" .env
  echo "Generated BVC_ACCESS_TOKEN (see .env). Realms don't use it; it's only required by the server config."
fi
chmod 600 .env

# The container runs as uid 100 / gid 101 and needs to write the DB, certs and logs into ./data.
mkdir -p data
sudo chown -R 100:101 data

# Open firewall ports if ufw is in use.
if command -v ufw >/dev/null && sudo ufw status | grep -q "Status: active"; then
  sudo ufw allow 443/tcp
  sudo ufw allow 28280/udp
  echo "Opened 443/tcp and 28280/udp in ufw."
else
  echo "ufw not active — make sure 443/tcp and 28280/udp are open (also in your VPS provider's firewall)."
fi

if grep -Eq '^(BVC_DOMAIN=voice\.example\.com|CF_API_TOKEN=replace-me|BVC_ACME_EMAIL=you@example\.com)$' .env; then
  echo
  echo "Edit .env (BVC_DOMAIN, BVC_ACME_EMAIL, CF_API_TOKEN), then run:  docker compose up -d"
  exit 0
fi

echo
echo "Ready. Start with:  docker compose up -d && docker compose logs -f"
