# Player guide: proximity voice on our Realm

Players near you in-game sound close; players far away fade out. This guide gets you set up in about 5 minutes.

**From the server owner, you need:**
- the **voice server address**, e.g. `voice.example.com`
- a one-time **login code** (valid 24 hours; ask for a new one if it expired)

---

## 1. Install the BVC app

Download **Bedrock Voice Chat** for your device: <https://www.bedrockvoicechat.com/wiki/start/downloads/>

| You play on | Install the app on |
|---|---|
| Windows / Mac | The same computer |
| Android / iPhone / iPad | The same device |
| Xbox / PlayStation / Switch | A phone or tablet on the **same Wi-Fi** as the console (it becomes your mic and speaker) |

## 2. Sign in (first time only)

1. Open the app and choose to sign in to a server.
2. Enter the voice server address, e.g. `voice.example.com`.
3. Sign in with the **Xbox account you play Minecraft with** and enter your login code when asked.

Getting `AUTH02`? You haven't been added yet. Ask the owner to run `add-player.sh` with your exact gamertag.

## 3. Connect to the Realm (every time you play)

1. In the app, click the **Settings cog** (bottom left) → **Voice Chat Connect**. The first time, it asks you to sign in again.
2. Select **our Realm** and wait for the connection details.
3. Open Minecraft → **Play → Worlds** tab (**not** Realms, **not** Servers).
4. Pick the entry with the Realm's name whose second line shows **your gamertag** and **Bedrock Voice Chat**.

> ⚠️ **Always join through that Worlds entry.** If you open the Realm directly from the Realms list, the game works but you'll have **no voice**.

**PC/mobile and the entry isn't under Worlds?** Go to **Servers → Add Server**, address `127.0.0.1`, port `28282`, and join that.

**On console:** keep the app open on your phone (same Wi-Fi), then on the console go to **Worlds** and pick the entry. If two people in the house use BVC, you'll see two entries; pick the one with your gamertag.

## Good to know

- **Disconnected?** Wait about **5 minutes** before connecting again; Realms refuse a quick reconnect.
- **Voice stopped after a Minecraft update?** Expected. Voice comes back once Bedrock Voice Chat releases support for the new version and you update the app.
- **Keep the app updated.** It must be on the same version as the server.
- **Muting, volume, groups, whisper (crouch to talk quietly), chat:** see the official player docs:
  - [Using voice chat](https://www.bedrockvoicechat.com/wiki/player/using-voice-chat/)
  - [Groups](https://www.bedrockvoicechat.com/wiki/player/groups/)
  - [Settings](https://www.bedrockvoicechat.com/wiki/player/settings/)
  - [Player troubleshooting](https://www.bedrockvoicechat.com/wiki/player/troubleshooting/)

## Quick fixes

| Problem | Try |
|---|---|
| `AUTH02` on sign-in | Ask the owner to add your gamertag |
| Code doesn't work | It's single-use and expires after 24 h. Ask for a new one. |
| In the game but hear nobody | You joined the Realm directly. Leave and join via **Worlds**. |
| Can't hear anyone, and others can't hear you either | Tell the owner. Usually a server firewall (UDP) problem. |
| Realm not shown in Voice Chat Connect | Sign in again inside Voice Chat Connect; make sure you're a member of the Realm. |
| Entry missing on console | Phone and console must be on the same Wi-Fi network (not guest network). |
