# Deployment guide

A step-by-step guide from an empty VPS to friends talking in your Realm. Follow the phases in order.
Most of it is a one-time setup, about 30–60 minutes. [Day-2 operations](#phase-7-day-2-operations) covers upkeep.

> Throughout this guide, replace `voice.example.com` with your own domain and `YourGamertag` with real Xbox gamertags.

---

## Contents

- [Before you start: checklist](#before-you-start-checklist)
- [Phase 1: Get a VPS](#phase-1-get-a-vps)
- [Phase 2: Domain and Cloudflare](#phase-2-domain-and-cloudflare)
- [Phase 3: Prepare the VPS](#phase-3-prepare-the-vps)
- [Phase 4: Install and start the voice server](#phase-4-install-and-start-the-voice-server)
- [Phase 5: Admin and players](#phase-5-admin-and-players)
- [Phase 6: Put the addon on the Realm](#phase-6-put-the-addon-on-the-realm)
- [Phase 7: Day-2 operations](#phase-7-day-2-operations)
- [Final checklist](#final-checklist)

---

## Before you start: checklist

| You need | Why |
|---|---|
| A Linux VPS with a public IPv4 (Ubuntu 22.04/24.04 assumed) | Runs the voice server in Docker |
| A domain name you control | BVC refuses bare IPs and self-signed certificates |
| A free Cloudflare account, with the domain's DNS on Cloudflare | Automatic Let's Encrypt certificates via DNS-01 (no port 80) |
| A Minecraft Realm you own (Bedrock) | Where the world runs |
| Minecraft Bedrock on a PC/phone (you, the owner) | To build the world with the addon and upload it |
| Every player: the BVC app ([downloads](https://www.bedrockvoicechat.com/wiki/start/downloads/)) | The app is what connects the Realm to voice |

Also check that the Realm's Minecraft version is on the [supported versions list](https://www.bedrockvoicechat.com/wiki/platforms/version-support/). If it isn't, voice won't work until BVC catches up.

---

## Phase 1: Get a VPS

1. Create a VPS at any provider (Hetzner, DigitalOcean, OVH, Vultr…).
   - **Size:** about 1 vCPU / 512 MB RAM per ~5 concurrent speakers. 1 vCPU / 1 GB is a comfortable start for a small Realm. If audio stutters later, add CPU or switch to a dedicated-CPU plan.
   - **Location:** close to your players (lower voice latency).
   - **OS:** Ubuntu 24.04 LTS.
2. Add your SSH key during creation.
3. Write down the **public IPv4 address**.

> Port 443 must be free on this VPS. If you already run a website on it, read [Port 443 is already taken](docs/TROUBLESHOOTING.md#port-443-is-already-taken) first.

---

## Phase 2: Domain and Cloudflare

### 2.1 Put the domain on Cloudflare

Skip this if your domain is already on Cloudflare.

1. Cloudflare dashboard → **Add a domain** → Free plan.
2. At your registrar, change the nameservers to the two Cloudflare gives you. This can take from minutes to a few hours.

### 2.2 DNS record for the voice server

Cloudflare → your domain → **DNS → Records → Add record**:

| Type | Name | Content | Proxy status |
|---|---|---|---|
| `A` | `voice` | `<VPS IPv4>` | **DNS only** (grey cloud) |

> **The grey cloud matters.** Cloudflare's proxy (orange cloud) only passes HTTP; voice uses UDP and will fail.

Check it resolves (from your PC):

```bash
nslookup voice.example.com
```

### 2.3 API token for certificates

1. Cloudflare → profile icon → **My Profile → API Tokens → Create Token**.
2. Use the **Edit zone DNS** template.
3. **Zone Resources:** Include → Specific zone → your domain.
4. Create it and copy the token. You'll put it in `.env` in Phase 4.

> Never use the Global API Key. It gives full control of your Cloudflare account.

---

## Phase 3: Prepare the VPS

SSH in:

```bash
ssh root@<VPS IPv4>
```

Update the system and install the tools:

```bash
apt update && apt upgrade -y && apt install -y git curl openssl ufw
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

---

## Phase 4: Install and start the voice server

### 4.1 Get the files

Clone this repository (or copy the folder with `scp`/WinSCP) to `/opt/bvc`:

```bash
git clone https://github.com/<you>/<this-repo>.git /opt/bvc
```

```bash
cd /opt/bvc
```

### 4.2 Run the setup script

```bash
bash setup.sh
```

It:
- creates `.env` from `.env.example`,
- generates `BVC_ACCESS_TOKEN`,
- makes `./data` writable for the container user (uid 100, gid 101),
- opens 443/tcp and 28280/udp in ufw.

### 4.3 Fill in `.env`

```bash
nano .env
```

| Variable | Set it to |
|---|---|
| `BVC_VERSION` | Leave as is unless you're upgrading. Must match the players' app and the Realm addon version. |
| `BVC_DOMAIN` | `voice.example.com` |
| `BVC_ACME_EMAIL` | Your email (Let's Encrypt expiry notices) |
| `CF_API_TOKEN` | The token from Phase 2.3 |
| `BVC_ACCESS_TOKEN` | Already generated. Realms don't use it, but the server requires it. |

Save (Ctrl+O, Enter) and exit (Ctrl+X).

> **Testing first?** To avoid Let's Encrypt rate limits while experimenting, uncomment the `directory = …staging…` line in `data/config.hcl`. Comment it out again before real use, because players' apps reject staging certificates.

### 4.4 Start

```bash
docker compose up -d
```

Watch the logs. The first start requests the certificate, which takes about 1–2 minutes:

```bash
docker compose logs -f
```

Press Ctrl+C to stop following. Look for errors about `acme`, `tls` or `config`. A missing `.env` value stops the server with an error naming it.

Check the container is **healthy**:

```bash
docker compose ps
```

### 4.5 Verify from outside

From your PC (not the VPS):

```bash
curl https://voice.example.com/api/config
```

| Result | Meaning |
|---|---|
| JSON | Running, certificate valid, 443 reachable ✅ |
| Connection refused | Container not running, or port not published |
| Timeout | Firewall (ufw or provider firewall) |
| Certificate error | Certificate not issued yet / wrong domain. Check logs. |

UDP 28280 can't be tested with curl. If players can sign in but hear nothing later, UDP is the cause. See [troubleshooting](docs/TROUBLESHOOTING.md#sign-in-works-but-nobody-hears-anything).

---

## Phase 5: Admin and players

A Realm can't tell BVC who your players are, so **every player must be added manually**. Unknown players get `AUTH02` when signing in.

### 5.1 Make yourself admin

```bash
bash add-player.sh YourGamertag
```

```bash
docker compose exec bvc bvc-server admin bootstrap -c /data/config.hcl -p YourGamertag -g minecraft
```

The first command prints a one-time **login code** (valid 24 h) for you.

### 5.2 Add each player

```bash
bash add-player.sh FriendGamertag
```

Send each player their code and the [player guide](docs/PLAYER-GUIDE.md).

- Codes are single-use and expire after 24 h. Run the script again for a new one.
- Once you're signed in as admin, you can also add players in the app: **Settings → Manage Players**.

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

### Backups

`./data/bvc.sqlite3` contains the **certificate authority for every player login**. Lose it and every player has to be re-added and signed in again.

Create a backup (stops the server for a few seconds, writes `backups/bvc-data-<timestamp>.tar.gz`):

```bash
bash backup.sh
```

Nightly at 04:00 via cron (`crontab -e`):

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
| Restart (after editing `config.hcl`) | `docker compose restart` |
| Stop | `docker compose down` |
| Add a player | `bash add-player.sh <Gamertag>` |
| Give admin | `docker compose exec bvc bvc-server admin bootstrap -c /data/config.hcl -p <Gamertag> -g minecraft` |
| Debug logging | set `level = "debug"` in `data/config.hcl`, then restart |
| JSON log files | `./data/logs/` |

### Uninstall

```bash
docker compose down
```

Then delete `/opt/bvc` (back up `data/` first if you might come back), and remove the DNS record and Cloudflare token.

---

## Final checklist

- [ ] `voice.example.com` A record → VPS IP, **grey cloud**
- [ ] Cloudflare token scoped to one zone, DNS edit
- [ ] 443/tcp and 28280/udp open in ufw **and** the provider firewall
- [ ] `.env` filled in; `docker compose ps` shows **healthy**
- [ ] `curl https://voice.example.com/api/config` returns JSON from outside
- [ ] You're admin; every player added with `add-player.sh`
- [ ] Realm world has the **no-net** pack + Beta APIs, same version as `BVC_VERSION`
- [ ] Two people tested: joined via the **Worlds** tab and can hear each other
- [ ] Backups scheduled and copied off the VPS
