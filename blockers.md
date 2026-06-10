# blockers.md — Known Blockers, Issues and Risks

Consolidated from hardware.md, driver_ports.md, code_review/findings.md and
the archive. One entry per blocker, with what unblocks it. Maintained per the
CLAUDE.md documentation requirements.

**Status legend:** 🔴 blocking the current milestone · 🟡 blocking a later
milestone · 🟢 resolved (kept for history)

---

## Operating decision: driver-work freeze (2026-06-10)

**No new driver code until first serial output on hardware.** Six subsystems
are already "code complete" against a device that has never booted anything
newer than 3.18, and several carry verification-blocked findings that only
hardware or datasheets can clear. Until Phase 3 produces serial output, the
only permitted work is: documentation, evidence extraction (vendor DTB / spec
PDF / boot images), Phase-3 build/packaging scripts, and fixes to *existing*
patches required for the minimal boot (e.g. B-4). Rationale: fable-report.md §4.3.

---

## 🔴 B-1 — FTDI serial cable not yet arrived

The primary Phase 3 blocker. All hardware verification is gated on it.
- **Unblocks:** cable delivery (ordered).
- **First action on arrival:** capture a **known-good 3.18 Kali boot** over the
  FTDI UART *before* flashing anything new. This validates the cable, wiring,
  and 921600 baud, and finally gives boot.md a baseline log. A 6.6 flash that
  produces nothing is then meaningful evidence about the kernel, not the cable.

## 🔴 B-2 — LK → mainline kernel handoff unverified

Everything assumes LK will load and start a 6.6 `Image.gz` + appended DTB the
way it boots the 3.18 image. Compounding risk: the archive records a rebuilt
3.18 kernel — byte-identical DTB, identical packaging and load addresses, even
the identical GCC 4.9 toolchain — that still failed to boot, **root cause never
found** (`archive/progress2.md` session 2). Whatever killed that build may kill
a 6.6 build identically.
- **Treat the first 6.6 flash as an experiment about LK, not about Linux 6.6.**
- **Diagnostic ladder if the first boot is silent** (decide now, not then):
  1. Re-verify the cable against the known-good 3.18 boot (B-1 first action).
  2. `earlycon` variants (explicit `earlycon=uart8250,mmio32,0x11002000`).
  3. Check whether LK itself prints on the UART / rejects the image (size
     limit, header fields).
  4. Bisect the DTS to an absolute minimum (cpus + memory + uart only).
  5. Read ramoops/pstore from Android after the failed boot
     (`/sys/fs/pstore`) — the board DTS now places ramoops in the region
     Android already maps.
- **Unblocks:** B-1, then first flash.

## 🔴 B-3 — LK memory/DTB fixup behaviour unknown

The vendor DTB carries a 1 GB placeholder memory node that preloader/LK fixes
up at boot. Unknown: does LK apply the same fixup to *our* DTB, and does it
preserve our `reserved-memory` carve-outs? Wrong answer = kernel sees 1 GB, or
stomps ATF/TEE regions (silent death).
- **Unblocks:** first boot — check `dmesg` memory map and `/proc/iomem`.

## 🟢 B-4 — dts/0006 display nodes default `status="okay"` (RESOLVED 2026-06-10)

Fixed: all 12 MM nodes (larb0, smi_common, disp_* ×9, mutex) now carry
`status = "disabled"`, matching `dsi0`/`mipi_tx0`. While fixing it, two more
pre-existing defects were found and fixed (see findings.md addendum):
- `dts/0006` was **corrupt** (hunk header declared 137 added lines, body had
  150) — it had *never applied*; the prior "compiles" claim was untestable.
- No patch added `mt6797-gemini-pda.dtb` to the dts `Makefile` — the board
  DTB would never have been built. Entry added to `dts/0001`.
Both patches regenerated from an in-tree edit (`git diff`), verified against
a pristine v6.6 checkout: all 10 patches `git apply --check` clean, and the
board DTB compiles (clang -E + dtc, 15,260 bytes).

## 🟡 B-5 — Datasheets missing for external chips

Verification-blocked BLOCK findings that no amount of repo work can clear
(see findings.md "Re-verification pass" for exactly what was and wasn't
clearable from the MT6797 spec PDF now in `docs/`):

