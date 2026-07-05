---
name: build-pack
description: Run the full Gemini kernel build/pack/provenance cycle (VM build, boot.img pack, provenance dir, banner verification) via scripts/build-pack.sh
---

# build-pack

Run the full build cycle for a new Gemini boot image. Arguments: `<NN> <short-desc>` — the log sequence number for the *build* provenance dir and a kebab-case description (e.g. `32 msdc0-vmmc-supply`).

## Steps

1. Determine `NN`: look at `ls logs/` and use the next free number for today. If the user gave a number, use it.
2. Ensure the build VM is up (`ssh -p 5522 root@localhost true`); if not, start it with `~/gemini-build/vm/start-vm.sh &` and wait for ssh.
3. Run from the repo root:
   ```bash
   ./scripts/build-pack.sh <NN> <short-desc> [--dtb-grep <pattern>]
   ```
   Use `--dtb-grep` with a property you changed this iteration (e.g. `vmmc-supply`) so the built DTB is spot-checked.
4. The script prints the sha256, kernel banner, and flash/capture commands. Relay these to the user verbatim (absolute paths).

## Non-scriptable follow-ups (mandatory)

- Add a boot.md entry for the build: provenance dir, sha256, banner, what changed and why, expected next-capture outcome.
- Update the relevant blocker in blockers.md if the build addresses one.
- **Never** flash with `mtk wl` — only targeted `mtk w boot|boot2 <img>`.
- Captures always via `scripts/ftdi-monitor.py --log logs/...` (never scrollback; never `--beacon` while wired to the Gemini).
- Before analysing any capture, verify its banner matches the flashed build's banner — stale-boot-slot flashes have happened before.
- Do not commit to git unless the user asks.
