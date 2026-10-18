#!/usr/bin/env bash
# All-in-one installer for the voice server + web portal.
#
#   git clone https://github.com/tam11a/minecraft-bvc-for-vps.git /opt/stacks/bvc
#   cd /opt/stacks/bvc && sudo bash install.sh
#
# It asks a few questions (first run only), then: installs Docker if missing, writes .env,
# opens firewall ports, installs cron jobs (certificate renewal, backups), gets the
# certificate, starts BVC and the web portal, and makes you BVC admin.
# Safe to re-run at any time; it keeps your .env and only fixes/starts what's missing.
set -euo pipefail
cd "$(dirname "$0")"
here="$(pwd -P)"

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '\n\033[31m✘ %s\033[0m\n' "$*" >&2; exit 1; }

env_value() { grep -E "^$1=" .env 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '\r'; }
set_env() {   # set_env KEY VALUE  (adds the line if missing; value used verbatim)
  V="$2" awk -v k="$1" 'BEGIN { v = ENVIRON["V"] }
    $0 ~ "^" k "=" { print k "=" v; done = 1; next } { print }
    END { if (!done) print k "=" v }' .env > .env.tmp && mv .env.tmp .env
}
ask() {       # ask VAR "Question" [default] [secret]
  local __var="$1" __q="$2" __def="${3:-}" __secret="${4:-}" __ans=""
  while [ -z "$__ans" ]; do
    if [ -n "$__secret" ]; then read -rsp "  $__q: " __ans; echo
    else read -rp "  $__q${__def:+ [$__def]}: " __ans; fi
    __ans="${__ans:-$__def}"
  done
  printf -v "$__var" '%s' "$__ans"
}

# --------------------------------------------------------------------------------------------
bold "1/8  Checks"
[ "$(id -u)" -eq 0 ] || die "Run as root:  sudo bash install.sh"
[ "$here" = "/opt/stacks/bvc" ] || die "The repo must be at /opt/stacks/bvc (the web portal needs this path).
   git clone https://github.com/tam11a/minecraft-bvc-for-vps.git /opt/stacks/bvc"
ok "Running as root from $here"

if ! command -v docker >/dev/null; then
  warn "Docker not found, installing it (official script from get.docker.com)…"
  curl -fsSL https://get.docker.com | sh
fi
docker compose version >/dev/null 2>&1 || die "Docker Compose plugin is missing."
command -v crontab >/dev/null || { apt-get update -qq && apt-get install -y -qq cron >/dev/null; }
ok "Docker $(docker version --format '{{.Server.Version}}'), Compose and cron available"

# --------------------------------------------------------------------------------------------
bold "2/8  Settings (.env)"
[ -f .env ] || cp .env.example .env
chmod 600 .env

domain="$(env_value BVC_DOMAIN)"
if [ -z "$domain" ] || [ "$domain" = "yourname.duckdns.org" ]; then
  [ -t 0 ] || die ".env is not configured and there is no terminal to ask. Fill in .env, then re-run."
  echo "  BVC needs a hostname with a real certificate (a bare IP does not work)."
  echo "    1) Free DuckDNS subdomain (no domain needed)   ← recommended"
  echo "    2) My own domain, DNS on Cloudflare"
  ask choice "Choose 1 or 2" "1"
  if [ "$choice" = "2" ]; then
    ask domain "Hostname for the voice server (e.g. voice.example.com)"
    ask email "Email for Let's Encrypt"
    ask cftoken "Cloudflare API token (Edit zone DNS, one zone)" "" secret
    set_env BVC_DOMAIN "$domain"
    set_env DUCKDNS_TOKEN ""; set_env CERT_EMAIL ""; set_env BVC_TLS_CERTIFICATE ""; set_env BVC_TLS_KEY ""
    set_env BVC_ACME_PROVIDER cloudflare; set_env BVC_ACME_EMAIL "$email"; set_env BVC_ACME_API_TOKEN "$cftoken"
  else
    echo "  Create a subdomain at https://www.duckdns.org (sign in, add a name) and copy the token at the top."
    ask sub "DuckDNS subdomain (just the name, e.g. mycraftvoice)"
    sub="${sub%.duckdns.org}"; domain="$sub.duckdns.org"
    ask dtoken "DuckDNS token" "" secret
    ask email "Email for Let's Encrypt"
    set_env BVC_DOMAIN "$domain"
    set_env DUCKDNS_TOKEN "$dtoken"; set_env CERT_EMAIL "$email"
    set_env BVC_TLS_CERTIFICATE /data/tls/fullchain.pem; set_env BVC_TLS_KEY /data/tls/privkey.pem
    set_env BVC_ACME_PROVIDER ""; set_env BVC_ACME_EMAIL ""; set_env BVC_ACME_API_TOKEN ""
  fi
  ok "Saved to .env"
else
  ok "Using existing .env ($domain)"
fi

if [ -n "$(env_value BVC_ACME_PROVIDER)" ]; then mode=B; else mode=A; fi
if [ "$mode" = A ]; then
  [ -n "$(env_value DUCKDNS_TOKEN)" ] && [ -n "$(env_value CERT_EMAIL)" ] || die "Option A needs DUCKDNS_TOKEN and CERT_EMAIL in .env."
  portal_cert=/opt/stacks/bvc/data/tls/fullchain.pem; portal_key=/opt/stacks/bvc/data/tls/privkey.pem
