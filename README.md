# Minecraft Realm Proximity Voice Chat

**Self-host proximity voice chat for a Minecraft Bedrock Realm on your own VPS, with Docker Compose. No domain purchase needed.**

This repository is a ready-to-deploy setup for the [Bedrock Voice Chat](https://www.bedrockvoicechat.com) (BVC) server, aimed at **Minecraft Realms**: players hear each other based on in-game distance, on PC, mobile and console.

> **Unofficial.** This project only packages deployment config around the official BVC container image. It is not affiliated with or endorsed by Bedrock Voice Chat, Mojang or Microsoft. See [License](#license).

---

## Contents

- [How it works](#how-it-works)
- [Features](#features)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Documentation](#documentation)
- [Repository layout](#repository-layout)
- [Configuration](#configuration)
- [Known limitations](#known-limitations)
- [FAQ](#faq)
- [Contributing](#contributing)
- [License](#license)

---

## How it works

```
        ┌──────────────── Minecraft Realm (Mojang) ────────────────┐
        │  world with the BVC "no-net" behavior pack + Beta APIs    │
        └──────────────────────────▲───────────────────────────────┘
                                   │ game traffic
  Minecraft ── "Worlds" tab ──► BVC app on each player's device
  (PC / phone / console)          (Bedrock Voice Chat Connect)
                                   │ positions + voice
                                   │ 443/tcp (login, API, fallback) · 28280/udp (QUIC voice)
                                   ▼
                    ┌──────── Your VPS (this repo) ────────┐
                    │  Docker: BVC server                   │
                    │  Let's Encrypt cert (DuckDNS or       │
                    │  Cloudflare), SQLite DB in ./data     │
                    └───────────────────────────────────────┘
```

Realms can't make HTTP requests, so the Realm never talks to your server. Instead, each player's **BVC app**
runs a local relay (*Bedrock Voice Chat Connect*): Minecraft joins the relay from the **Worlds** tab, the
relay forwards traffic to the Realm, reads player positions from it, and sends them to your VPS, which mixes
voice by distance.

## Features

- 🐳 **One `docker compose up`.** Pinned official image, working healthcheck, auto-restart, log rotation.
- 🆓 **No domain required.** Free DuckDNS subdomain with automatic Let's Encrypt certificates (`cert.sh`), or your own domain on Cloudflare.
- 🔑 **No secrets in git.** Everything sensitive lives in `.env`.
- 👥 **Player helper.** `add-player.sh` registers a Realm player and prints their login code.
- 💾 **Backups.** `backup.sh` snapshots the database (which holds the login certificate authority).
- 📖 **Full docs.** [Deployment guide](DEPLOY.md), [player guide](docs/PLAYER-GUIDE.md), [troubleshooting](docs/TROUBLESHOOTING.md).

## Requirements

| | |
|---|---|
| **VPS** | Linux with Docker + Compose plugin, public IPv4. ~1 vCPU / 512 MB per 5 concurrent speakers. |
| **Hostname** | A free [DuckDNS](https://www.duckdns.org) name, or your own domain on Cloudflare. BVC rejects bare IPs and self-signed certificates. |
| **Ports** | `443/tcp` and `28280/udp` open on the VPS. Port 443 must be free. |
| **Realm** | Bedrock Realm you own, on a [BVC-supported version](https://www.bedrockvoicechat.com/wiki/platforms/version-support/). |
| **Players** | The [BVC app](https://www.bedrockvoicechat.com/wiki/start/downloads/) (Windows, macOS, Android, iOS; console players use a phone). |

## Quick start

For the full walkthrough (VPS, firewall, both TLS options, Realm world), see **[DEPLOY.md](DEPLOY.md)**.

Using a free DuckDNS name (create the subdomain and copy your token at [duckdns.org](https://www.duckdns.org) first). On the VPS:

```bash
git clone https://github.com/tam11a/minecraft-bvc-for-vps.git /opt/bvc && cd /opt/bvc
```

```bash
bash setup.sh
```

Set `BVC_DOMAIN`, `DUCKDNS_TOKEN` and `CERT_EMAIL` in `.env`:

```bash
nano .env
```

Get the certificate and start:

```bash
bash cert.sh && docker compose up -d
```

Register yourself and make yourself admin, then add players:

```bash
bash add-player.sh YourGamertag
```

```bash
docker compose exec bvc bvc-server admin bootstrap -p YourGamertag -g minecraft
```

```bash
bash add-player.sh FriendGamertag
```

Then upload a world with the **no-net** addon to your Realm ([DEPLOY.md, Phase 6](DEPLOY.md#phase-6-put-the-addon-on-the-realm)), schedule `cert.sh` and `backup.sh` in cron ([Phase 7](DEPLOY.md#phase-7-day-2-operations)), and share the [player guide](docs/PLAYER-GUIDE.md).

## Documentation

| Document | For | Covers |
|---|---|---|
| [DEPLOY.md](DEPLOY.md) | Server owner | Step-by-step deployment, certificates, backups, upgrades, Minecraft updates |
| [docs/PLAYER-GUIDE.md](docs/PLAYER-GUIDE.md) | Players | Install the app, sign in, join the Realm with voice |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Everyone | Diagnosing sign-in, audio and certificate problems |
| [Official BVC wiki](https://www.bedrockvoicechat.com/wiki/) | Everyone | Upstream reference |

## Repository layout

```
.
├── docker-compose.yml    # BVC server container (ports, volume, healthcheck)
├── .env.example          # Template for settings/secrets → copied to .env
├── data/
│   └── config.hcl        # BVC server config (hostname from .env)
├── setup.sh              # One-time VPS setup: .env, permissions, ufw
├── cert.sh               # Option A: DuckDNS IP update + certificate get/renew (lego)
├── add-player.sh         # Register a player + print a login code
├── backup.sh             # Snapshot ./data to ./backups
├── DEPLOY.md             # Deployment guide
├── docs/
│   ├── PLAYER-GUIDE.md
│   └── TROUBLESHOOTING.md
├── CONTRIBUTING.md
└── LICENSE
```

At runtime the server writes `data/bvc.sqlite3`, `data/certificates/` and `data/logs/`; `cert.sh` writes `data/tls/` and `lego/`. All of these are git-ignored.

## Configuration

### `.env`

| Variable | Option | Description |
|---|---|---|
| `BVC_VERSION` | both | Image tag, e.g. `1.0.0-beta.23`. Must match the Realm addon and players' app. |
| `BVC_DOMAIN` | both | Hostname players use, e.g. `yourname.duckdns.org` or `voice.example.com`. |
| `DUCKDNS_TOKEN` | A | DuckDNS account token. |
| `CERT_EMAIL` | A | Let's Encrypt account email. |
| `BVC_TLS_CERTIFICATE`, `BVC_TLS_KEY` | A | Certificate paths inside the container. Keep the defaults. |
| `BVC_ACME_PROVIDER` | B | `cloudflare`. |
| `BVC_ACME_EMAIL` | B | Let's Encrypt account email. |
| `BVC_ACME_API_TOKEN` | B | Cloudflare token, one zone, DNS edit. |

Fill in **one** option and leave the other's values empty; the server refuses to start with two certificate sources. BVC reads `BVC_*` variables directly ([environment variables reference](https://www.bedrockvoicechat.com/wiki/reference/environment-variables/)), so any other documented `BVC_*` setting can be added to `.env` too.

### `data/config.hcl`

Main options (full list in the [configuration reference](https://www.bedrockvoicechat.com/wiki/reference/configuration/)):

| Setting | Default here | Notes |
|---|---|---|
| `server.port` | `443` | TCP port. Change the compose port mapping too. |
| `server.quic_port` | `28280` | UDP voice port. If changed, also set `advertised_quic_ports` and the compose mapping. |
| `server.peering` | `false` | Linking multiple BVC servers; off, so UDP 28284 stays closed. |
| `server.tls.names` | `BVC_DOMAIN` | Hostname in the certificate. |
| `voice.spatial_audio.broadcast_range` | `48.0` | How far (blocks) voices carry. |
| `log.level` | `info` | `debug` for troubleshooting. |

The server reads `config.hcl` only at startup. Run `docker compose restart` after editing it.

## Known limitations

These come from how BVC works on Realms, not from this repo:

- **Minecraft updates pause voice.** Realms auto-update; the no-net addon supports one Bedrock protocol version, so voice stops until BVC releases support for the new version.
- **Everyone needs the BVC app**, on the same network as the device they play on.
- **Players must join via the Worlds tab** entry created by the app. Joining the Realm directly gives no voice.
- **Players must be added** (`add-player.sh` or the app's *Manage Players*) because a Realm can't register them.
- **Reconnect cooldown:** after leaving Connect, wait ~5 minutes before reconnecting.
- **Single instance.** Don't load-balance multiple BVC containers; scale up CPU instead.

Running your own Bedrock Dedicated Server with the full BVC addon removes most of these. The VPS side of this repo stays the same; see the [upstream addon guide](https://www.bedrockvoicechat.com/wiki/server/bedrock-addon/).

## FAQ

**Do I need to buy a domain?**
No. Use a free DuckDNS subdomain (option A). You do need *some* hostname: BVC requires a publicly trusted certificate, and it doesn't work with a bare IP.

**Why not just the VPS IP?**
The BVC docs state that a bare IP address does not work and that self-signed certificates are always refused. BVC's own free hostnames ("assigned hostnames") are not released yet and are limited to some supporters.

**Can I put it behind Cloudflare's proxy (orange cloud)?**
No. Voice uses UDP, which the Cloudflare HTTP proxy doesn't carry. Use *DNS only*.

**Does the Realm need my server address or a token?**
No. The players' apps do all the connecting. The Realm only needs the no-net behavior pack with Beta APIs on.

**Can console players use it?**
Yes. They run the BVC app on a phone on the same Wi-Fi, then pick the world under **Worlds** on the console.

**Something else already uses port 443 on my VPS.**
See [Port 443 is already taken](docs/TROUBLESHOOTING.md#port-443-is-already-taken).

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). Report problems with BVC itself (app, server, addon) [upstream](https://github.com/Alaydriem/bedrock-voice-chat/issues).

## License

- **This repository** (compose file, scripts, config templates, docs): [MIT](LICENSE).
- **Bedrock Voice Chat** (the container image, apps and addons this setup downloads) is a separate project by Charles R. Portwood II under its own [Clear Horizon Path License](https://github.com/Alaydriem/bedrock-voice-chat/blob/master/LICENSE.md). This repo does not redistribute any BVC code or binaries. You are responsible for complying with BVC's license, including its restrictions on commercial use and on offering BVC as a hosted/managed service. Before v1.0, the BVC license describes the software as for evaluation only. Read it before running a server.
- [lego](https://github.com/go-acme/lego) (used by `cert.sh` as a container) is MIT licensed.
- Minecraft is a trademark of Mojang Synergies AB / Microsoft. This project is not affiliated with them.

## Credits

- [Bedrock Voice Chat](https://www.bedrockvoicechat.com) by [Alaydriem](https://github.com/Alaydriem). All the actual voice chat magic. Consider [supporting the project](https://www.bedrockvoicechat.com/wiki/start/supporting-bvc/).
- [DuckDNS](https://www.duckdns.org) for free dynamic DNS.
