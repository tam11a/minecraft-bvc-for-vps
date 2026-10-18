#!/usr/bin/env bash
# TLS option A (free DuckDNS subdomain): point the name at this VPS and get or renew
# its Let's Encrypt certificate, then restart BVC if the certificate changed.
# Safe to run as often as you like; schedule it daily with cron (see DEPLOY.md).
#   bash cert.sh
set -euo pipefail
cd "$(dirname "$0")"

LEGO_IMAGE="goacme/lego:v4.35.2"

env_value() { grep -E "^$1=" .env | tail -n1 | cut -d= -f2- | tr -d '\r' | sed -E "s/^[\"']|[\"']$//g"; }

[ -f .env ] || { echo ".env not found. Run install.sh first."; exit 1; }
domain="$(env_value BVC_DOMAIN)"
token="$(env_value DUCKDNS_TOKEN)"
email="$(env_value CERT_EMAIL)"

case "$domain" in
  *.duckdns.org) ;;
  *) echo "BVC_DOMAIN ($domain) is not a duckdns.org name. cert.sh is only for TLS option A."; exit 1 ;;
esac
[ "$domain" != "yourname.duckdns.org" ] || { echo "Set BVC_DOMAIN in .env first."; exit 1; }
[ -n "$token" ] || { echo "Set DUCKDNS_TOKEN in .env first."; exit 1; }
[ -n "$email" ] || { echo "Set CERT_EMAIL in .env first."; exit 1; }
if [ -n "$(env_value BVC_ACME_PROVIDER)$(env_value BVC_ACME_API_TOKEN)" ]; then
  echo "Option B (BVC_ACME_*) values are set too. Empty them; BVC refuses to start with both."; exit 1
fi

# 1. Point <name>.duckdns.org at this VPS (DuckDNS uses the caller's public IP when ip= is empty).
sub="${domain%.duckdns.org}"
reply="$(curl -fsS "https://www.duckdns.org/update?domains=${sub}&token=${token}&ip=")"
[ "$reply" = "OK" ] || { echo "DuckDNS update failed (reply: $reply). Check DUCKDNS_TOKEN and the subdomain."; exit 1; }
echo "DuckDNS: $domain -> this VPS"

# 2. Get the certificate (first run) or renew it when it has fewer than 30 days left.
#    DNS-01 through the DuckDNS API, so port 80 is not needed.
mkdir -p lego
if sudo test -f "lego/certificates/${domain}.crt"; then
  action=(renew --days 30)
else
  action=(run)
fi
docker run --rm -e DUCKDNS_TOKEN="$token" -v "$PWD/lego:/lego" "$LEGO_IMAGE" \
  --accept-tos --email "$email" --dns duckdns --domains "$domain" --path /lego "${action[@]}"

# 3. Install it where BVC reads it (BVC_TLS_CERTIFICATE / BVC_TLS_KEY), owned by the container user.
#    lego's .crt already contains the full chain.
src_crt="lego/certificates/${domain}.crt"
src_key="lego/certificates/${domain}.key"
dst_dir="data/tls"
if sudo cmp -s "$src_crt" "$dst_dir/fullchain.pem" 2>/dev/null; then
  echo "Certificate unchanged."
  exit 0
fi
sudo install -d -o 100 -g 101 -m 750 "$dst_dir"
sudo install -o 100 -g 101 -m 644 "$src_crt" "$dst_dir/fullchain.pem"
sudo install -o 100 -g 101 -m 600 "$src_key" "$dst_dir/privkey.pem"
echo "Certificate installed in $dst_dir."

# BVC and the web portal read certificate files only at startup.
if [ -n "$(docker compose ps -q --status running bvc 2>/dev/null)" ]; then
  docker compose restart bvc
  echo "BVC restarted with the new certificate."
fi
if [ "$(docker inspect -f '{{.State.Running}}' bvc-portal 2>/dev/null)" = "true" ]; then
  docker restart bvc-portal >/dev/null
  echo "Web portal restarted with the new certificate."
fi
