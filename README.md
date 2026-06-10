# Gemini PDA — Modern Linux Kernel Bring-Up

Port the [Planet Computers Gemini PDA](https://www.planetcom.co.uk/gemini-pda)
(MediaTek MT6797X / Helio X27) from its legacy Android/Linux 3.18 kernel to
**Linux 6.6 LTS**, maximising upstream Linux support and minimising vendor
code. The goal is a stable, maintainable, *booting* system — feature
completeness is secondary (see [CLAUDE.md](CLAUDE.md) for the full strategy
and phase plan).

## Status (2026-06-10)

- **Phase:** 3 (minimal kernel bring-up) — **blocked on FTDI serial cable**
  (ordered). Known-good baseline (2019 Kali, kernel 3.18) confirmed booting.
- **Operating decision:** new driver work is **frozen** until first serial
  output on hardware ([blockers.md](blockers.md)).
- Console question resolved: UART0 @ `0x11002000`, 921600 baud, pins
  GPIO97/98 — triple-sourced ([kernel.md](kernel.md)).
- Firmware reserved-memory map recovered from the vendor DTB and added to the
  board DTS, including a dual-boot-safe ramoops region.
- All 10 patches verified to apply on a pristine v6.6 tree; board DTB
  compile-checked on macOS (clang -E + dtc). Display/MM nodes all `disabled`.
- **Build VM was deleted** in a disk cleanup — must be rebuilt before any
  kernel build ([blockers.md](blockers.md) B-10). Mac-side kernel checkout
  restored for patch/DTS validation.

## Documents

| Document | Purpose |
|----------|---------|
| [CLAUDE.md](CLAUDE.md) | Project strategy, phase plan, build environment, flashing rules |
| [hardware.md](hardware.md) | Hardware inventory + upstream support status (start here) |
| [blockers.md](blockers.md) | Consolidated blockers and risks, with what unblocks each |
| [kernel.md](kernel.md) | Kernel config decisions; Phase 3 minimal boot artifact definition |
| [driver_ports.md](driver_ports.md) | Porting plan/details for every non-mainline driver |
| [research.md](research.md) | Deep-dive research notes (e.g. CONSYS WiFi/BT architecture) |
| [boot.md](boot.md) | Boot logs and observations from real hardware |
| [code_review/fable-report.md](code_review/fable-report.md) | Independent project assessment (2026-06-10) |

## Repository layout

```
patches/v6.6/        Kernel patches (git diff) by subsystem — read patches/STANDARDS.md first
scripts/             build.sh (VM build entry point) + hardware test scripts
code_review/         Adversarial driver review: rubric + findings
docs/                MT6797 functional spec PDF; vendor-dtb/ (extracted DTB/DTS + known-good config)
planet/              Stock firmware images (kali_boot.img, system.img, …) — not in git
archive/             Previous attempts (3.18-era); lessons learned, assumptions superseded
FlashToolLinux/      SP Flash Tool (recovery path) — not in git
```

## Build (summary)

Kernel builds run inside the QEMU arm64 VM — never on macOS:

```bash
~/gemini-build/vm/start-vm.sh &            # start VM (macOS)
ssh -p 5522 root@localhost                 # password: toor
cd ~/gemini_linux
./scripts/build.sh patch && ./scripts/build.sh config && ./scripts/build.sh build
```

See CLAUDE.md → Build Environment for sync commands and details.

## Flashing — safety rules

- **Never** use `mtk wl` or anything that rewrites the GPT (it corrupted the
  partition table once already — full reflash required).
- Only targeted writes: `mtk w boot2 <image>` (Linux kernel). `boot` is
  Android — leave it. `nvram` holds the IMEI — **never flash it**.
- Recovery: SP Flash Tool + scatter file (see CLAUDE.md → Flashing).

## Hardware quick facts

| Component | Detail |
|-----------|--------|
| SoC | MediaTek MT6797X (Helio X27), 10-core big.LITTLE, GIC-v3 |
| RAM / storage | 4 GB LPDDR3 / 64 GB eMMC (MSDC) |
| Display | 5.99″ 1440×2560 Renesas R63419, dual-DSI CMD mode |
| Keyboard | QWERTY matrix via AWINIC AW9523B I2C GPIO expander |
| Debug | UART0 @ 0x11002000, 921600 baud, GPIO97 RX / GPIO98 TX (FTDI) |
| Boot chain | MTK preloader → LK → `boot2` partition (Linux kernel) |
