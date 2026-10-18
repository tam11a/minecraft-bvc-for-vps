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
| Error naming an `env` variable | That variable is missing/empty in `.env`. |
| Permission denied on `/data/...` | Run `sudo chown -R 100:101 data`, then `docker compose restart`. |
| `address already in use` on 443 | Another service uses port 443. See [Port 443 is already taken](#port-443-is-already-taken). |
| Error mentioning `acme`, `cloudflare`, `dns` | See [Certificate problems](#certificate-problems). |
| Health `unhealthy` but logs fine | Certificate not issued yet (first start), or `BVC_DOMAIN` doesn't match the certificate. |

## 2. Is it reachable from the internet?

From your **own PC**, not the VPS:

```bash
curl https://voice.example.com/api/config
```

| Result | Cause |
|---|---|
| JSON | Server, TLS and 443/tcp are fine ✅ |
| Connection refused | Container down or port not published |
| Timeout | ufw or the provider's cloud firewall blocks 443/tcp |
| Certificate error | Certificate not issued / wrong name / staging directory still enabled |
| 404 or an HTML page | Something else answers on 443 (another web server, or Cloudflare proxy is on) |

Check that DNS points at the VPS, and that Cloudflare shows **DNS only** (grey cloud):

```bash
nslookup voice.example.com
```

## Certificate problems

- **Token permissions:** the Cloudflare token needs *Zone → DNS → Edit* on the zone containing `BVC_DOMAIN`.
- **Wrong zone:** `BVC_DOMAIN` must be inside the zone the token covers.
- **Rate limited:** after many failed attempts Let's Encrypt blocks you for a while. Test with the staging `directory` line in `data/config.hcl`, then switch back.
- **Staging left on:** apps reject staging certificates. Comment the `directory` line out and restart.
- **Self-signed / IP certificates** never work; BVC apps verify certificates like a browser.

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
   - healthcheck: `--resolve ${BVC_DOMAIN}:8443:127.0.0.1` and `https://${BVC_DOMAIN}:8443/health/readiness`
3. `sudo ufw allow 8443/tcp` (+ provider firewall)
4. `docker compose up -d`
5. Players use `voice.example.com:8443` as the server address.

Don't try to put BVC behind nginx/Caddy as an HTTP reverse proxy. It needs end-to-end TLS with client certificates and UDP.

## Reporting a problem

Before asking upstream ([Discord](https://discord.gg/CdtchD5zxr) / [GitHub issues](https://github.com/Alaydriem/bedrock-voice-chat/issues)), collect:

- output of `curl https://voice.example.com/api/config`
- whether UDP 28280 is open (ufw + provider firewall)
- that you run it with Docker (this repo), `BVC_VERSION`, and that the world is on a Realm (no-net addon)
- relevant lines from `docker compose logs`
- what you already tried

Problems with *this repo's* scripts/docs: open an issue here.
