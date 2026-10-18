# Minecraft Realm Proximity Voice Chat

**Self-host proximity voice chat for a Minecraft Bedrock Realm on your own VPS, in one Docker Compose file.**

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
                    │  Let's Encrypt cert via Cloudflare    │
                    │  SQLite DB in ./data                  │
                    └───────────────────────────────────────┘
```

Realms can't make HTTP requests, so the Realm never talks to your server. Instead, each player's **BVC app**
runs a local relay (*Bedrock Voice Chat Connect*): Minecraft joins the relay from the **Worlds** tab, the
relay forwards traffic to the Realm, reads player positions from it, and sends them to your VPS, which mixes
voice by distance.

## Features

- 🐳 **One `docker compose up`.** Pinned official image, healthcheck, auto-restart, log rotation.
- 🔒 **Automatic TLS.** Let's Encrypt via Cloudflare DNS-01; no port 80, auto-renewal.
- 🔑 **No secrets in git.** Everything sensitive lives in `.env`; `config.hcl` only references it.
- 👥 **Player helper.** `add-player.sh` registers a Realm player and prints their login code.
- 💾 **Backups.** `backup.sh` snapshots the database (which holds the login certificate authority).
- 📖 **Full docs.** [Deployment guide](DEPLOY.md), [player guide](docs/PLAYER-GUIDE.md), [troubleshooting](docs/TROUBLESHOOTING.md).

## Requirements

| | |
|---|---|
| **VPS** | Linux with Docker + Compose plugin, public IPv4. ~1 vCPU / 512 MB per 5 concurrent speakers. |
| **Domain** | Required. BVC rejects bare IPs and self-signed certificates. |
| **DNS** | Cloudflare (free) for automatic certificates. acme-dns or your own certificate also work. |
| **Ports** | `443/tcp` and `28280/udp` open on the VPS. Port 443 must be free. |
| **Realm** | Bedrock Realm you own, on a [BVC-supported version](https://www.bedrockvoicechat.com/wiki/platforms/version-support/). |
| **Players** | The [BVC app](https://www.bedrockvoicechat.com/wiki/start/downloads/) (Windows, macOS, Android, iOS; console players use a phone). |

## Quick start

For the full walkthrough (DNS, Cloudflare token, firewall, Realm world), see **[DEPLOY.md](DEPLOY.md)**.

On the VPS:

```bash
git clone https://github.com/<you>/<this-repo>.git /opt/bvc && cd /opt/bvc
```

```bash
bash setup.sh
```

Set `BVC_DOMAIN`, `BVC_ACME_EMAIL` and `CF_API_TOKEN` in `.env`:

```bash
nano .env
```

```bash
docker compose up -d
```

Make yourself admin, then add players:

```bash
bash add-player.sh YourGamertag
```

```bash
docker compose exec bvc bvc-server admin bootstrap -c /data/config.hcl -p YourGamertag -g minecraft
```

```bash
bash add-player.sh FriendGamertag
```

Then upload a world with the **no-net** addon to your Realm ([DEPLOY.md, Phase 6](DEPLOY.md#phase-6-put-the-addon-on-the-realm)) and share the [player guide](docs/PLAYER-GUIDE.md).

## Documentation

| Document | For | Covers |
|---|---|---|
| [DEPLOY.md](DEPLOY.md) | Server owner | Step-by-step deployment, backups, upgrades, Minecraft updates |
| [docs/PLAYER-GUIDE.md](docs/PLAYER-GUIDE.md) | Players | Install the app, sign in, join the Realm with voice |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Everyone | Diagnosing sign-in, audio and certificate problems |
| [Official BVC wiki](https://www.bedrockvoicechat.com/wiki/) | Everyone | Upstream reference |

## Repository layout

```
.
├── docker-compose.yml    # BVC server container (ports, volume, healthcheck)
├── .env.example          # Template for secrets/settings → copy to .env
├── data/
│   └── config.hcl        # BVC server config (reads values from .env)
├── setup.sh              # One-time VPS setup: .env, token, permissions, ufw
├── add-player.sh         # Register a player + print a login code
├── backup.sh             # Snapshot ./data to ./backups
├── DEPLOY.md             # Deployment guide
├── docs/
│   ├── PLAYER-GUIDE.md
│   └── TROUBLESHOOTING.md
├── CONTRIBUTING.md
└── LICENSE
```

At runtime the server also writes `data/bvc.sqlite3`, `data/certificates/` and `data/logs/`. These are git-ignored.

## Configuration

### `.env`

| Variable | Required | Description |
|---|---|---|
| `BVC_VERSION` | yes | Image tag, e.g. `1.0.0-beta.23`. Must match the Realm addon and players' app. |
| `BVC_DOMAIN` | yes | Domain pointing at the VPS (e.g. `voice.example.com`). |
| `BVC_ACME_EMAIL` | yes | Let's Encrypt account email. |
| `CF_API_TOKEN` | yes* | Cloudflare token, one zone, DNS edit. *Not needed with acme-dns / own cert. |
| `BVC_ACCESS_TOKEN` | yes | Required by the server; unused by Realms. `setup.sh` generates it. |

### `data/config.hcl`

Main options (full list in the [configuration reference](https://www.bedrockvoicechat.com/wiki/reference/configuration/)):

| Setting | Default here | Notes |
|---|---|---|
| `server.port` / `server.quic_port` | `443` / `28280` | Change both here and in `docker-compose.yml`. |
| `server.peering` | `false` | Linking multiple BVC servers; off, so UDP 28284 stays closed. |
| `server.tls.acme` | Cloudflare | acme-dns and own-certificate alternatives are commented in the file. |
| `voice.spatial_audio.broadcast_range` | `48.0` | How far (blocks) voices carry. |
| `log.level` | `info` | `debug` for troubleshooting. |

The server reads `config.hcl` only at startup. Run `docker compose restart` after editing it.

## Known limitations

These come from how BVC works on Realms, not from this repo:

- **Minecraft updates pause voice.** Realms auto-update; the no-net addon supports one Bedrock protocol version, so voice stops until BVC releases support for the new version.
- **Everyone needs the BVC app**, on the same network as the device they play on.
- **Players must join via the Worlds tab** entry created by the app. Joining the Realm directly gives no voice.
- **Players must be added manually** (`add-player.sh` or the app's *Manage Players*).
- **Reconnect cooldown:** after leaving Connect, wait ~5 minutes before reconnecting.
- **Single instance.** Don't load-balance multiple BVC containers; scale up CPU instead.

Running your own Bedrock Dedicated Server with the full BVC addon removes most of these. The VPS side of this repo stays the same; see the [upstream addon guide](https://www.bedrockvoicechat.com/wiki/server/bedrock-addon/).

## FAQ

**Can I use the VPS IP instead of a domain?**
No. BVC requires a fully qualified domain with a publicly trusted certificate.

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
- **Bedrock Voice Chat** (the container image, apps and addons this setup downloads) is a separate project by Charles R. Portwood II under its own [Clear Horizon Path License](https://github.com/Alaydriem/bedrock-voice-chat/blob/master/LICENSE). This repo does not redistribute any BVC code or binaries. You are responsible for complying with BVC's license, including its restrictions on commercial use and on offering BVC as a hosted/managed service. Before v1.0, the BVC license describes the software as for evaluation only. Read it before running a server.
- Minecraft is a trademark of Mojang Synergies AB / Microsoft. This project is not affiliated with them.

## Credits

- [Bedrock Voice Chat](https://www.bedrockvoicechat.com) by [Alaydriem](https://github.com/Alaydriem). All the actual voice chat magic. Consider [supporting the project](https://www.bedrockvoicechat.com/wiki/start/supporting-bvc/).
