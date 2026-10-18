#!/usr/bin/env bash
# One-time setup on the voice VPS. Run from the repo folder (/opt/stacks/bvc):  bash setup.sh
# Run it twice: first to create .env, then again after filling .env in, to install the cron jobs.
# Safe to re-run: it never overwrites .env and replaces only its own cron lines.
set -euo pipefail
cd "$(dirname "$0")"
here="$(pwd -P)"

command -v docker >/dev/null || { echo "Docker is not installed: https://docs.docker.com/engine/install/"; exit 1; }
docker compose version >/dev/null || { echo "Docker Compose plugin is missing."; exit 1; }

if [ "$here" != "/opt/stacks/bvc" ]; then
  echo "Note: repo is at $here. The web portal (portal/) only works from /opt/stacks/bvc."
fi

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
  sudo ufw allow 443/tcp      # BVC login / API / WebSocket fallback
  sudo ufw allow 28280/udp    # BVC voice
  sudo ufw allow 8443/tcp     # web portal
  echo "Opened 443/tcp, 28280/udp and 8443/tcp in ufw."
else
  echo "ufw not active. Make sure 443/tcp, 28280/udp and 8443/tcp are open (also in your VPS provider's firewall)."
fi

env_value() { grep -E "^$1=" .env | tail -n1 | cut -d= -f2- | tr -d '\r'; }
domain="$(env_value BVC_DOMAIN)"

echo
if [ -z "$domain" ] || [ "$domain" = "yourname.duckdns.org" ]; then
  echo "Next: edit .env (BVC_DOMAIN and ONE TLS option), then run  bash setup.sh  again."
  exit 0
fi

if [ -n "$(env_value BVC_ACME_PROVIDER)" ]; then mode=B; else mode=A; fi

# Scheduled jobs, so the server looks after itself. Lines are tagged "# bvc-managed".
cron_lines="0 4 * * * cd $here && bash backup.sh >> backups/backup.log 2>&1 # bvc-managed"
if [ "$mode" = A ]; then
  # Renew the DuckDNS certificate (restarts BVC and the portal only when it changed).
  cron_lines="30 3 * * * cd $here && bash cert.sh >> lego/renew.log 2>&1 # bvc-managed
$cron_lines"
else
  # BVC renews its own certificate; reload the portal weekly so it picks up the renewed file.
  cron_lines="15 4 * * 1 docker restart bvc-portal >/dev/null 2>&1 # bvc-managed
$cron_lines"
fi
mkdir -p backups lego
{ crontab -l 2>/dev/null | grep -v '# bvc-managed' || true; echo "$cron_lines"; } | crontab -
echo "Installed cron jobs:"
echo "$cron_lines"

echo
echo "TLS option $mode. Next steps:"
if [ "$mode" = A ]; then
  echo "  bash cert.sh                       # point $domain here and get the certificate"
fi
echo "  docker compose up -d               # start the voice server"
if [ "$mode" = B ]; then
  echo "  (wait ~2 min for the certificate; option B: switch the two cert lines in portal/compose.yaml)"
fi
echo "  (cd portal && docker compose up -d)   # start the web portal"
echo "  then open https://$domain:8443 immediately and create the portal admin account."
