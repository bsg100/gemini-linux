# Gemini PDA — Modern Linux Kernel Bring-Up

Port the [Planet Computers Gemini PDA](https://www.planetcom.co.uk/gemini-pda)
(MediaTek MT6797X / Helio X27) from its legacy Android/Linux 3.18 kernel to
**Linux 6.6 LTS**, maximising upstream Linux support and minimising vendor
code. The goal is a stable, maintainable, *booting* system — feature
completeness is secondary (see [CLAUDE.md](CLAUDE.md) for the full strategy
and phase plan).

## Status (2026-07-16)

Phases 1-8 complete (see the phase table in [CLAUDE.md](CLAUDE.md) for full
detail and links into blockers.md/boot.md):

- **Phase 3** — first full Linux 6.6 boot to serial console.
- **Phase 4** — eMMC storage + Debian 13 rootfs live over SSH.
- **Phase 5** — display working on the physical panel, zero errors.
- **Phase 6 Stage A** — keyboard typing alongside display + USB gadget SSH.
- **Phase 7** — charger (TI BQ25896, mainline `bq25890_charger.c`) identified
  and working; fuel gauge has no mainline path (charger-only + userspace
  voltage monitor is the accepted minimum).
- **Phase 8** — simultaneous left-port charging + right-port USB host-mode
  ethernet confirmed on hardware.
- **In progress:** B-21 (internal WiFi via MT6797 CONSYS) — Gate G2a passes,
  G2b (WMT handshake) blocked; current focus is deciding how to re-scope G2b
  now that pre-firmware capture has been ruled out as reachable from
  userspace. See [blockers.md](blockers.md) B-21.

## Documents

| Document | Purpose |
|----------|---------|
| [CLAUDE.md](CLAUDE.md) | Project strategy, phase plan (with status table), build environment, flashing rules — start here for how the project runs |
| [hardware.md](hardware.md) | Hardware inventory + upstream support status per subsystem |
| [plan.md](plan.md) | Per-phase goals and success criteria (phase *status* lives in CLAUDE.md, not here) |
| [blockers.md](blockers.md) | Consolidated open/closed blockers and risks, with root causes and what unblocks each |
| [boot.md](boot.md) | Chronological boot logs, observations and per-build analysis from real hardware |
| [kernel.md](kernel.md) | Kernel config decisions; console/UART identification; minimal boot artifact definition |
| [driver_ports.md](driver_ports.md) | Porting plan and implementation details for every driver not available in mainline Linux |
| [research.md](research.md) | Deep-dive research notes (e.g. CONSYS WiFi/BT architecture, charger identity) |
| [patches/STANDARDS.md](patches/STANDARDS.md) | Mandatory rules every patch is reviewed against |
| [code_review/findings.md](code_review/findings.md) | Worked examples of patches breaking STANDARDS.md rules |
| [code_review/fable-report.md](code_review/fable-report.md) | Independent project assessment (2026-06-10) |

Boot attempts, blockers and driver decisions are recorded once, in the
document above whose purpose matches — avoid duplicating findings across
files; cross-link instead (e.g. a blockers.md entry links to the boot.md
build that produced the evidence, rather than re-describing it).

## Repository layout

```
patches/v6.6/        Kernel patches (git diff) by subsystem — read patches/STANDARDS.md first
scripts/             build.sh / build-pack.sh (VM build entry points) + hardware test scripts
code_review/         Adversarial driver review: rubric + findings
docs/                MT6797 functional spec PDF; vendor-dtb/ (extracted DTB/DTS + known-good config)
configs/             Kernel .config fragments per build variant (base, USB host, CONSYS, ...)
logs/                Per-build-attempt provenance (image/config/sha256 + serial capture) — evidence, not narrative
baremetal/           Standalone bare-metal test harnesses (e.g. display-hang-test) used for isolating hardware behaviour from the full kernel
rootfs-files/         Small files installed into the Debian rootfs by scripts/mkrootfs.sh
planet/              Stock firmware images (kali_boot.img, system.img, …) — not in git
archive/             Previous attempts (3.18-era); lessons learned, assumptions superseded — not in git
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

For a full build-flash-verify cycle with provenance tracking, use
`scripts/build-pack.sh <NN> <short-desc>` (see CLAUDE.md → Full-Cycle
Script). See CLAUDE.md → Build Environment for sync commands, the two-machine
(Mac/Linux workstation) profile split, and further details.

## Flashing — safety rules

- **Never** use `mtk wl` or anything that rewrites the GPT (it corrupted the
  partition table once already — full reflash required).
- Only targeted writes: `mtk w boot2 <image>` (Linux kernel), `mtk w linux
  <image>` (rootfs). `boot`/`system` are the Android pair — leave them.
  `nvram` holds the IMEI — **never flash it**.
- Recovery: SP Flash Tool + scatter file (see CLAUDE.md → Flashing).

## Hardware quick facts

| Component | Detail |
|-----------|--------|
| SoC | MediaTek MT6797X (Helio X27), 10-core big.LITTLE, GIC-v3 |
| RAM / storage | 4 GB LPDDR3 / 64 GB eMMC (MSDC) |
| Display | 5.99″ 1440×2560 Renesas R63419 panel (SSD2092 bridge), dual-DSI CMD mode |
| Keyboard | QWERTY matrix via AWINIC AW9523B I2C GPIO expander |
| Charger | TI BQ25896 @ i2c0 0x6b (mainline `bq25890_charger.c`) |
| USB | Left port (mtu3, peripheral/gadget) + right port (MUSB, host) — both working simultaneously |
| Debug | UART0 @ 0x11002000, 921600 baud, GPIO97 RX / GPIO98 TX (FTDI) |
| Boot chain | MTK preloader → LK → `boot2` (kernel) / `linux` (rootfs) partitions |

See [hardware.md](hardware.md) for the full inventory and per-subsystem
mainline-support status.
