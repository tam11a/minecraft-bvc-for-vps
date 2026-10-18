# Deployment guide

A step-by-step guide from an empty VPS to friends talking in your Realm. Follow the phases in order.
Most of it is a one-time setup, about 30–60 minutes. [Phase 7](#phase-7-day-2-operations) covers upkeep.

> Throughout this guide, replace `yourname.duckdns.org` (or `voice.example.com`) with your own hostname and `YourGamertag` with real Xbox gamertags.

---

## Contents

- [Before you start: checklist](#before-you-start-checklist)
- [Choose a hostname: DuckDNS or your own domain](#choose-a-hostname-duckdns-or-your-own-domain)
- [Phase 1: Get a VPS](#phase-1-get-a-vps)
- [Phase 2: Prepare the VPS](#phase-2-prepare-the-vps)
- [Phase 3: Install and configure](#phase-3-install-and-configure)
- [Phase 4: Certificate and start](#phase-4-certificate-and-start)
- [Phase 5: Admin and players](#phase-5-admin-and-players)
- [Phase 6: Put the addon on the Realm](#phase-6-put-the-addon-on-the-realm)
- [Phase 7: Day-2 operations](#phase-7-day-2-operations)
- [Final checklist](#final-checklist)

---

## Before you start: checklist

| You need | Why |
|---|---|
| A Linux VPS with a public IPv4 (Ubuntu 22.04/24.04 assumed) | Runs the voice server in Docker |
| A hostname: a **free DuckDNS name** or your own domain | BVC refuses bare IPs and self-signed certificates |
| A Minecraft Realm you own (Bedrock) | Where the world runs |
| Minecraft Bedrock on a PC/phone (you, the owner) | To build the world with the addon and upload it |
| Every player: the BVC app ([downloads](https://www.bedrockvoicechat.com/wiki/start/downloads/)) | The app is what connects the Realm to voice |

Also check that the Realm's Minecraft version is on the [supported versions list](https://www.bedrockvoicechat.com/wiki/platforms/version-support/). If it isn't, voice won't work until BVC catches up.

---

## Choose a hostname: DuckDNS or your own domain

BVC **requires a hostname with a publicly trusted certificate**. The app checks it like a browser does, and a bare IP or self-signed certificate is refused. You don't need to buy a domain, though:

| | Option A: DuckDNS (default) | Option B: own domain on Cloudflare |
|---|---|---|
| Cost | Free | Domain price |
| Hostname | `yourname.duckdns.org` | `voice.example.com` |
| DNS setup | None: `cert.sh` points the name at the VPS | A record on Cloudflare |
| Certificate | `cert.sh` (lego) gets it; daily cron renews it and restarts BVC | BVC gets and renews it itself |
| Reliability | Depends on DuckDNS (free service, occasional outages) | Depends on Cloudflare |

> **Not suitable:** `sslip.io`/`nip.io` (Let's Encrypt rate limits are shared with every user worldwide) and BVC's own *assigned hostnames*, which are unreleased and limited to some Patreon/YouTube members.

Pick one. The phases below have A and B steps where they differ.

---

## Phase 1: Get a VPS

1. Create a VPS at any provider (Hetzner, DigitalOcean, OVH, Vultr…).
   - **Size:** about 1 vCPU / 512 MB RAM per ~5 concurrent speakers. 1 vCPU / 1 GB is a comfortable start for a small Realm. If audio stutters later, add CPU or switch to a dedicated-CPU plan.
   - **Location:** close to your players (lower voice latency).
   - **OS:** Ubuntu 24.04 LTS.
2. Add your SSH key during creation.
3. Write down the **public IPv4 address**.

> Port 443 must be free on this VPS. If you already run a website on it, read [Port 443 is already taken](docs/TROUBLESHOOTING.md#port-443-is-already-taken) first.

### Get your hostname

**Option A (DuckDNS):**
1. Go to <https://www.duckdns.org> and sign in (GitHub, Google, Reddit…).
2. Under **domains**, add a subdomain, e.g. `mycraftvoice` → `mycraftvoice.duckdns.org`. You don't need to enter the IP; `cert.sh` sets it later.
3. Copy the **token** shown at the top of the page.

**Option B (own domain on Cloudflare):**
1. Put the domain on Cloudflare (free plan) and switch the nameservers at your registrar.
2. **DNS → Add record:** `A`, name `voice`, content `<VPS IPv4>`, proxy status **DNS only** (grey cloud). Cloudflare's orange-cloud proxy doesn't carry UDP voice.
3. **My Profile → API Tokens → Create Token → Edit zone DNS** template, limited to that zone. Copy the token. Never use the Global API Key.

---

## Phase 2: Prepare the VPS

SSH in:

```bash
ssh root@<VPS IPv4>
```

Update the system and install the tools:

```bash
apt update && apt upgrade -y && apt install -y git curl ufw
```

Install Docker (official convenience script, includes the Compose plugin):

```bash
curl -fsSL https://get.docker.com | sh
```

Check it works:

```bash
docker compose version
```

**Firewall.** Allow SSH *before* enabling ufw, or you'll lock yourself out:

```bash
ufw allow OpenSSH && ufw enable
```

If your provider also has a **cloud firewall** (Hetzner Firewall, DigitalOcean Cloud Firewall, AWS Security Group…), open these there too:

| Port | Protocol | Purpose |
|---|---|---|
| 22 | TCP | SSH |
| 443 | TCP | Login, HTTP API, WebSocket voice fallback |
| 28280 | UDP | Voice (QUIC) |

Port 80 is **not** needed: both certificate options use DNS validation.

---

## Phase 3: Install and configure

Clone the repository to `/opt/bvc`:

```bash
git clone https://github.com/tam11a/minecraft-bvc-for-vps.git /opt/bvc
```

```bash
cd /opt/bvc
```

Run the setup script. It creates `.env`, makes `./data` writable for the container user (uid 100, gid 101) and opens 443/tcp + 28280/udp in ufw:

```bash
bash setup.sh
```

Edit `.env`:

```bash
nano .env
```

**Option A (DuckDNS):** set these and leave the option B lines empty:

| Variable | Value |
|---|---|
| `BVC_DOMAIN` | `mycraftvoice.duckdns.org` |
| `DUCKDNS_TOKEN` | The token from duckdns.org |
| `CERT_EMAIL` | Your email (Let's Encrypt expiry notices) |
| `BVC_TLS_CERTIFICATE` / `BVC_TLS_KEY` | Leave the defaults |

**Option B (Cloudflare):** **empty** the four option A lines (`DUCKDNS_TOKEN`, `CERT_EMAIL`, `BVC_TLS_CERTIFICATE`, `BVC_TLS_KEY`), then set:

| Variable | Value |
|---|---|
| `BVC_DOMAIN` | `voice.example.com` |
| `BVC_ACME_PROVIDER` | `cloudflare` |
| `BVC_ACME_EMAIL` | Your email |
| `BVC_ACME_API_TOKEN` | The Cloudflare token |

Leave `BVC_VERSION` as is unless you're upgrading. It must match the players' app and the Realm addon. Save with Ctrl+O, Enter, then exit with Ctrl+X.

> Setting both options makes the server refuse to start. Only one certificate source may be configured.

---

## Phase 4: Certificate and start

### Option A: get the certificate first

```bash
bash cert.sh
```

It points `yourname.duckdns.org` at this VPS, gets a Let's Encrypt certificate via the DuckDNS API (takes about a minute), and installs it in `data/tls/`. Then start:

```bash
docker compose up -d
```

### Option B: just start

BVC requests the certificate itself on first start (about 1–2 minutes):

```bash
docker compose up -d
```

> Testing option B a lot? Add `BVC_ACME_DIRECTORY=https://acme-staging-v02.api.letsencrypt.org/directory` to `.env` to avoid Let's Encrypt rate limits, then remove it for real use, because the apps reject staging certificates.

### Check it

Watch the logs (Ctrl+C stops following):

```bash
docker compose logs -f
```

A good start ends with `TLS demultiplexer listening … listen=[::]:443`. Errors name the problem (missing certificate file, ACME failure, both TLS options set…).

After about a minute the container should show **healthy**:

```bash
docker compose ps
```

From your **own PC** (not the VPS):

```bash
curl https://yourname.duckdns.org/api/config
```

| Result | Meaning |
|---|---|
| JSON | Running, certificate valid, 443 reachable ✅ |
| Connection refused | Container not running, or port not published |
| Timeout | Firewall (ufw or provider firewall) |
| Certificate error | Certificate missing / wrong hostname. Check logs. |

UDP 28280 can't be tested with curl. If players can sign in but hear nothing, UDP is the cause. See [troubleshooting](docs/TROUBLESHOOTING.md#sign-in-works-but-nobody-hears-anything).

---

## Phase 5: Admin and players

A Realm can't tell BVC who your players are, so **every player must be added**. Unknown players get `AUTH02` when signing in.

### 5.1 Make yourself admin

```bash
bash add-player.sh YourGamertag
```

```bash
docker compose exec bvc bvc-server admin bootstrap -p YourGamertag -g minecraft
```

The first command registers you and prints a one-time **login code** (valid 24 h). The second gives you admin.

### 5.2 Add each player

```bash
bash add-player.sh FriendGamertag
```

Send each player the server address (`https://yourname.duckdns.org`), their code and the [player guide](docs/PLAYER-GUIDE.md).

- Codes are single-use and expire after 24 h (pass a second argument in seconds to change that). Run the script again for a new one.
- Once added, players can also sign in with their Microsoft account instead of a code.
- Once you're signed in as admin, you can add players in the app too: **Settings → Manage Players**.

---

## Phase 6: Put the addon on the Realm

The standard addon can't run on Realms. Use the **no-net** addon.

### 6.1 Download the no-net addon

From [GitHub Releases](https://github.com/Alaydriem/bedrock-voice-chat/releases), open the release tagged `mods-v<BVC_VERSION>` (e.g. `mods-v1.0.0-beta.23`) and download:

```
bvc-bds-pack-no-net-<version>.mcaddon
```

Don't use `bvc-bds-pack-<version>.mcaddon` without "no-net". That one is for your own dedicated server and does not work on Realms.

### 6.2 Build the world

On the PC/phone with Minecraft Bedrock:

1. Double-click the `.mcaddon` to import it into Minecraft.
2. **Create New World.**
3. **Behavior Packs** → activate **Bedrock Voice Chat (Realms + No-Net Servers)**.
4. **Experiments** → turn on **Beta APIs**.
5. Create the world, then exit it right away.

**Using an existing world instead?** Back it up (export it) first, then in its settings activate the same behavior pack and turn on Beta APIs. The official guide only describes new worlds.

### 6.3 Upload to the Realm

1. Minecraft → **Play → Realms** → your Realm → ✏️ **Edit Realm → Replace World**.
2. Pick the world from 6.2 and wait for the upload to finish.
3. Leave the Realm.

### 6.4 First connection test

Follow the [player guide](docs/PLAYER-GUIDE.md) yourself with a second person. Then on the VPS:

```bash
docker compose logs --tail 100
```

You should see connection activity and no repeated errors.

---

## Phase 7: Day-2 operations

### Certificate renewal (option A only)

Let's Encrypt certificates last 90 days. Run `cert.sh` daily from cron. It only renews when fewer than 30 days are left and restarts BVC only when the certificate changed. Open the crontab:

```bash
crontab -e
```

Add this line:

```
30 3 * * * cd /opt/bvc && bash cert.sh >> lego/renew.log 2>&1
```

Option B needs nothing: BVC renews its own certificate.

### Backups

`./data/bvc.sqlite3` contains the **certificate authority for every player login**. Lose it and every player has to be re-added and signed in again.

Create a backup (stops the server for a few seconds, writes `backups/bvc-data-<timestamp>.tar.gz`, keeps the newest 14):

```bash
bash backup.sh
```

Nightly at 04:00 via cron:

```
0 4 * * * cd /opt/bvc && bash backup.sh >> backups/backup.log 2>&1
```

Copy backups **off the VPS** now and then (e.g. `scp` to your PC). A backup that lives only on the VPS is lost along with the VPS.

**Restore:**

```bash
docker compose down
```

```bash
sudo mv data data.before-restore
```

```bash
sudo tar -xzf backups/bvc-data-<timestamp>.tar.gz
```

```bash
docker compose up -d
```

### Upgrading BVC

The server, the Realm addon and every player's app must be on the **same BVC release**. Upgrade them together.

1. Read the release notes and the [upgrade notes](https://www.bedrockvoicechat.com/wiki/upgrading/).
2. Back up:
   ```bash
   bash backup.sh
   ```
3. Set the new `BVC_VERSION` in `.env`.
4. Pull and restart:
   ```bash
   docker compose pull && docker compose up -d
   ```
5. Check `docker compose logs` (database migrations run on start).
6. Rebuild/update the Realm world with the matching `bvc-bds-pack-no-net-<version>.mcaddon` (Phase 6).
7. Tell players to update the app.

### When Mojang updates Minecraft

Realms update automatically. The no-net addon is tied to one Bedrock protocol version, so **voice stops working on the day of a Minecraft update** until BVC ships support (check [version support](https://www.bedrockvoicechat.com/wiki/platforms/version-support/)). Then do the upgrade above.

### Useful commands

Run all of these from `/opt/bvc`.

| Task | Command |
|---|---|
| Status / health | `docker compose ps` |
| Live logs | `docker compose logs -f` |
| Restart (after editing `config.hcl` or `.env`) | `docker compose up -d --force-recreate` |
| Stop | `docker compose down` |
| Add a player | `bash add-player.sh <Gamertag>` |
| Give admin | `docker compose exec bvc bvc-server admin bootstrap -p <Gamertag> -g minecraft` |
| Renew certificate now (option A) | `bash cert.sh` |
| Debug logging | set `level = "debug"` in `data/config.hcl`, then restart |
| JSON log files | `./data/logs/` |

`docker compose restart` re-reads `config.hcl` but **not** `.env`. After changing `.env`, use `up -d --force-recreate`.

### Uninstall

```bash
docker compose down
```

Then delete `/opt/bvc` (back up `data/` first if you might come back), remove the cron lines, and delete the DuckDNS subdomain or the DNS record + Cloudflare token.

---

## Final checklist

- [ ] Hostname resolves to the VPS (`nslookup yourname.duckdns.org`); Cloudflare record is **grey cloud** (option B)
- [ ] 443/tcp and 28280/udp open in ufw **and** the provider firewall
- [ ] Only **one** TLS option filled in `.env`
- [ ] `docker compose ps` shows **healthy**
- [ ] `curl https://<hostname>/api/config` returns JSON from outside
- [ ] You're admin; every player added with `add-player.sh`
- [ ] Realm world has the **no-net** pack + Beta APIs, same version as `BVC_VERSION`
- [ ] Two people tested: joined via the **Worlds** tab and can hear each other
- [ ] Cron jobs: `cert.sh` daily (option A) and `backup.sh` nightly; backups copied off the VPS