| Chip | Patch | What is blocked |
|------|-------|-----------------|
| Richtek RT5735 | `regulator/0001` | Slew table, VSEL0/VSEL1 active-register polarity, PID value — drives the CPU rail; **do not enable on hardware until confirmed** |
| ON Semi FUSB301A | `usb/0001` | TYPE-register role decode (current logic FIXME-flagged, likely inverted) |
| AWINIC AW9523B | `gpio/0001` | ID value 0x23, CTL bit semantics |
| MT6797 MIPITX | `phy/0004` | PLL/PCW register layout, lock bit. Needs **"MT6797 Software Register Table (Part II)"** — the functional spec in `docs/` explicitly defers all DSI/MIPITX registers to that document (§6.4.3). Worth hunting for the Part II PDF. |

- **Unblocks:** datasheet acquisition, or empirical verification on hardware
  (Phase 4+; chip-ID reads first).

## 🟡 B-6 — `xhci-mtk` has no MT6797 entry in its device table

Phase 8 networking (USB-Ethernet) assumes the generic `mediatek,mtk-xhci`
binding will match. Unverified; if it does not bind, Phase 8 needs a small
compatible/device-table patch.
- **Unblocks:** hardware test once Phase 4 is stable.

## 🟡 B-7 — Rootfs / userspace compatibility (Phase 4)

The 2019 Kali `linux.img` userspace was built against kernel 3.18. Running it
under 6.6 is plausible but unproven (module loading, udev, device names).
- **Recommendation (fable-report §5.8):** build a fresh arm64 rootfs with
  `mmdebstrap` — the procedure is already proven (`archive/PROGRESS.md`) and
  removes the 2019-userspace variable entirely. Decision pending.
- **Unblocks:** decision + a Phase 4 build session; does not block Phase 3.

## 🟡 B-8 — R63419 panel requires dual-DSI for native resolution

The panel is dual-DSI (port0+port1, 4 lanes each); the current port is
single-DSI only. Single-DSI may reduce resolution/refresh **or fail to display
entirely** — unknown until hardware test. Mainline MTK DRM dual-DSI support is
weak. The spec PDF confirms the dual-DSI architecture (2 clock + 8 data lanes)
but no register detail (B-5).
- **Unblocks:** Phase 5 hardware iteration; manage expectations — a reduced
  display mode may need to be accepted per the project priority order.

## 🟡 B-9 — Touchscreen chip identity unknown

Novatek model is runtime-identified (`nvtpid`); cannot pick a driver path
until the ID is read on hardware or found in a Gemian/Kali boot log.
- **Unblocks:** first I2C-capable boot, or a community boot log.

## 🟢 B-10 — Build VM deleted (RESOLVED 2026-06-10 — rebuilt, smaller, reproducible)

Rebuilt the same day as Debian 13 arm64 (cloud image + cloud-init — fully
scripted, no manual installer): 10 GiB virtual disk (5.0 GB actual on host,
`discard=unmap` + `fstrim` keep it compact), GCC 14.2, SSH key auth, 9p host
share. Full kernel build verified: **0 errors, Image.gz + Gemini DTB + all
ported-driver modules** (~12 min). Rebuild recipe = `~/gemini-build/vm/seed/`
+ base image + `start-vm.sh`; provisioning script `~/provision-build.sh` in
the VM replays clone→patch→config→build. CLAUDE.md Build VM table updated.
Original entry below for history:

<details><summary>Original blocker text</summary>

The space cleanup removed **the entire `~/gemini-build/` directory** — the VM
qcow2 (with its `~/linux-6.6` and `~/gemini_linux` copies), the start script,
and all snapshots. Trash is empty; no Time Machine local snapshots. Nothing
authoritative was lost (patches and evidence live in this repo), but **no
kernel can be built until the VM is rebuilt** — kernel builds cannot run on
macOS (case-insensitive FS causes phantom file collisions, observed directly;
host-tool chain requires Linux).
- **Partially mitigated (2026-06-10):** the Mac-side kernel checkout is
  restored (`/Volumes/extdata/github/linux-6.6`, shallow clone of v6.6). This
  supports patch validation and DTS compilation (clang -E + dtc) on macOS,
  which is how B-4 was fixed and verified — but not kernel/module builds.
- **Unblocks:** rebuild the VM before the FTDI cable arrives so Phase 3 isn't
  serialised behind it. Recipe: `archive/claude.md` (QEMU `virt` + HVF, Kali
  arm64, 8 GB/8 CPU, port 5522, virtfs share), then rsync this repo and the
  kernel tree in, `apt install build-essential bc bison flex libssl-dev
  libelf-dev`, and re-create the CLAUDE.md snapshot baseline.

