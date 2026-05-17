# Privacy — what SoulwardenKioku captures and what you share

SoulwardenKioku captures network traffic, which is personal data. This page is the
straight account of what is recorded, what is removed, and what ends up in the
bundle you share. Please read it before you submit anything.

## The short version

- The **raw packet capture never leaves your machine.** It is not in the
  bundle you share.
- The thing you share is a **sanitized bundle** — data *derived* from the
  capture, with the sensitive parts removed automatically.
- New World's gameplay traffic is **encrypted**. SoulwardenKioku cannot read it, and
  neither can anyone you share the bundle with. Message *contents* are never
  exposed.

## What gets captured (stays local)

While you play, SoulwardenKioku writes a normal packet capture (`pcap\`) of your
selected network adapter, filtered to game traffic. A packet capture contains:

- packet **timing, size and direction**;
- the **encrypted payloads** — opaque ciphertext, not readable;
- the **DTLS handshake** (the encryption setup — cipher, the *server's*
  certificate, the server name requested);
- the network **addresses** of both ends — the game servers, and your own
  machine's address on your network.

This raw capture is filed under `Documents\SoulwardenKioku Captures\` and **stays
there.** It is git-ignored and never uploaded by SoulwardenKioku.

## What goes into the bundle you share

When a session ends, `sanitize.ps1` builds `<session>_soulwardenkioku.zip`. It contains
**only derived, scrubbed data**:

| File                 | What it is | How it's made safe |
|----------------------|------------|--------------------|
| `flows.csv`          | Per-packet timing, size, direction, and the **server** endpoint. | Each row is recorded by direction (up/down) and server peer; your own address is never written. Local and multicast traffic is dropped. |
| `endpoints.txt`      | Summary of the game servers you talked to. | Built only from server-side data; your address cannot appear. |
| `dtls-handshake.txt` | The encryption handshake — cipher, server certificate, server name. | Handshake fields only. The *server's* details; no field of yours. |
| `Game.log`           | New World's own log for the session. | Steam auth ticket, persona/account id, Steam ID and your Windows username are **redacted** automatically. |
| `session.md`         | Session metadata, plus context you fill in. | You write it — say as little or as much as you like. |
| `notes.md`           | Your timestamped in-game markers. | You write it. |
| `submission.md`      | Summary + a report of exactly what was redacted. | Generated. |

The **raw `pcap\`** is deliberately **not** included.

## Why derived data is enough

Because the gameplay protocol is encrypted, the raw capture's payloads are
opaque even to a researcher. Everything that *can* be learned from a live
capture — timing, sizes, direction, server endpoints, the handshake — is in
`flows.csv` and the handshake file. Sharing the derived data loses nothing
useful and removes the parts that identify you.

## Game.log — what is scrubbed

`Game.log` is the one file with real identifiers in it. SoulwardenKioku redacts:

- the **Steam authentication ticket** (the long `ticket: steam|…` blob);
- **Amazon persona / account / user ids** (`amzn1.…`);
- your **Steam ID** (the 17-digit number);
- your **Windows username** wherever it appears, including in file paths;
- any long token-like hex string.

Redaction is automatic but **best-effort** — it cannot promise to catch an
identifier in a format it has never seen. So:

> **Before you share, open the `sanitized\Game.log` and skim it.** If anything
> looks personal, delete those lines, or just leave `Game.log` out of the zip.
> The capture is still useful without it.

## What is *not* removed (and is fine to share)

- **Game server IP addresses** — these are the data the project wants.
- **Game/server version strings**, build numbers, region.
- **Hardware/OS lines** in `Game.log` (CPU, GPU, Windows version) — useful
  diagnostic context, not personally identifying.
- Whatever you choose to write in `session.md` / `notes.md`.

## Your choices

- You can **read every file** in the bundle before sharing — it is all plain
  text and a `.csv`.
- You can **remove any file** from the zip you would rather not share.
- You can **not share at all.** SoulwardenKioku captures to your own disk; sharing is a
  separate, deliberate step.

## Reporting a privacy problem

If you find an identifier that SoulwardenKioku failed to scrub, please open an issue (do
**not** attach the unredacted data) describing the *kind* of value and where
it appeared, so the scrubber can be improved.