else
  [ -z "$(env_value BVC_TLS_CERTIFICATE)$(env_value DUCKDNS_TOKEN)" ] || die "Both TLS options are set in .env. Empty the option A values."
  [ -n "$(env_value BVC_ACME_EMAIL)" ] && [ -n "$(env_value BVC_ACME_API_TOKEN)" ] || die "Option B needs BVC_ACME_EMAIL and BVC_ACME_API_TOKEN in .env."
  portal_cert=/opt/stacks/bvc/data/certificates/acme/cert.pem; portal_key=/opt/stacks/bvc/data/certificates/acme/key.pem
fi
ok "TLS option $mode ($([ $mode = A ] && echo 'DuckDNS + cert.sh' || echo 'Cloudflare, BVC built-in ACME'))"

# --------------------------------------------------------------------------------------------
bold "3/8  Files and permissions"
mkdir -p data backups lego portal/data
chown -R 100:101 data           # the BVC container runs as uid 100 / gid 101
printf 'PORTAL_SSL_CERT=%s\nPORTAL_SSL_KEY=%s\n' "$portal_cert" "$portal_key" > portal/.env
ok "data/ owned by the container user; portal certificate paths set"

# --------------------------------------------------------------------------------------------
bold "4/8  Firewall"
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow 443/tcp >/dev/null; ufw allow 28280/udp >/dev/null; ufw allow 8443/tcp >/dev/null
  ok "ufw: opened 443/tcp, 28280/udp, 8443/tcp"
else
  warn "ufw is not active, so nothing changed here."
fi
warn "If your VPS provider has a cloud firewall, open 443/tcp, 28280/udp and 8443/tcp there too."

# --------------------------------------------------------------------------------------------
bold "5/8  Scheduled jobs (cron)"
cron_lines="0 4 * * * cd $here && bash backup.sh >> backups/backup.log 2>&1 # bvc-managed"
if [ "$mode" = A ]; then
  cron_lines="30 3 * * * cd $here && bash cert.sh >> lego/renew.log 2>&1 # bvc-managed
$cron_lines"
else
  cron_lines="15 4 * * 1 docker restart bvc-portal >/dev/null 2>&1 # bvc-managed
$cron_lines"
fi
{ crontab -l 2>/dev/null | grep -v '# bvc-managed' || true; echo "$cron_lines"; } | crontab -
ok "Installed: $([ $mode = A ] && echo 'certificate renewal (daily), ')backups (nightly)$([ $mode = B ] && echo ', portal reload (weekly)')"

# --------------------------------------------------------------------------------------------
bold "6/8  Certificate"
if [ "$mode" = A ]; then
  bash cert.sh
  ok "Certificate for $domain is in place"
else
  ok "BVC requests the certificate itself on start (option B)"
fi

# --------------------------------------------------------------------------------------------
bold "7/8  Start the voice server and the web portal"
docker compose up -d
printf '  Waiting for BVC to become healthy'
for _ in $(seq 1 60); do
  status="$(docker inspect -f '{{.State.Health.Status}}' bvc 2>/dev/null || true)"
  [ "$status" = healthy ] && break
  printf '.'; sleep 5
done
echo
[ "$status" = healthy ] || die "BVC did not become healthy. Check:  docker compose logs --tail 100"
ok "BVC is running"

[ -f "$portal_cert" ] || die "Certificate file $portal_cert not found, so the portal can't start. Check: docker compose logs"
docker compose -f portal/compose.yaml up -d
ok "Web portal is running"

# --------------------------------------------------------------------------------------------
bold "8/8  BVC admin"
gamertag=""
if [ -t 0 ]; then
  read -rp "  Your Xbox gamertag, to make you BVC admin (Enter to skip): " gamertag
fi
if [ -n "$gamertag" ]; then
  code="$(docker compose exec -T bvc bvc-server admin generate-code -p "$gamertag" -g minecraft -d 86400 | sed -n 's/^Code: //p')"
  docker compose exec -T bvc bvc-server admin bootstrap -p "$gamertag" -g minecraft >/dev/null
  ok "$gamertag is admin. One-time login code (24 h): ${code:-see above}"
else
  warn "Skipped. Later: re-run install.sh, or use the portal terminal (docs/MANAGING.md)."
fi

# --------------------------------------------------------------------------------------------
bold "Done 🎉"
cat <<EOF
  Voice server address (for the BVC app):  https://$domain
  Web portal:                              https://$domain:8443

  Next:
  1. Open the web portal NOW and create its admin account (the first visitor creates it).
     Use a long, unique password: the portal can control this whole VPS.
  2. Install the BVC app, sign in to https://$domain with your Microsoft account (or the code).
  3. Add friends in the app: Settings → Manage Players.
  4. Put the no-net addon on your Realm: DEPLOY.md, Phase 5.
  5. Send players docs/PLAYER-GUIDE.md.

  Day-to-day management: docs/MANAGING.md. You can log out of SSH now.
EOF
