# Deployment guide

From an empty VPS to friends talking in your Realm. The server part is **one command** (`install.sh`).
After that you manage everything from the BVC app and a web portal ([docs/MANAGING.md](docs/MANAGING.md)).

> Replace `mycraftvoice.duckdns.org` (or `voice.example.com`) with your own hostname and `YourGamertag` with real Xbox gamertags.

---

## Contents

- [Before you start: checklist](#before-you-start-checklist)
- [Choose a hostname: DuckDNS or your own domain](#choose-a-hostname-duckdns-or-your-own-domain)
- [Phase 1: VPS and hostname](#phase-1-vps-and-hostname)
- [Phase 2: Prepare the VPS](#phase-2-prepare-the-vps)
- [Phase 3: Install (one command)](#phase-3-install-one-command)
- [Phase 4: Portal account and players](#phase-4-portal-account-and-players)
- [Phase 5: Put the addon on the Realm](#phase-5-put-the-addon-on-the-realm)
- [Phase 6: Day-2 operations](#phase-6-day-2-operations)
- [Final checklist](#final-checklist)

---

## Before you start: checklist

| You need | Why |
|---|---|
| A Linux VPS with a public IPv4 (Ubuntu 22.04/24.04 assumed), root access | Runs the voice server in Docker |
| A hostname: a **free DuckDNS name** or your own domain | BVC refuses bare IPs and self-signed certificates |
| A Minecraft Realm you own (Bedrock) | Where the world runs |
| Minecraft Bedrock on a PC/phone (you, the owner) | To build the world with the addon and upload it |
| Every player: the BVC app ([downloads](https://www.bedrockvoicechat.com/wiki/start/downloads/)) | The app is what connects the Realm to voice |

Check that the Realm's Minecraft version is on the [supported versions list](https://www.bedrockvoicechat.com/wiki/platforms/version-support/). If it isn't, voice won't work until BVC catches up.

---

## Choose a hostname: DuckDNS or your own domain

BVC **requires a hostname with a publicly trusted certificate**. The app checks it like a browser does; a bare IP or self-signed certificate is refused. You don't need to buy a domain:

| | Option A: DuckDNS (recommended) | Option B: own domain on Cloudflare |
|---|---|---|
| Cost | Free | Domain price |
| Hostname | `mycraftvoice.duckdns.org` | `voice.example.com` |
| DNS setup | None: the installer points the name at the VPS | A record on Cloudflare |
| Certificate | Obtained and renewed automatically (lego + cron) | Obtained and renewed automatically (BVC built-in) |
| Reliability | Depends on DuckDNS (free service, occasional outages) | Depends on Cloudflare |

> **Not suitable:** `sslip.io`/`nip.io` (Let's Encrypt rate limits are shared with every user worldwide) and BVC's own *assigned hostnames*, which are unreleased and limited to some Patreon/YouTube members.

---

## Phase 1: VPS and hostname

### VPS

1. Create a VPS at any provider (Hetzner, DigitalOcean, OVH, Vultr…).
   - **Size:** about 1 vCPU / 512 MB RAM per ~5 concurrent speakers. 1 vCPU / 1 GB is a comfortable start for a small Realm. If audio stutters later, add CPU or switch to a dedicated-CPU plan.
   - **Location:** close to your players (lower voice latency).
   - **OS:** Ubuntu 24.04 LTS.
2. Add your SSH key during creation and note the **public IPv4 address**.
3. If the provider has a **cloud firewall**, allow:

   | Port | Protocol | Purpose |
   |---|---|---|
   | 22 | TCP | SSH |
   | 443 | TCP | Login, HTTP API, WebSocket voice fallback |
   | 28280 | UDP | Voice (QUIC) |
   | 8443 | TCP | Web portal. Ideally only from your own IP; see [Securing the portal](docs/MANAGING.md#securing-the-portal). |

Port 80 is **not** needed. Port 443 must be free on the VPS; if you already run a website there, read [Port 443 is already taken](docs/TROUBLESHOOTING.md#port-443-is-already-taken) first.

### Hostname

**Option A (DuckDNS):** go to <https://www.duckdns.org>, sign in (GitHub, Google, Reddit…), add a subdomain (e.g. `mycraftvoice`), and copy the **token** shown at the top. No IP needed; the installer sets it.

**Option B (Cloudflare):**
1. Put the domain on Cloudflare (free plan) and switch the nameservers at your registrar.
2. **DNS → Add record:** `A`, name `voice`, content `<VPS IPv4>`, proxy status **DNS only** (grey cloud). Cloudflare's orange-cloud proxy doesn't carry UDP voice.
3. **My Profile → API Tokens → Create Token → Edit zone DNS** template, limited to that zone. Copy the token. Never use the Global API Key.

---

## Phase 2: Prepare the VPS

SSH in:

```bash
ssh root@<VPS IPv4>
```

Update the system and install git:

```bash
apt update && apt upgrade -y && apt install -y git curl ufw
```

Turn on the firewall. Allow SSH **first**, or you'll lock yourself out:

```bash
ufw allow OpenSSH && ufw enable
```

Docker doesn't need to be installed yet; the installer does it if it's missing.

---

## Phase 3: Install (one command)

Clone the repository to **`/opt/stacks/bvc`** (the web portal requires exactly this path):

```bash
git clone https://github.com/tam11a/minecraft-bvc-for-vps.git /opt/stacks/bvc
```

Run the installer:

```bash
cd /opt/stacks/bvc && sudo bash install.sh
```

It asks:

| Question | Option A answer | Option B answer |
|---|---|---|
| Choose 1 or 2 | `1` | `2` |
| Subdomain / hostname | `mycraftvoice` | `voice.example.com` |
| Token (hidden while typing) | DuckDNS token | Cloudflare API token |
| Email for Let's Encrypt | your email | your email |
| Your Xbox gamertag | to make you BVC admin (Enter to skip) | same |

Then it does everything else, showing each step:

1. Installs Docker if missing.
2. Writes `.env` (your settings; never committed to git).
3. Sets file ownership for the container user (uid 100).
4. Opens 443/tcp, 28280/udp and 8443/tcp in ufw.
5. Installs cron jobs: certificate renewal (option A, daily), nightly backups, portal reload (option B, weekly).
6. Gets the certificate (option A; option B gets it on start).
7. Starts the voice server, waits until it's healthy, then starts the web portal.
8. Makes you BVC admin and prints a one-time login code.

It ends with your **voice server address** (`https://mycraftvoice.duckdns.org`) and **portal address** (`https://mycraftvoice.duckdns.org:8443`).

If a step fails, the installer stops with a message saying what to fix. Fix it and run `sudo bash install.sh` again; it keeps your answers and only redoes what's needed.

**Check from your own PC** (optional):

```bash
curl https://mycraftvoice.duckdns.org/api/config
```

JSON means the server, certificate and port 443 are fine. UDP 28280 can't be tested with curl. If players can sign in but hear nothing later, see [troubleshooting](docs/TROUBLESHOOTING.md#sign-in-works-but-nobody-hears-anything).

---

## Phase 4: Portal account and players

### Portal account: do this immediately

Open `https://mycraftvoice.duckdns.org:8443` and **create the portal admin account right away** with a long, unique password. Until you do, anyone who opens the page could create it, and the portal controls the whole VPS. You should see the **bvc** stack listed.

Then, if your home IP is stable, allow 8443 only from it: [Securing the portal](docs/MANAGING.md#securing-the-portal).

### You in the BVC app

Install the [BVC app](https://www.bedrockvoicechat.com/wiki/start/downloads/), enter `https://mycraftvoice.duckdns.org`, and sign in with your Microsoft account (or the code the installer printed). You're admin.

**You can log out of SSH now.** 🎉

### Add players

A Realm can't tell BVC who your players are, so **add each player before they sign in** (otherwise they get `AUTH02`):

BVC app → **Settings → Manage Players** → add their exact Xbox gamertag.

Send them the server address and the [player guide](docs/PLAYER-GUIDE.md). Everything else you'll do day to day is in [docs/MANAGING.md](docs/MANAGING.md).

---

## Phase 5: Put the addon on the Realm

The standard addon can't run on Realms. Use the **no-net** addon.

### 5.1 Download

From [GitHub Releases](https://github.com/Alaydriem/bedrock-voice-chat/releases), open the release tagged `mods-v<BVC_VERSION>` (e.g. `mods-v1.0.0-beta.23`) and download:

```
bvc-bds-pack-no-net-<version>.mcaddon
```

Don't use `bvc-bds-pack-<version>.mcaddon` without "no-net". That one is for your own dedicated server and does not work on Realms.

### 5.2 Build the world

On the PC/phone with Minecraft Bedrock:

1. Double-click the `.mcaddon` to import it into Minecraft.
2. **Create New World.**
3. **Behavior Packs** → activate **Bedrock Voice Chat (Realms + No-Net Servers)**.
4. **Experiments** → turn on **Beta APIs**.
5. Create the world, then exit it right away.

**Using an existing world instead?** Back it up (export it) first, then in its settings activate the same behavior pack and turn on Beta APIs. The official guide only describes new worlds.

### 5.3 Upload to the Realm

1. Minecraft → **Play → Realms** → your Realm → ✏️ **Edit Realm → Replace World**.
2. Pick the world from 5.2 and wait for the upload to finish.
3. Leave the Realm.

### 5.4 Test

Follow the [player guide](docs/PLAYER-GUIDE.md) yourself with a second person, joining from the **Worlds** tab. Watch the bvc stack's log in the portal for errors.

---

## Phase 6: Day-2 operations

Day to day, use the **BVC app** and the **web portal**. See [docs/MANAGING.md](docs/MANAGING.md). This section covers what runs automatically and the few SSH-only tasks.

### Automatic

| Job | Schedule | Notes |
|---|---|---|
| Certificate renewal (option A) | Daily 03:30 | `cert.sh` renews when < 30 days left; restarts BVC + portal only if it changed. Log: `lego/renew.log`. |
| Certificate renewal (option B) | Built into BVC | A weekly cron job reloads the portal so it picks up the new file. |
| Backups | Nightly 04:00 | `backup.sh`: `backups/bvc-data-<timestamp>.tar.gz`, newest 14 kept. Log: `backups/backup.log`. |
| Restarts | Always | Containers come back after crashes and reboots. |

See the jobs with `crontab -l` (tagged `# bvc-managed`).

### Backups

`data/bvc.sqlite3` holds the **certificate authority for every player login**. Lose it and every player has to be re-added and signed in again. Copy backups **off the VPS** now and then (e.g. `scp root@<VPS>:/opt/stacks/bvc/backups/*.tar.gz .`).

Extra backup on demand (SSH):

```bash
cd /opt/stacks/bvc && bash backup.sh
```

**Restore** (SSH). Stop the server:

```bash
cd /opt/stacks/bvc && docker compose down
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
2. **Portal:** bvc stack → Edit → set the new `BVC_VERSION` in `.env` → Save → **Update** ([details](docs/MANAGING.md#update-bvc-to-a-new-version)).
3. Check the log (database migrations run on start).
4. Rebuild the Realm world with the matching `bvc-bds-pack-no-net-<version>.mcaddon` ([Phase 5](#phase-5-put-the-addon-on-the-realm)).
5. Tell players to update the app.

### When Mojang updates Minecraft

Realms update automatically. The no-net addon is tied to one Bedrock protocol version, so **voice stops working on the day of a Minecraft update** until BVC ships support (check [version support](https://www.bedrockvoicechat.com/wiki/platforms/version-support/)). Then do the upgrade above.

### Updating this repo

To get newer scripts/docs from this repository (SSH):

```bash
cd /opt/stacks/bvc && git pull && sudo bash install.sh
```

Your `.env`, `data/` and backups are not touched by `git pull` (they're git-ignored).

### Useful SSH commands

Run from `/opt/stacks/bvc`. Most have portal equivalents.

| Task | Command |
|---|---|
| Re-run / repair the setup | `sudo bash install.sh` |
| Status / health | `docker compose ps` |
| Live logs | `docker compose logs -f` |
| Apply `.env` changes | `docker compose up -d --force-recreate` |
| Restart after editing `config.hcl` | `docker compose restart` |
| Add a player + login code | `bash add-player.sh <Gamertag>` |
| Give admin | `docker compose exec bvc bvc-server admin bootstrap -p <Gamertag> -g minecraft` |
| Renew certificate now (option A) | `bash cert.sh` |
| Restart the web portal | `docker restart bvc-portal` |
| Debug logging | set `level = "debug"` in `data/config.hcl`, then restart |

`docker compose restart` re-reads `config.hcl` but **not** `.env`. After changing `.env`, recreate (`up -d --force-recreate`, or **Deploy** in the portal).

### Uninstall

```bash
cd /opt/stacks/bvc && docker compose down && docker compose -f portal/compose.yaml down
```

```bash
crontab -l | grep -v '# bvc-managed' | crontab -
```

Then delete `/opt/stacks/bvc` (back up `data/` first if you might come back), and delete the DuckDNS subdomain or the DNS record + Cloudflare token.

---

## Final checklist

- [ ] Hostname resolves to the VPS; Cloudflare record is **grey cloud** (option B)
- [ ] 443/tcp, 28280/udp and 8443/tcp open in ufw **and** the provider firewall
- [ ] `sudo bash install.sh` finished with **Done 🎉**
- [ ] Portal account created immediately; 8443 ideally limited to your IP
- [ ] You're admin in the BVC app; players added via **Manage Players**
- [ ] Realm world has the **no-net** pack + Beta APIs, same version as `BVC_VERSION`
- [ ] Two people tested: joined via the **Worlds** tab and can hear each other
- [ ] Backups occasionally copied off the VPS