</details>

## 🟡 B-11 — Mainline MT6797 pinctrl has NO EINT (GPIO interrupt) support

Discovered 2026-06-10 while compile-checking the board DTS: dtc warns that
`&pio` is not an interrupt controller, and inspection of
`drivers/pinctrl/mediatek/pinctrl-mt6797.c` (v6.6) confirms it registers **no
`mtk_eint_hw` data at all** — no GPIO line on this SoC can deliver an
interrupt under mainline. This breaks every planned GPIO-IRQ consumer:

| Consumer | Phase | IRQ |
|----------|-------|-----|
| RT9466 charger | 7 | GPIO246 |
| AW9523B keyboard | 6 | GPIO87 (EINT10) |
| FUSB301A USB-C CC | 4+ | TBD |
| Novatek touchscreen | 5+ | TBD |

The charger node in `dts/0001` was `status="okay"` with
`interrupt-parent = <&pio>` — its probe would have failed at IRQ resolution.
**Fixed:** node now `disabled` with the rationale in-DTS.

- **Hardware facts for the future fix** (vendor DTB line 2835): EINT
  controller `eintc@1000b000`, reg `0x1000b000`, GIC SPI 170 level-high,
  192 EINT lines (`max_eint_num = 0xc0`), plus a GPIO→EINT mapping table.
  The mainline pattern is `mtk_eint_hw` data in the pinctrl driver + an
  `"eint"` reg + `interrupt-controller` + `interrupts` on the pio node
  (see `pinctrl-mt2701.c` for a same-generation example).
- **Workaround until then:** polled mode where drivers support it
  (`gpio-matrix-keypad` can poll; rt9467 cannot — charger stays disabled).
- **Unblocks:** EINT support in `pinctrl-mt6797.c` — **driver work, queued
  behind the freeze**; not needed for Phase 3/4.

## 🟡 B-12 — MT6351 PMIC has no mainline support (hardware.md was wrong)

Discovered 2026-06-10 while configuring the first VM kernel build:
`CONFIG_REGULATOR_MT6351` does not exist — direct inspection of v6.6 shows
**no MT6351 MFD, regulator, or RTC driver anywhere in mainline** (only the
ASoC codec `sound/soc/codecs/mt6351.c`). hardware.md previously marked the
PMIC "Upstreamed" (claimed mainlined in 6.2) — corrected.

Impact by phase:
- **Phase 3:** none — UART/boot need no PMIC regulators; LK leaves rails up.
- **Phase 4:** eMMC `vmmc`/`vqmmc` must be `regulator-fixed` stubs in the
  board DTS (rails already configured by LK; `mtk-sd.c` regulators optional).
- **Phase 7:** fuel-gauge plan unchanged (was already "no mainline support");
  RTC now also deferred.
- **Long-term:** a real MT6351 MFD + regulator driver port (mt6397-family
  pattern, vendor `drivers/misc/mediatek/pmic/` as register reference) is a
  new driver_ports.md item — **queued behind the freeze**.

---

## 🟢 Resolved (history)

| Date | Was | Resolution |
|------|-----|-----------|
| 2026-06-10 | Console identity contradiction (ttyMT0 vs ttyMT3 vs ttyS0) — risk of silent dead boot | **ttyMT0 = UART0 @ 0x11002000 @ 921600**, triple-sourced (vendor DTB bootargs + spec Table 2-7 pinmux + mainline dtsi). ttyMT3 was a never-used `CONFIG_CMDLINE` fallback. See kernel.md. |
| 2026-06-10 | Reserved-memory carve-outs unknown — risk of stomping ATF/TEE | Full map recovered from vendor DTB; carve-outs + ramoops added to `dts/0001`. See kernel.md / boot.md. |
| 2026-06-10 | Vendor decompiled DTS lived in volatile `/tmp` | Re-extracted and committed: `docs/vendor-dtb/` (DTB + DTS + known-good kernel config). |
| 2026-06-08 | WiFi/BT port feasibility unknown | Researched: ~75–103 KLOC vendor stack, broken upstream since 5.7/6.0. Deferred to Phase 9; USB-Ethernet is the Phase 8 plan. See research.md. |
| 2026-06-07 | GCC ≤4.9 believed required | Empirically debunked; GCC 15.2.0 works for both 3.18 and 6.6. See CLAUDE.md. |
| 2026-06-07 | `mtk wl` GPT corruption | Banned; targeted `mtk w` writes only. See CLAUDE.md Flashing. |
