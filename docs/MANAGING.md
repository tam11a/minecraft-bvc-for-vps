# Managing without SSH: BVC app and web portal

After the one-time setup in [DEPLOY.md](../DEPLOY.md), you don't need to log in to the VPS. Everything is done from:

| Where | What you do there |
|---|---|
| **BVC app** (as admin) | Add players, give/remove admin and other permissions |
| **Web portal** (`https://<your-hostname>:8443`) | Update BVC, restart, read logs, edit settings, run admin commands |
| **Automatic** (cron, installed by `setup.sh`) | Certificate renewal, nightly backups |

---

## Contents

- [What runs automatically](#what-runs-automatically)
- [In the BVC app](#in-the-bvc-app)
- [In the web portal](#in-the-web-portal)
- [Task cheat sheet](#task-cheat-sheet)
- [Securing the portal](#securing-the-portal)
- [When you still need SSH](#when-you-still-need-ssh)

---

## What runs automatically

`setup.sh` installs these cron jobs (tagged `# bvc-managed` in root's crontab):

| Job | When | Notes |
|---|---|---|
| `cert.sh` (option A) | Daily 03:30 | Renews the DuckDNS certificate when < 30 days are left; restarts BVC and the portal only if it changed. Log: `lego/renew.log`. |
| Portal reload (option B) | Mondays 04:15 | BVC renews its own certificate; this makes the portal pick up the new file. |
| `backup.sh` | Daily 04:00 | Snapshot of `data/` to `backups/`, newest 14 kept. Log: `backups/backup.log`. |

Containers restart by themselves after crashes and VPS reboots.

---

## In the BVC app

You need admin once. If you followed DEPLOY.md you already have it. Otherwise run `bvc-server admin bootstrap -p YourGamertag -g minecraft` in the [portal terminal](#run-bvc-admin-commands-terminal).

Open **Settings → Manage Players**:

| Task | How |
|---|---|
| **Add a player** | Add them by their exact Xbox gamertag. They can then sign in with their Microsoft account (no code needed). On a Realm, add players **before** they try to sign in, or they get `AUTH02`. |
| **Make someone admin** (co-owner) | Settings icon on their row → **admin** → Allow. They can then manage players too. |
| **Remove admin / permissions** | Same place → Deny, or **Default** to fall back to the server default. |
| **Audio library upload/delete** | Same place: `audio_upload`, `audio_delete`. |

Banning a player (`user banish`) is documented as a command. If the app doesn't offer it, use the [portal terminal](#run-bvc-admin-commands-terminal).

---

## In the web portal

The portal is [Dockge](https://github.com/louislam/dockge), a web UI for Docker Compose, served over HTTPS with the voice server's own certificate.

### Open it

`https://<your-hostname>:8443`, e.g. `https://mycraftvoice.duckdns.org:8443`. Log in with the portal account you created during setup.

You'll see the **bvc** stack. Click it.

### Update BVC to a new version

Do this when a new BVC release is out (e.g. after a Minecraft update).

1. Check the release notes and [upgrade notes](https://www.bedrockvoicechat.com/wiki/upgrading/).
2. Click **Edit**. In the **.env** box, change `BVC_VERSION=1.0.0-beta.23` to the new version.
3. **Save**, then click **Update**. It pulls the new image and recreates the container.
4. Watch the log panel for errors (migrations run on start).
5. Update the no-net addon in the Realm world and tell players to update their app ([DEPLOY.md, upgrading](../DEPLOY.md#upgrading-bvc)).

A backup runs every night at 04:00, so upgrading the morning after means you have a fresh one. An extra on-demand backup needs SSH (`bash backup.sh`).

### Restart / stop / start

Buttons on the stack page. **Restart** keeps the current settings. After editing `.env`, use **Save** then **Deploy** (or **Update**) so the container is recreated with the new values.

### Read logs

The stack page shows the live container log. Look for `TLS demultiplexer listening … listen=[::]:443` after a start, and for `error` lines.

### Change settings

- **`.env` settings** (version, hostname, any documented [`BVC_*` variable](https://www.bedrockvoicechat.com/wiki/reference/environment-variables/)): **Edit → .env → Save → Deploy**. Useful ones:

  | Variable | Effect |
  |---|---|
  | `BVC_MAX_CONNECTIONS=10` | Max simultaneous voice sessions (0 = unlimited) |
  | `BVC_RECORDING=false` | Stop players' apps from recording |
  | `BVC_CHAT=false` | Turn off in-game chat sync in the app |
  | `BVC_RADAR=false` | Hide out-of-range players on the dashboard ring |

- **`config.hcl` settings** without an env variable (e.g. voice range `broadcast_range`): open the [terminal](#run-bvc-admin-commands-terminal) and run `vi /data/config.hcl`, then restart the stack.

### Run BVC admin commands (terminal)

On the stack page, open the **terminal** for the `bvc` service. If it says bash isn't found, switch the shell to **sh** (the BVC image only has `sh`). You're now inside the voice server, in `/data`:

| Task | Command |
|---|---|
| One-time login code for a player | `bvc-server admin generate-code -p Gamertag -g minecraft -d 86400` |
| Make someone admin | `bvc-server admin bootstrap -p Gamertag -g minecraft` |
| Edit config | `vi /data/config.hcl` (then restart the stack) |

The `admin …` commands above talk to the database directly and always work here (tested).

**Banning** uses `user banish`, which goes through the server's API and needs a logged-in admin identity ([CLI reference](https://www.bedrockvoicechat.com/wiki/reference/cli/)). Set it up once in the same terminal, keeping the identity on the persistent volume:

```sh
export BVC_IDENTITY_DIR=/data/.identity
bvc-server admin generate-code -p YourGamertag -g minecraft
bvc-server login --server-url https://<your-hostname> --code <code-from-above>
bvc-server user banish -p Gamertag -g minecraft             # ban
bvc-server user banish -p Gamertag -g minecraft --banish false   # unban
```

Next time, only the `export` line and the `user banish` command are needed. (This flow follows the upstream CLI docs; it can't be tested without a real certificate.)

---

## Task cheat sheet

| I want to… | Use |
|---|---|
| Add a friend | App → Manage Players |
| Give a friend admin | App → Manage Players → admin → Allow |
| Send someone a login code | Portal terminal → `admin generate-code` |
| Ban someone | Portal terminal → `user banish` (see above) |
| Update after a Minecraft/BVC update | Portal → Edit `.env` `BVC_VERSION` → Update |
| See why voice is broken | Portal → logs; then [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| Change voice range | Portal terminal → `vi /data/config.hcl` → restart |
| Limit players / disable recording | Portal → Edit `.env` → `BVC_MAX_CONNECTIONS` / `BVC_RECORDING` → Deploy |
| Renew certificate | Automatic |
| Back up | Automatic (nightly) |

---

## Securing the portal

The portal can control Docker, so whoever logs in has **full control of the VPS**. Treat its password like the server's root password.

- **Create the account immediately** after first starting the portal; until then, the first visitor can create it.
- Use a **long, unique password** (password manager).
- **Restrict who can reach it** (recommended if your home IP is stable):
  ```bash
  ufw delete allow 8443/tcp && ufw allow from <your-home-ip> to any port 8443 proto tcp
  ```
  Or open 8443 only for your IP in the provider's cloud firewall, which you can change from the provider's website without SSH.
- **Close it when you don't need it:** block 8443 in the provider's cloud firewall and open it only while you use the portal.
- The portal's own *console* (a shell on the host) is **disabled** in this setup. Only container terminals are available.
- Keep it updated: when a new Dockge version is out, bump the tag in `portal/compose.yaml` (needs SSH, rare).

---

## When you still need SSH

- First-time setup ([DEPLOY.md](../DEPLOY.md) Phases 2–4).
- Restoring a backup, or copying backups off the VPS (`scp`).
- Changing `portal/compose.yaml` itself (portal version, port, option B certificate lines).
- Running `cert.sh` manually if a renewal keeps failing.
- Anything that breaks the portal itself.
