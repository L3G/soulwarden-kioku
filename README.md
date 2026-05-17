# SoulwardenKioku — New World capture tool

**SoulwardenKioku** records the network traffic of a New World play session so
the game's online protocol can be studied and documented. It is a small,
double-click Windows tool: it captures your own traffic, then builds a
privacy-safe bundle you can share.

*(The name pairs* soulwarden *with* kioku *— 記憶, Japanese for "memory".)*

> **One-line version:** play New World normally, and SoulwardenKioku quietly writes down
> what your PC and the game servers said to each other (sizes and timing — not
> content; the traffic is encrypted). Share the result, help map the protocol.

This is a community **preservation and research** effort. New World's servers
will not run forever — once they are gone, the only record of how the game
talked to them is what players capture *now*. Every session helps.

This project is **unofficial** and not affiliated with or endorsed by Amazon
Games.

---

## Is this safe? Will I get banned?

**No ban risk — and that is by design.**

- SoulwardenKioku **launches New World completely normally**, through Steam, straight
  through EasyAntiCheat. Nothing is injected, hooked, patched, or modified.
- It captures **at the network layer** — the same thing Wireshark does. It is
  a passive observer of your own PC's network adapter. EasyAntiCheat does not
  see it, because there is nothing to see: the game runs untouched.
- SoulwardenKioku does **not** read, change, or automate anything in the game.

It captures **only your own traffic on your own machine**. It does not touch
anyone else's connection.

---

## What it records

New World's gameplay traffic is **encrypted (DTLS)**, so a capture does *not*
expose message contents — not yours, not the server's. What it does record is
the **shape** of the conversation: packet sizes, timing, direction, which
servers were involved, and the encryption handshake. That shape is what the
project uses to map the protocol.

When a session ends, SoulwardenKioku builds a **sanitized bundle** — and that is the only
file you ever share. The raw capture stays on your machine. Your Steam auth
ticket, account/persona id, and Windows username are scrubbed from the game log
automatically; your own machine's network address is removed from the data by
construction.

👉 **[PRIVACY.md](PRIVACY.md)** spells out exactly what is and is not in the
bundle. It is short — please read it.

---

## Quick start

You need **Windows 10/11** and **New World installed via Steam**.

### 1. Get SoulwardenKioku

[**Download the latest release**](../../releases/latest) and unzip it anywhere
(Desktop is fine). Or clone this repo.

### 2. Run setup — once

Double-click **`Setup.cmd`**. It installs the capture engine (Npcap +
Wireshark) and will ask for Administrator rights to do so. This is a one-time
step.

### 3. Capture a session

Double-click **`SoulwardenKioku.cmd`**. It asks for a short **label**, then:

1. starts the capture,
2. launches New World through Steam — play normally,
3. shows a `marker>` prompt: type a short note + Enter whenever something
   happens (entered world, accepted a quest, zone change, combat, level up,
   disconnect). Each note is timestamped so events can be lined up later.
4. when you finish playing, type **`stop`** + Enter.

SoulwardenKioku then builds **`<session>_soulwardenkioku.zip`** — your shareable bundle.

### 4. Share it

Skim the files inside the bundle (a quick sanity check), then drop the `.zip`
in the community Discord. See **[CONTRIBUTING.md](CONTRIBUTING.md)**.

---

## What is most useful to capture

- **Character creation** — capture it as its own session (label `char-create`).
  It is a distinct flow worth having on its own.
- **In-world play** — questing, combat, zone changes, towns, dungeons. One
  long continuous session beats several short logins.
- **Disconnects and reconnects** — note them with a marker; those moments are
  exactly what the research is short on.
- **Variety** — different regions, different character states (a fresh
  character vs. one with lots of inventory/quests) all add signal.

Mark events generously. A `notes.md` line for every quest, zone change, death
and level-up is what makes an encrypted capture interpretable later.

---

## Advanced use

Run the script directly for extra options:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\capture.ps1 -Label msq-ch1 [flags]
```

| Flag              | Effect |
|-------------------|--------|
| `-AllTraffic`     | Capture TCP too (picks up the HTTPS login flow). Default is UDP-only — that is the game protocol. |
| `-Watch`          | Open the Wireshark GUI to watch packets live. |
| `-NoGame`         | Capture only; don't launch the game (it's already running). |
| `-NoSanitize`     | Skip building the shareable bundle (build it later by hand). |
| `-ListInterfaces` | List capture interfaces and exit. |
| `-IfIndex <n>`    | Force a capture interface (default: the default-route adapter). |

Build a bundle from a session by hand at any time:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\sanitize.ps1 -SessionDir "<session folder>"
```

Sessions are filed under **`Documents\SoulwardenKioku Captures\`** by default.

---

## How it works

```
Setup.cmd  ─▶ scripts/setup.ps1     installs Npcap + Wireshark
SoulwardenKioku.cmd  ─▶ scripts/capture.ps1   capture + launch game + event markers
                   └─▶ scripts/sanitize.ps1   builds the shareable bundle
```

The capture engine is **dumpcap** (from Wireshark) with **Npcap**. SoulwardenKioku does
not bundle them — `Setup.cmd` installs them from their official sources.

---

## Good practice for clean captures

- **Quiet the network first** — close downloads, video, cloud sync and other
  games. Fewer stray flows make the game traffic easier to isolate.
- **Turn off any VPN** — it changes which servers show up.
- **Keep playing.** A continuous half-hour shows protocol flow that short
  logins never reach.
- **Edit `session.md`** right after, while it's fresh — note your character's
  class/level (no need for the name), region/world, and what you did.

---

## License

[MIT](LICENSE). SoulwardenKioku is the capture tool only; Npcap and Wireshark are
separate projects under their own licenses, installed from their own sources.
