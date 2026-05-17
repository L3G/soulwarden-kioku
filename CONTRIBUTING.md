# Contributing captures

The whole point of SoulwardenKioku is the data. A single capture of an unusual moment —
a disconnect, a region you have not seen submitted, character creation — can
be the missing piece. Thank you for helping.

## Submitting a capture

1. **Capture a session** — double-click `SoulwardenKioku.cmd`, play, type `stop` when
   done. See the [README](README.md) for the walkthrough.
2. **Review the bundle.** Open the session folder (under
   `Documents\SoulwardenKioku Captures\`), look in the `sanitized\` folder, and skim
   `Game.log`, `session.md` and `notes.md`. This is the last privacy check —
   see [PRIVACY.md](PRIVACY.md). Remove any file you would rather not share.
3. **Fill in `session.md`** — character class/level (the name is not needed),
   region/world, and what the session covered.
4. **Share `<session>_soulwardenkioku.zip`** in the community Discord:

   👉 **Discord:** https://discord.gg/BVhGm2yX — channel **`#captures`**

   Drop the `.zip` in `#captures` and add a one-line description, e.g.
   *"char creation, EU Central, build 6031"* or *"~40 min in-world, combat +
   2 zone changes, one disconnect"*.

That is it. No GitHub account, no pull request — and nothing to install by
hand: SoulwardenKioku sets up its own capture engine the first time you run it.

## What makes a capture especially valuable

- **Character creation** as its own session.
- **Long, continuous in-world play** — questing, combat, zone changes,
  dungeons, towns.
- **Disconnects / reconnects** — mark them with a note when they happen.
- **Variety** — regions, fresh vs. established characters, login edge cases
  (queues, failures).

## Only ever share the sanitized `.zip`

Do **not** share the raw `pcap\` folder or raw `Game.log`. The
`<session>_soulwardenkioku.zip` is the reviewed, scrubbed bundle — that is the one to
post. If you are unsure whether something is safe, ask in the Discord before
posting, or leave that file out.

## Improving the tool itself

Code contributions are welcome via pull request:

- Keep it **dependency-light** — Windows PowerShell, plus the Wireshark tools
  SoulwardenKioku installs on first run. No new runtimes.
- The capture path must stay **passive** — capture only, normal game launch,
  no injection, no game modification. Anything that touches the game process
  is out of scope and will not be merged.
- If you change what a capture records, update [PRIVACY.md](PRIVACY.md) in the
  same PR.

## Reporting problems

- **A bug or a capture failure** — open an issue with your Windows version and
  what `SoulwardenKioku.cmd` printed.
- **A privacy gap** (an identifier the scrubber missed) — open an issue
  describing the *kind* of value and where it appeared. **Do not attach the
  unredacted data.**
