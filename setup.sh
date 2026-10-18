#!/usr/bin/env bash
# One-time setup on the voice VPS. Run from this directory:  bash setup.sh
# Safe to re-run: it never overwrites an existing .env.
set -euo pipefail
cd "$(dirname "$0")"

command -v docker >/dev/null || { echo "Docker is not installed: https://docs.docker.com/engine/install/"; exit 1; }
docker compose version >/dev/null || { echo "Docker Compose plugin is missing."; exit 1; }

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env from .env.example"
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
  echo "ufw not active. Make sure 443/tcp and 28280/udp are open (also in your VPS provider's firewall)."
fi

env_value() { grep -E "^$1=" .env | tail -n1 | cut -d= -f2- | tr -d '\r'; }
domain="$(env_value BVC_DOMAIN)"

echo
if [ -z "$domain" ] || [ "$domain" = "yourname.duckdns.org" ]; then
  echo "Next: edit .env (BVC_DOMAIN and ONE TLS option), then run setup.sh again or follow DEPLOY.md."
elif [ -n "$(env_value BVC_ACME_PROVIDER)" ]; then
  echo "TLS option B (own domain, Cloudflare). Start with:  docker compose up -d && docker compose logs -f"
else
  echo "TLS option A (DuckDNS). Get the certificate, then start:"
  echo "  bash cert.sh && docker compose up -d && docker compose logs -f"
fi
