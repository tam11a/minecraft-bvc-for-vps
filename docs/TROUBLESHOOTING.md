# Troubleshooting

Work from the outside in: **server reachable → certificate → UDP → players → Realm addon**.
Upstream reference: [BVC troubleshooting](https://www.bedrockvoicechat.com/wiki/server/troubleshooting/).

Run commands on the VPS from the repo folder (e.g. `/opt/bvc`) unless noted.

---

## 1. Is the server running?

```bash
docker compose ps
```

```bash
docker compose logs --tail 200
```

| You see | Cause / fix |
|---|---|
| Container restarting | Read the logs. Usually a config error (below). |
| Error naming an `env` variable | That variable is missing/empty in `.env` (e.g. `BVC_DOMAIN`). |
| `ACME env configuration is incomplete` | Option B is half filled in. Set all three `BVC_ACME_*` values, or empty all of them. |
| `tls.acme and tls.certificate/tls.key are mutually exclusive` | Both TLS options are filled in `.env`. Empty one, then `docker compose up -d --force-recreate`. |
| Certificate file not found (`/data/tls/...`) | Option A: run `bash cert.sh` before starting. |
| Permission denied on `/data/...` | Run `sudo chown -R 100:101 data`, then `docker compose restart`. |
| `address already in use` on 443 | Another service uses port 443. See [Port 443 is already taken](#port-443-is-already-taken). |
| Error mentioning `acme`, `cloudflare`, `dns` | See [Certificate problems](#certificate-problems). |
| Health `unhealthy` | The healthcheck calls `/health/readiness` inside the container. Check the logs; on option B the first certificate can take up to 2 minutes. |

A good start ends with a line like `TLS demultiplexer listening … listen=[::]:443`.

After changing `.env`, run `docker compose up -d --force-recreate`. A plain `restart` keeps the old environment.

## 2. Is it reachable from the internet?

From your **own PC**, not the VPS:

```bash
curl https://yourname.duckdns.org/api/config
```

| Result | Cause |
|---|---|
| JSON | Server, TLS and 443/tcp are fine ✅ |
| Connection refused | Container down or port not published |
| Timeout | ufw or the provider's cloud firewall blocks 443/tcp |
| Certificate error | Certificate not issued / wrong name / staging directory still set |
| 404 or an HTML page | Something else answers on 443 (another web server, or Cloudflare proxy is on) |

Check that the hostname points at the VPS (and, with Cloudflare, that the record is **DNS only** / grey cloud):

```bash
nslookup yourname.duckdns.org
```

## Certificate problems

**Option A (DuckDNS, `cert.sh`):**
- `DuckDNS update failed (reply: KO)`: wrong `DUCKDNS_TOKEN`, or the subdomain in `BVC_DOMAIN` isn't in your DuckDNS account.
- lego times out waiting for the TXT record: DuckDNS is slow or down. Run `bash cert.sh` again later; your current certificate keeps working until it expires.
- Check the certificate BVC serves: `echo | openssl s_client -connect yourname.duckdns.org:443 -servername yourname.duckdns.org 2>/dev/null | openssl x509 -noout -dates`
- Renewal log (if you used the cron line from DEPLOY.md): `lego/renew.log`.

**Option B (Cloudflare, BVC's built-in ACME):**
- **Token permissions:** the Cloudflare token needs *Zone → DNS → Edit* on the zone containing `BVC_DOMAIN`.
- **Wrong zone:** `BVC_DOMAIN` must be inside the zone the token covers.
- **Rate limited:** after many failed attempts Let's Encrypt blocks you for a while. Test with `BVC_ACME_DIRECTORY=https://acme-staging-v02.api.letsencrypt.org/directory` in `.env`, then remove it.
- **Staging left on:** apps reject staging certificates. Remove `BVC_ACME_DIRECTORY` and recreate the container.

**Both:** self-signed and IP-address certificates never work; BVC apps verify certificates like a browser.

## Sign-in works but nobody hears anything

Almost always **UDP 28280 is blocked**. Check:

1. ufw allows it:
   ```bash
   sudo ufw status
   ```
2. The provider's **cloud firewall** allows `28280/udp` (separate from ufw!).
3. `docker-compose.yml` publishes `28280:28280/udp`.
4. Cloudflare record is **DNS only**.

When a player's network blocks UDP entirely, the app falls back to WebSocket voice over 443/tcp, so audio working for some players but not others usually means those players' networks block UDP.

## Players can't sign in

| Symptom | Fix |
|---|---|
| `AUTH02` | Player isn't registered: `bash add-player.sh <Gamertag>` (exact Xbox gamertag). |
| Code rejected | Single-use, expires (24 h with `add-player.sh`). Generate a new one. |
| Everyone suddenly signed out | `data/bvc.sqlite3` was lost/replaced (it holds the login CA). Restore it from a backup, or re-add everyone. |
| App says version mismatch / can't open session | App and server are on different BVC releases. Align `BVC_VERSION` with the app. |

## Realm-specific problems

| Symptom | Cause / fix |
|---|---|
| Player joined but has no voice | They joined the Realm directly. They must join via the **Worlds** entry from Voice Chat Connect. |
| Voice stopped for everyone after a Minecraft update | Realm updated to a Bedrock version BVC doesn't support yet. Check [version support](https://www.bedrockvoicechat.com/wiki/platforms/version-support/), wait for a release, then upgrade (see [DEPLOY.md](../DEPLOY.md#upgrading-bvc)). |
| Nobody gets positions / voice never spatial | The world is missing the **no-net** pack or **Beta APIs**. Re-check the world settings, re-upload. The non-no-net `.mcaddon` doesn't work on Realms. |
| Addon version mismatch | The pack in the world must match `BVC_VERSION`. Rebuild with the matching `bvc-bds-pack-no-net-<version>.mcaddon`. |
| Can't reconnect right after leaving | Realms (NetherNet) refuse a new connection for ~5 minutes. Wait. |
| Console doesn't show the Worlds entry | Phone with BVC and console must be on the same LAN (no guest Wi-Fi / client isolation). |
| PC/mobile doesn't show the Worlds entry | Add server `127.0.0.1`, port `28282` under **Servers**. |

## Audio quality

- **Stutters as more players join:** the VPS needs more CPU. Add cores or use a dedicated-CPU plan.
- **A player goes silent every few minutes on mobile data:** carrier NAT changes their UDP port; QUIC tolerates only a few changes. Wi-Fi usually fixes it; otherwise report it upstream with the network type.

## Debug logging

In `data/config.hcl`:

```hcl
log {
    level = "debug"
}
```

```bash
docker compose restart && docker compose logs -f
```

JSON log files are in `data/logs/`. Set the level back to `info` afterwards, because debug is very noisy.

## Port 443 is already taken

If the VPS already runs a web server on 443, move BVC's TCP port, e.g. to 8443:

1. `data/config.hcl` → `port = 8443`
2. `docker-compose.yml`:
   - ports: `"8443:8443/tcp"` instead of `"443:443/tcp"`
   - healthcheck URL: `https://127.0.0.1:8443/health/readiness`
3. `sudo ufw allow 8443/tcp` (+ provider firewall)
4. `docker compose up -d`
5. Players use `https://yourname.duckdns.org:8443` as the server address.

Don't try to put BVC behind nginx/Caddy as an HTTP reverse proxy. It needs end-to-end TLS with client certificates and UDP.

## Reporting a problem

Before asking upstream ([Discord](https://discord.gg/CdtchD5zxr) / [GitHub issues](https://github.com/Alaydriem/bedrock-voice-chat/issues)), collect:

- output of `curl https://yourname.duckdns.org/api/config`
- whether UDP 28280 is open (ufw + provider firewall)
- that you run it with Docker (this repo), `BVC_VERSION`, and that the world is on a Realm (no-net addon)
- relevant lines from `docker compose logs`
- what you already tried

Problems with *this repo's* scripts/docs: open an issue here.
