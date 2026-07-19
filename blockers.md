# blockers.md — Known Blockers, Issues and Risks

Consolidated from hardware.md, driver_ports.md, code_review/findings.md and
the archive. One entry per blocker, with what unblocks it. Maintained per the
CLAUDE.md documentation requirements.

**Status legend:** 🔴 blocking the current milestone · 🟡 blocking a later
milestone · 🟢 resolved (kept for history)

---

## Operating decision: driver-work freeze (2026-06-10, LIFTED 2026-07-04)

**No new driver code until first serial output on hardware.** Six subsystems
were already "code complete" against a device that had never booted anything
newer than 3.18, and several carry verification-blocked findings that only
hardware or datasheets can clear. While the freeze was in effect, the only
permitted work was: documentation, evidence extraction (vendor DTB / spec
PDF / boot images), Phase-3 build/packaging scripts, and fixes to *existing*
patches required for the minimal boot (e.g. B-4). Rationale: fable-report.md §4.3.

**Lifted 2026-07-04** — see B-1 (resolved) and boot.md's "First Clean Serial
Capture" entry. First serial output on hardware has been achieved (stock
Android boot chain, over the now-working FTDI rig). Driver work may resume.
Note: the previously "code complete" driver subsystems are still unverified
against real hardware running Linux 6.6 (that requires B-2, the first 6.6
boot) — resuming work does not retroactively validate them.

---

## 🟢 B-1 — FTDI serial cable not yet arrived (RESOLVED 2026-07-04)

The primary Phase 3 blocker. All hardware verification was gated on it.
- **Resolution:** cable arrived; a 1.8V/3.3V-selectable adapter was initially
  wired at 1.8 V (matching the SoC's native pad voltage but wrong for the
  USB-C mux path, which rides standard 3.3 V USB D+/D− logic — see
  kernel.md). Switching the adapter to 3.3 V produced a fully clean capture
  of the stock Android preloader → LK → ATF boot chain at 921600 baud on the
  first attempt. This also retroactively confirms the 2026-06-12 garbled
  captures (see boot.md) were caused by signal-level mismatch, not a wiring
  or baud fault.
- **Evidence:** `logs/2026-07-04-01-first-serial-attempt.log`; full writeup
  in [boot.md](boot.md) under "First Clean Serial Capture — console
  confirmed working (2026-07-04)".
- **Unblocked:** the driver-work freeze condition ("first serial output on
  hardware") is now satisfied. Next: flash a Linux 6.6 `boot2` image and
  capture its console the same way (see B-2).

## 🟢 B-2 — LK → mainline kernel handoff unverified (RESOLVED 2026-07-04)

Everything assumes LK will load and start a 6.6 `Image.gz` + appended DTB the
way it boots the 3.18 image. Compounding risk: the archive records a rebuilt
3.18 kernel — byte-identical DTB, identical packaging and load addresses, even
the identical GCC 4.9 toolchain — that still failed to boot, **root cause never
found** (`archive/progress2.md` session 2). Whatever killed that build may kill
a 6.6 build identically.
- **Treat the first 6.6 flash as an experiment about LK, not about Linux 6.6.**
- **Next steps for the 6.6 flash attempt (unblocked by B-1, 2026-07-04):**
  1. ✅ Build: already done and validated 2026-06-10 (commit `19e91dc`) —
     `Image.gz` + `mt6797-gemini-pda.dtb` + full modules, 0 errors, against
     clean `~/linux-6.6` (`v6.6`) with the current patch set. Outputs live in
     `~/gemini-build/OUTPUT/` on the Mac host (not committed — build
     artifacts). No patch changes since, so no rebuild was needed.
  2. ✅ Packaged into a `boot.img` (2026-07-04) with the new
     `scripts/pack-boot-img.py`: copies the header and ramdisk byte-for-byte
     from `planet/kali_boot.img` (verified by direct hex inspection to be a
     plain AOSP v0 boot header, no MTK wrapper — kernel_addr `0x40080000`,
     ramdisk_addr `0x45000000`, tags `0x44000000`, page size 2048, all
     matching boot.md), and substitutes only the kernel blob
     (`Image.gz` + appended DTB). Result: `logs/2026-07-04-02-first-6.6-flash/new_kali_boot.img`.
  3. ✅ Provenance recorded — see boot.md "6.6 boot.img Packaged" entry for
     kernel tag/commit, patch commit, and checksums. `.config` copied to
     `logs/2026-07-04-02-first-6.6-flash/config`.
  4. ⬜ **Next (requires hands on the hardware — not automatable):** start
     the capture first — `scripts/ftdi-monitor.py --log
     logs/2026-07-04-02-first-6.6-flash.log` (proven rig from B-1: 3.3 V
     adapter, VBUS on the 5 V pin) — before plugging/powering the device.
  5. ⬜ Flash only `boot2`: `mtk w boot2
     logs/2026-07-04-02-first-6.6-flash/new_kali_boot.img` (never `mtk wl`).
  6. ⬜ Power on and capture. Compare against the B-1 baseline
     (`logs/2026-07-04-01-first-serial-attempt.log`): same preloader/LK
     preamble is expected; divergence starts wherever LK either fails to
     load/jump to the 6.6 image, or the 6.6 kernel itself goes silent after
     the jump — that divergence point is the diagnostic signal.
  7. ✅ Result added to boot.md ("First 6.6 Flash — flashed, captured,
     silent after el3_exit", 2026-07-04): preloader→LK→ATF handoff is
     byte-identical to the B-1 baseline, then silent after `el3_exit` —
     **but the B-1 stock-kernel baseline goes silent at the exact same
     point**, so this is inconclusive, not a failure. Root cause of the
     silence (both boots): LK injects its own cmdline
     (`console=ttyMT0,921600n1 ... printk.disable_uart=1`) at handoff,
     `ttyMT0` isn't a mainline console name, and our `.config` has
     `CONFIG_CMDLINE=""` with no `FORCE` flag, so nothing overrides it.
  8. ✅ Rebuilt with the cmdline force fix, reflashed, recaptured — **same
     exact silence at `el3_exit`**, a third identical result. This falsified
     the console-naming hypothesis (earlycon prints within the first few
     instructions of `start_kernel`, before any cmdline-dependent logic
     could matter) and pointed to something more fundamental: the CPU isn't
     executing our kernel's code at all after the jump.
  9. ✅ **Root cause found** (see boot.md "Cmdline Fix Retested" entry,
     2026-07-04): our packaged boot.img's `kernel_addr` (`0x40080000`,
     copied from the vendor header) is `dram_base + 0x80000` — correct
     under the vendor kernel's *old* (pre-v4.6) boot protocol, but **not
     2MB-aligned**, which the *modern* protocol our 6.6 kernel uses
     (`PHYS_BASE=1` flag, unconditional in all mainline arm64 kernels since
     v4.6 — confirmed this is not a `CONFIG_RELOCATABLE`/`RANDOMIZE_BASE`
     effect) strictly requires. Loading a modern kernel at a
     non-2MB-aligned address is a protocol violation — silent crash,
     matching all 3 identical failures exactly.
  10. ✅ **Retested and falsified** (boot.md "Aligned kernel_addr Retested",
      2026-07-04): flashed the 2MB-aligned repackage — identical silent
      failure, and the log proved LK **ignores the boot.img header's
      `kernel_addr` field entirely**, always loading at the hardcoded
      `0x40080000`. The packaging-layer fix could never have worked.
  11. ✅ **Real root cause identified**: since LK cannot be redirected via
      the header, the kernel itself must self-relocate off the
      non-2MB-aligned `0x40080000` — which is exactly what
      `CONFIG_RELOCATABLE=y` (arch/arm64 default) does. The prior session's
      fix had **disabled** `CONFIG_RELOCATABLE` while chasing the unrelated
      `text_offset=0x0` red herring, removing the only mechanism that makes
      booting at this address possible. That is the most likely true cause
      of every silent failure so far.
  12. ✅ Reverted `configs/gemini-cmdline.config` to leave
      `CONFIG_RELOCATABLE`/`CONFIG_RANDOMIZE_BASE` at defconfig defaults;
      kept `CONFIG_CMDLINE_FORCE`. Rebuilt clean in VM
      (`~/build-6.6-reloc-restored.log`). Repackaged at the original,
      LK-honored `kernel_addr=0x40080000` (no override):
      `logs/2026-07-04-05-relocatable-restored/new_kali_boot.img`, sha256
      `c8bb8f6bbf13b434efb351ca48d9a41dddfd7dec18c07c2d920cb24db7f43134`.
  13. ✅ Retested with RELOCATABLE restored — still identical silence after
      `el3_exit`. Falsified.
  14. ✅ **Baseline test** (boot.md "Vendor Baseline", 2026-07-04): flashed
      the unmodified vendor `planet/kali_boot.img` and captured a full run.
      Also silent after `el3_exit` — but this doesn't clear 6.6, since the
      vendor cmdline's `printk.disable_uart=1` (a 3.18-fork-only parameter,
      not implemented in mainline) is a known, deliberate cause unrelated to
      our kernel. **We have never had a real baseline of successful
      post-el3_exit console output on this hardware.**
  15. ✅ Found our explicit-address `earlycon=uart8250,mmio32,0x11002000`
      always uses the generic 8250 early driver, never the MediaTek-specific
      `early_mtk8250_setup` (only reachable via DT-node match on uart0's
      compatible string, confirmed `"mediatek,mt6797-uart"` /
      `"mediatek,mt6577-uart"` at `0x11002000`). Switched to the bare
      DT-node `earlycon` form, rebuilt, repackaged:
      `logs/2026-07-04-07-mtk-earlycon/new_kali_boot.img`, sha256
      `37a64a6d14b05f0f5aa8cbe18cd81647a92750844ae25dd45d12b7d9f19bc166`.
  16. ✅ Retested (power-button boot, not USB charge-mode) — still identical
      silence. Rules out boot mode as a variable.
  17. ✅ **Pivotal result** (boot.md "Pivotal Result: Silence After el3_exit
      Is Not a Failure Signal", 2026-07-04): flashed the unmodified vendor
      `planet/kali_boot.img`, held the power button, and the device **fully
      booted to the Android desktop UI — user-confirmed, visually
      verified.** The serial capture still ends at the exact same
      `el3_exit` point as every other attempt, with **zero output** despite
      the confirmed-successful boot. **This invalidates the diagnostic
      method used in steps 9-16**: silence after `el3_exit` carries no
      information about success or failure on this hardware/rig — it is
      what every boot looks like, vendor or mainline, working or not. The
      `CONFIG_RELOCATABLE` and earlycon-driver fixes may or may not be
      correct in principle, but the "still silent" results used to argue
      about them were never valid evidence either way.
  18. ✅ **ACTUAL ROOT CAUSE OF EVERYTHING ABOVE** (boot.md "ROOT CAUSE OF
      ALL 2026-07-04 SILENT RESULTS", 2026-07-04): after flashing 6.6 to
      `boot2`, a plain power-button boot **booted normally into Android** —
      and re-checking every capture from today shows LK loading
      `partition boot` (stock Android) in every single run. **`boot2` was
      never booted; our 6.6 kernel has never executed.** Plain power-button
      and USB-plug boots select OS 1; `boot2` needs the Gemini multi-boot
      button combo (left silver button + power — confirm exact combo).
      The uniform silence is fully explained by the stock Android kernel
      honouring `printk.disable_uart=1`. Steps 7-17's hypotheses and
      "results" are all void (never actually tested); the DEVAPC theory is
      withdrawn. Kept config changes (CMDLINE_FORCE + bare earlycon,
      RELOCATABLE at defaults) are reasonable but unexercised.
  19. ⬜ **Next (the real first 6.6 boot attempt):** `boot2` already holds
      the mtk-earlycon 6.6 image. Start a capture
      (`logs/2026-07-04-09-first-real-6.6-boot.log`), power on with the
      **boot2 combo** (silver + power), and verify the capture shows
      `Loading DTB from partition boot2` before interpreting anything —
      that line is now a mandatory validity check for every run.
      Optional sanity first: combo-boot the vendor image to prove the combo
      and finally capture a real successful Kali serial boot.
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

- **RESOLVED 2026-07-04.** After step 19, the strategy changed: rather than
  chase the `boot2` combo, the 6.6 test kernel was flashed to the **default
  `boot` slot** (boots on plain power-on, no button combo) — see boot.md's
  "FIRST 6.6 ATTEMPT" through "SEVENTH RESULT" entries and CLAUDE.md's
  current-decisions note. From there, LK's DTB pre-jump fixups were peeled
  off one panic at a time (each one a hard vendor-DTB-shape dependency in
  `mt_boot.c`, confirmed against `docs/vendor-dtb/gemini_kali_boot.dts`):
  1. cpu `clock-frequency` on all 10 cpu nodes (else infinite loop in
     `target_fdt_cpus`).
  2. `mediatek,mt6797-atf-ramdump-memory` reserved-memory compatible (else
     "Can not find atf ram dump!" panic).
  3. `mediatek,scp` **device** node (compatible `mediatek,scp`, root-level,
     `status="disabled"` — no 6.6 driver drives it) — LK's
     `platform_fdt_scp()` looks this up and patches its status before
     handoff; a `scp-share` *reserved-memory* node alone was NOT sufficient,
     the device node was the actual fix.
  With all three in place, LK printed `[LK]jump to K64 0x40080000` for the
  first time (`logs/2026-07-04-21-scp-node-boot.log`) — **the LK→mainline
  handoff is now proven working.** Two further kernel-side (not LK-side)
  issues were found and fixed via `CONFIG_CMDLINE`
  (`configs/gemini-cmdline.config`):
  4. 🟡 **NARROWED 2026-07-06, root cause reclassified 2026-07-06** — SMP
     secondary-CPU PSCI bringup hang, worked around with `maxcpus=1`/now
     `maxcpus=8` (not fully resolved — full 10-core SMP is now tracked as
     **B-16**, not B-13, see below). PSCI `CPU_ON` instrumentation
     (`arch/arm64/kernel/psci.c`, boot.md "PSCI CPU_ON diagnostic") showed
     CPU0–7 (both Cortex-A53 clusters) bring up cleanly in ~35ms; the hang is
     specifically at CPU8, the first core of the third cluster (2x
     Cortex-A72). Its PSCI `CPU_ON` SMC never returns — ATF firmware itself
     hangs, not a Linux-side defect. The original 2026-07-04 hang (which
     stalled at CPU1, before any clk fix existed) is now believed to have
     actually been the clk_ignore_unused bug wearing a different hat, not a
     distinct CPU1 defect — `maxcpus=2` alone boots CPU1 cleanly today
     (boot.md, `logs/2026-07-06-73-psci-cpu1-diag/`).
     `configs/gemini-cmdline.config` now uses `maxcpus=8` (validated
     `logs/2026-07-06-77-maxcpus8/`, boot.md "BUILD — maxcpus=8"): all 8 A53
     cores online, clean boot to `systemctl is-system-running` = `running`.
     Full SMP (cpu8/9) was originally assumed to share B-13's root cause but
     **this was disproven 2026-07-06** (boot.md "BUILD #11") — see B-16.
  5. 🟢 **RESOLVED 2026-07-06** — real root cause found and fixed (was:
     kernel hangs at `clk: Disabling unused clocks`, worked around with
     `clk_ignore_unused`). Full diagnosis and validation: boot.md "BUILD
     #62/#65/#67/#69". Summary: the clock that hangs is `infra_uart0` — the
     debug console's own baud clock. `drivers/tty/serial/8250/8250_mtk.c`
     fetches it with plain `devm_clk_get()` and only reads its rate, never
     enabling it (unlike the `"bus"` clock in the same function, which
     correctly uses `devm_clk_get_enabled()`). The hardware clock is left
     running by the bootloader, but Linux's own `enable_count` stays 0, so
     `late_initcall`'s `clk_disable_unused` cuts it — killing the only
     console, indistinguishable from a hang. Genuine upstream driver gap,
     not MT6797-specific. Fix:
     `patches/v6.6/serial/0001-serial-8250_mtk-hold-baud-clock-enabled.patch`
     (`devm_clk_get_enabled()` for both the `"baud"`-named and legacy-unnamed
     fallback paths). Validated on hardware (build #69,
     `logs/2026-07-06-69-uart-clk-fix-validation/`): `clk_disable_unused`
     completes, `infra_uart0` is skipped (enable_count now > 0), boot
     continues through eMMC mount and systemd with **no
     `clk_ignore_unused` needed**. Confirmed *not* the same root cause as
     B-13 (that one is a scpsys/power-domain issue with no domain even
     registered in this config; this one is a plain clk-framework refcount
     bug in a UART driver). **Folded back into the production build
     2026-07-06** (build #71, boot.md "BUILD #71"): `gemini-usb.config`
     (mtu3 gadget) re-added alongside the fix, `configs/gemini-cmdline.config`
     updated to drop `clk_ignore_unused` for real, validated end-to-end over
     SSH-over-USB with no regression (clean boot to `graphical.target` in
     19s, `g_ether` gadget working).
  With both workarounds, Linux 6.6 reached `Run /init as init process` —
  **first full boot to userspace** — before panicking in `switch_root` for
  reasons now tracked under B-7 (no eMMC controller node in DT at all).
  Patch: `patches/v6.6/dts/0001-arm64-dts-mediatek-add-gemini-pda-board.patch`
  (scp node + reserved-memory additions). **Phase 3 success criterion (first
  Linux 6.6 boot with diagnostic serial output) is met.**

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

## 🟢 B-7 — Rootfs / userspace compatibility (RESOLVED 2026-07-05 — 2019 Kali userspace boots under 6.6)

**Resolution (boot.md SIXTEENTH RESULT):** with eMMC working, the vendor
ramdisk's `switch_root` onto `/dev/mmcblk0p29` succeeds and the 2019 Kali
userspace boots fully under Linux 6.6 — systemd 239, udev, sshd, connman,
`kali login:` prompt on ttyS0 at 22.5s, multi-user + graphical targets
reached. **No fresh rootfs needed.** One follow-up (userspace, not kernel):
the vendor `kpoc_charger`/droid-hal-init daemon misreads the charging state
(vendor battery sysfs paths don't exist under 6.6), triggers its power-off
path and sysrq-remounts everything read-only ~28s in; disable/mask
`droid-hal-init`, `lxc@android` and the charger units on p29. Original
blocker text and the msdc0 bring-up chronicle below for history.

The 2019 Kali `linux.img` userspace was built against kernel 3.18. Running it
under 6.6 is plausible but unproven (module loading, udev, device names).
- **Recommendation (fable-report §5.8):** build a fresh arm64 rootfs with
  `mmdebstrap` — the procedure is already proven (`archive/PROGRESS.md`) and
  removes the 2019-userspace variable entirely. Decision pending.
- **Confirmed blocking, 2026-07-04** (boot.md "SEVENTH RESULT" entry): with
  B-2 now resolved and Linux 6.6 reaching `Run /init as init process`, init's
  script (from the 2019 Kali ramdisk) unconditionally does
  `switch_root` onto `/dev/mmcblk0p29`, which panics
  (`/dev/mmcblk0p29: Can't lookup blockdev` → `Attempted to kill init!`)
  because **no MMC/eMMC/SDHCI controller node exists anywhere in the device
  tree** — confirmed by grepping both mainline `mt6797.dtsi` and our board
  DTS. This is a prerequisite for *either* rootfs option (reused 2019 image
  or fresh mmdebstrap build): without an eMMC node, nothing can mount any
  root filesystem from internal storage. Next concrete step: add an MT6797
  MSDC/eMMC device-tree node — mainline's `drivers/mmc/host/mtk-sd.c`
  (`mtk-sd` driver) already supports the MT6797 MSDC IP block, so this should
  not require a new driver, only correct DT wiring (reg/clocks/pinctrl,
  vendor DTB at `docs/vendor-dtb/gemini_kali_boot.dts` has the reference
  node shape).
- **MSDC0 node added, then deferred, 2026-07-04:** an `msdc0@11230000` node
  was added using `compatible = "mediatek,mt6795-mmc"` (nearest upstream
  MSDC IP generation; mainline `mtk-sd.c` has no MT6797 entry). Probe
  required adding a second `state_uhs` pinctrl state (`mtk-sd.c` hard-fails
  probe without one, even for fixed non-removable eMMC with no real UHS
  signaling). With that added, probe proceeds but then **hangs completely
  silently** — no printk, ATF `aee_wdt_dump` fires ~36s later
  (`logs/2026-07-04-29-msdc0-uhs-boot.log`). Hypothesized the MSDC50_0 clock
  mux being unrouted (`msdc_init_hw()`'s `readl_poll_timeout(..., CKSTB, 0,
  0)` has **no timeout**, spins forever) and added
  `assigned-clocks`/`assigned-clock-parents` routing the mux to
  `msdcpll_d2` (mirroring the mt8173 binding example) —
  **no effect**: `logs/2026-07-04-31-msdc0-assigned-clocks-boot.log` hangs at
  the byte-identical timestamp/PC/LR as before, disproving the clock-wait
  theory. Attempted to symbolicate the hang PC/LR against `System.map` but
  KASLR's runtime slide made the addresses meaningless (resolved to
  irrelevant `omap_dm_timer` symbols). Added `nokaslr` to
  `configs/gemini-cmdline.config` for the next attempt at this, but **root
  cause is still unknown.**
- **Decision, 2026-07-04: MSDC/eMMC deferred, not required for Phase 4's
  first milestone.** The Gemini also has a removable SD card as a future
  alternate storage path, and per CLAUDE.md principle 5 (bootability first),
  neither is required just to prove the kernel/DT stack is otherwise sound.
  The `msdc0` node is left in the board DTS but `status = "disabled"`
  (comment references this entry for whoever resumes it). The vendor init
  script's unconditional `switch_root` (which is what actually needs eMMC)
  is bypassed for now via `rdinit=/bin/sh` on the cmdline — see boot.md
  "EIGHTH RESULT" for the resulting clean boot to an interactive shell.
  Resume this by symbolicating the hang PC with `nokaslr` before trying
  anything else; a genuine register-layout mismatch (needing a proper
  `mt6797_compat` table entry in `mtk-sd.c` rather than the `mt6795`
  stand-in) is the leading remaining hypothesis.
- **Update 2026-07-05 (msdc0 resumed, root cause found):** with the display
  fragment disabled (B-13, boot.md TENTH RESULT) and the headless `#32` build
  actually booting (after a stale-`boot`-slot detour — boot.md ELEVENTH
  RESULT), msdc0 finally probed: hclk-mux fix works (hclk 273 MHz),
  `msdc_init_hw` completes. The old "silent hang" is now diagnosed as an
  **MSDC IRQ storm**: ATF's watchdog dump (real PC this time, `nokaslr`)
  lands in `__irq_resolve_mapping` with hwirq 111 = GIC SPI 79 = msdc0.
  `msdc_irq()` always returns `IRQ_HANDLED` so the spurious detector never
  trips, and with `maxcpus=1` the storm starves everything, including printk.
  The mt6795-compat register-layout-mismatch hypothesis is still open as the
  reason the line screams. A storm guard (mask + dump raw
  `MSDC_INT/INTEN/PS` after 100k hits, disable line) is in the mtk-sd
  instrumentation patch; next boot (`#33`,
  `logs/2026-07-05-28-msdc0-irqstorm-guard/`) will name the stuck bit.
- **Update 2026-07-05 (storm root cause = IRQ polarity; first shell):** the
  `#33` storm-guard boot (boot.md TWELFTH RESULT,
  `logs/2026-07-05-29-msdc0-irqstorm-guard-boot.log`) dumped
  `MSDC_INT=0 MSDC_INTEN=0 MSDC_PS=81ff0002` — the storm is not from the MSDC
  event logic at all. Vendor DTB declares msdc0's IRQ as SPI 79
  **level-LOW**; our DTS said level-HIGH, so the idle line read permanently
  asserted. With the guard disabling the line, boot reached
  `Run /bin/sh as init process` and a live serial shell (MMC commands then
  time out, interrupt-less). Fix: `IRQ_TYPE_LEVEL_LOW` in the board DTS
  (patch 0001 regenerated); build `#34` in
  `logs/2026-07-05-30-msdc0-irq-levellow/` awaits flashing. The
  mt6795-register-layout hypothesis is likely retired as the storm cause.
- **Update 2026-07-05 (polarity confirmed; next failure = empty OCR):** `#34`
  boot (boot.md THIRTEENTH RESULT,
  `logs/2026-07-05-31-msdc0-irq-levellow-boot.log`): storm guard silent —
  polarity fix confirmed. Card init now fails with `no support for card's
  volts` / `-22`: no `vmmc-supply`/`vqmmc-supply` in our msdc0 node →
  empty `ocr_avail`. Fixed in build `#35`
  (`logs/2026-07-05-32-msdc0-vmmc-supply/`) with fixed always-on regulators
  (vemc 3.0 V → vmmc, vdd_1v8 stub → vqmmc); awaits flashing.
- **Update 2026-07-05 (vmmc confirmed; -84 CRC = mt6795 compat mismatch —
  the layout hypothesis returns, now proven):** `#35` boot (boot.md
  FOURTEENTH RESULT): volts error gone, card now fails with CRC `-84`.
  Vendor MT6797 `msdc_reg.h` proves `mt6795_compat` wrong on two counts:
  MT6797 has a 12-bit CKDIV (mt6795 data assumes 8-bit, so CKMOD bits
  landed inside the divider → wrong card clock) and PAD_TUNE0 at 0xf0
  (mt6795 writes 0xec, which doesn't exist). Switched compatible to
  `mediatek,mt2701-mmc` (12-bit div, PAD_TUNE0, async_fifo, data_tune).
  Also stripped all bias/input-enable pinconf from the msdc0 pin groups —
  upstream `pinctrl-mt6797.c` has no pinconf support, the failures
  reverted state application and leaked a GPIO125 pin claim. Build `#37`
  in `logs/2026-07-05-34-msdc0-mt2701-compat/` awaits flashing.
- **Update 2026-07-05 (eMMC WORKS — controller half of B-7 resolved):** `#37`
  boot (boot.md FIFTEENTH RESULT,
  `logs/2026-07-05-35-msdc0-mt2701-compat-boot.log`): banner matches, storm
  guard silent, no pinctrl errors, no CRC. `mmc0: new high speed MMC card at
  address 0001` → `mmcblk0: mmc0:0001 DF4064 58.2 GiB` with **all 33
  partitions** (p1–p33, incl. the p29 Kali rootfs), plus boot0/boot1/rpmb.
  The mt2701-compat + pinmux-only fix is confirmed. Card runs at legacy
  "high speed" (52 MHz) — fine for bring-up; HS200/HS400 tuning is a later
  optimisation. What remains of B-7 is the original rootfs question: point
  init at `/dev/mmcblk0p29` (drop `rdinit=/bin/sh`, let the vendor ramdisk
  `switch_root`) and see whether the 2019 Kali userspace survives 6.6, or
  build a fresh mmdebstrap rootfs.
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
  (rt9467 cannot poll — charger stays disabled).
  **Correction 2026-07-12 (Phase 6):** the original claim that
  `gpio-matrix-keypad` "can poll" was wrong — v6.6 `matrix_keypad.c` is
  IRQ-only, and no polling mode exists upstream even in current mainline
  (checked the file's full git log). Polling support was added locally:
  `patches/v6.6/input/0001-Input-matrix_keypad-add-polling-mode.patch`
  (optional `poll-interval` DT property → delayed-work scan loop, no row
  IRQs). The Gemini keyboard (build #147) uses it with
  `poll-interval = <20>`; the aw9523b DTS node has its interrupt
  properties removed until EINT exists (annotated in-DTS for restore).
- **Unblocks:** EINT support in `pinctrl-mt6797.c` — **driver work, queued
  behind the freeze**; not needed for Phase 3/4. Now also the Phase 6
  Stage B follow-up (switch keyboard from polling to IRQ) and a Phase 7
  prerequisite (RT9466 charger IRQ).

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

## 🟢 B-13 — cpu0 display-boot hard-lock ROOT-CAUSED (2026-07-07): DSI IRQ unmasked at probe wedges cpu0; scpsys domain-table bug was a separate, already-fixed issue

**RESOLVED at the diagnostic level 2026-07-07** (boot.md builds #127–#139):
the cpu0 "hard lock" was never a hardware/bus lock and never scpsys — the
mtk_dsi driver requests its level-low IRQ (GIC SPI 229) at probe time,
unmasking it while LK's leftover DSI engine state holds the line asserted;
cpu0 acks it and `mtk_dsi_irq()` wedges without EOI (status read stalls on
the unclocked/LK-state DSI block), which blocks ALL further interrupt
delivery to cpu0 at the GIC while the core keeps executing. Proof chain:
irqs-off cpu0 spin survives (#129) → irqs-on dies even with
cpuidle.off/nohlt (#131) → GIC observer catches SPI 229 stuck ACTIVE at
hang time (#133) → disable_irq after request is already too late (#135) →
IRQ_NOAUTOEN before request defeats the hang (#137) → clean build boots
to `systemd is-system-running: running` with the display stack enabled
(#139, SSH-validated). **Proper fix landed 2026-07-07 (build #141,
boot.md "BUILD #141"):**
`patches/v6.6/drm/0008-drm-mediatek-dsi-enable-irq-only-while-powered.patch`
— IRQ_NOAUTOEN at probe, `enable_irq()` at end of `mtk_dsi_poweron()`
(clocks on, engine reset), `disable_irq()` in `mtk_dsi_poweroff()` before
clocks off; replaces the interim DEBUG patch. Validated on hardware: no
regression (systemd `running`, `/proc/interrupts` shows IRQ 15 / SPI 229
registered with 0 counts, masked until power-on).
Remaining follow-ups: DRM master deferred-probe chain (ordinary bringup
work), debug-instrumentation cleanup, A72-cluster (B-16) retest.

**Update 2026-07-07 (SMI larb pin-active regression, boot.md BUILD #155/#157):**
new, distinct MM-domain-adjacent hang found and reverted during OVL
frame-fetch debugging. The DSI IRQ fix above cleared the DRM bind hang, but
`flip_done timed out` persisted (boot.md BUILD #151) — root-caused to SMI
larb0 sitting permanently runtime-suspended (mainline only resumes SMI larbs
via mtk_iommu device links, and MT6797 has no mainline M4U driver, so nothing
ever claims it). A fix pinning the larb active at probe
(`memory/0003-…pin-larbs-active-when-no-iommu-driver.patch`) was landed in
build #154, but its guard tested the wrong condition
(`IS_ENABLED(CONFIG_MTK_IOMMU)`, a Kconfig symbol compiled in generally,
rather than whether *this* larb's DT node has an `iommus` phandle) and
silently never fired. **Build #155 corrected the guard** to
`!of_property_present(dev->of_node, "iommus")`, making the pin-active
`pm_runtime_resume_and_get()` call actually execute for the first time — and
this reproduced the same class of MM-domain hard-hang as BUILD #79
(`configs/gemini-display.config`'s `COMMON_CLK_MT6797_MMSYS` finding):
serial log looked completely normal up to the expected USB-mux cutoff, but
the USB gadget never enumerated (vs. 15-35s normally) and the user directly
observed a crash/reboot. **Build #157 reverted `memory/0003` entirely**
(regenerating the patch against a clean tree produced a zero-line diff,
confirming full revert to stock `mtk-smi.c`) and confirmed stable: normal
boot, USB gadget enumerated normally, SSH-live `uptime` with no crash,
`flip_done timed out` persists as expected (larb correctly left unpinned,
`runtime_status`=`suspended`), backlight still correct. **Conclusion:**
SMI larb0's power domain is `MT6797_POWER_DOMAIN_MM` — the same domain
implicated in BUILD #79 — and eagerly resuming it at probe time (rather than
leaving it to whatever power-on sequencing the MM domain needs) reliably
triggers a hard-hang/crash. The open sub-problem is therefore not "pin the
larb active" but "safely power on the MM domain path (scpsys → SMI larb)
without hitting this hang class" — likely needs the same kind of guarded,
precondition-gated approach that fixed the DSI IRQ (enable/resume only after
some other state is confirmed ready, not unconditionally at probe). Current
state: stable baseline restored (backlight working, larb correctly
unpinned, pipeline stalled), tracked as the next concrete B-13 sub-task.

**Update 2026-07-07 (OVL→SMI-larb device link — safe fix for the pin-active
regression, boot.md BUILD #159/#161):** the "safely power on the MM domain
path" sub-problem flagged just above is resolved. Instead of pinning the SMI
larb active unconditionally at its own probe time (the #155 approach that
hard-hung the MM domain), `drm/0011-drm-mediatek-ovl-link-smi-larb-runtime-pm.patch`
has `mtk_disp_ovl_probe()` resolve its existing `"mediatek,larb"` DT phandle
and add a `device_link_add(dev, &larb_pdev->dev, DL_FLAG_STATELESS |
DL_FLAG_PM_RUNTIME)` (no `DL_FLAG_RPM_ACTIVE`) — this ties the larb's
runtime-PM state to OVL's own, so the larb only resumes when OVL is
runtime-resumed by the normal DRM atomic-commit path, not eagerly at
link-creation/probe time. Confirmed live over SSH on build #159: SMI larb and
smi-common both `active` (were permanently `suspended`), OVL0/OVL2L0 IRQ
counters incrementing (71/70, previously frozen at 0), no MM-domain hang, no
crash. **Lesson generalized:** for an SMI larb with no mainline M4U/IOMMU
driver bound, *when* its runtime-PM resume happens (tied to a consumer whose
own resume timing is already proven safe) matters more than *whether* it
happens at all.

Build #161 then stripped the now-obsolete GEMINI-DEBUG instrumentation (its
purpose — diagnosing this blocker — is done) and surfaced the next data
point with a clean serial trace:
```
[drm:mtk_dsi_host_attach] *ERROR* failed to add dsi_host component: -517
panel-solomon-ssd2092 1401c000.dsi.0: failed to attach DSI: -517
```
alongside `mediatek-drm mediatek-drm.1.auto: Waiting for disp-mutex driver
/mutex@1401f000`. `-517` is `-EPROBE_DEFER` — normally a benign, self-resolving
retry — but this has **not yet been confirmed** benign vs. a real block here,
since the serial capture always cuts off shortly after (B-15 mtu3/USB mux
switch) before any retry could be observed. **This is the first task for the
next session:** get a full post-boot `dmesg` over SSH on build #161 (not yet
done — a USB host-side enumeration issue on the Mac intervened and consumed
the rest of this session; root-caused as unrelated to the kernel, see boot.md
"USB gadget enumeration investigation, 2026-07-07" — every serial capture
throughout showed a completely normal, unhung boot) to determine whether the
DSI host eventually attaches or the `disp-mutex` wait blocks it permanently.

**Update 2026-07-08 (`-517` confirmed benign — B-13 closed; new blocker
opened as B-17):** got the live `journalctl -k -b` dump over SSH on build
#159 that the previous session needed (dmesg's own ring buffer had already
wrapped past the boot-time messages). Confirms the DSI host attach
**does** succeed on retry:
```
probe of 1401c000.dsi.0 returned 0 after 62276826 usecs
```
(~62s after the initial `-517`). `mtk_drm_bind` then completes, the panel
registers (`panel-solomon-ssd2092 1401c000.dsi.0: Solomon SSD2092 FHD DSI
panel registered`), and DRM creates `fb0: mediatekdrmfb`. So the
`disp-mutex` wait resolves and the deferred-probe retry is a normal,
harmless part of driver bring-up here — **not** a real block. **B-13, as
originally scoped (cpu0 hard-lock at DSI probe + this probe-defer
question), is now fully closed.**

Immediately after, a new failure appeared that actually explains the still-dark
screen: `mtk_mipi_tx_driver_init` (`phy_mtk_mipi_dsi_drv`, the MIPI DSI
D-PHY) returns **`-16`/`-EBUSY`** on probe. With no working D-PHY, DSI binds
logically (host+panel+fb all register) but can't physically clock data to
the glass, so every DRM atomic commit times out waiting for vblank/flip
completion — an infinite ~10s-period loop of `flip_done timed out` /
`commit wait timed out` across CRTC/PLANE/CONNECTOR as the fbdev helper
keeps retrying. Tracked as new blocker **B-17** (see entry below) — root
cause of the EBUSY not yet investigated (leading candidate: a clock,
regulator, or MMIO region the D-PHY driver requests is already held by
another driver/instance; cross-reference the vendor 3.18 `mtk_mipi_tx`/DSI
PHY source for a specific sequencing requirement).

**Update 2026-07-05 (evening):** severity upgraded — this is no longer just
"DRM never binds". With `CONFIG_COMMON_CLK_MT6797_MMSYS=y` (added to fix the
DSI engine-clk -517 defer), the kernel **hard-hangs silently at ~0.52s**
(identical final line/timestamp in `logs/2026-07-05-21-…` and `-23-…`;
minutes-long capture, no further output, no watchdog dump). Registering the
mm-domain clocks leads to an MM-domain register access with the domain
unpowered/unmanaged, wedging the bus. Until B-13 is fixed, the display
fragment is disabled: `configs/gemini-display.config` →
`gemini-display.config.disabled-b13`. See boot.md TENTH RESULT.

**Update 2026-07-06:** also the likely root cause of the Phase 4 SMP hang
(B-2 item 4) — PSCI `CPU_ON` instrumentation showed the Cortex-A72 cluster
(cpu8/9) hangs firmware-side on bringup, consistent with its power domain
never being enabled by the broken scpsys domain table. See boot.md "PSCI
CPU_ON diagnostic". Fixing B-13 is therefore expected to unblock **both**
display and full 10-core SMP, not just display.

**Update 2026-07-07:** the bare-metal diagnostic payload
(`baremetal/display-hang-test/`) built to distinguish hardware-lock vs
Linux-software causes is **parked without ever executing** — six packaging
variants all hang inside ATF/BL31 before `el3_exit` while a control reflash
of the known-good build boots clean (boot.md "B-13 bare-metal payload",
logs -114..-126; README "Known issue" has the variant table). Replaced by
an in-kernel equivalent:
`patches/v6.6/drm/0007-GEMINI-DEBUG-cpu0-irqsoff-poll-loop.patch` — cpu0
irqs-off raw-MMIO heartbeat + GICD pending/active dump (hooked at the end
of `mtk_drm_probe()`, which returns ~27ms before the hang).

**RESULT (build #129, boot.md "BUILD #129"): NOT a hardware lock.** With
the display config enabled, the hijacked cpu0 heartbeat ran continuously
for ~7.1s straight through the fatal ~2.6s window — cntpct advancing, GICD
pending pattern constant (no storm), and cpu0 still took the ATF watchdog
FIQ at the end. B-13 is therefore a software/GIC-state problem: interrupt
*delivery to* cpu0 dies (or cpu0 dies in something it only does when
allowed to proceed — prime suspect cpuidle/WFI entry), not the core or
bus. Status upgraded from "deferred, hypotheses exhausted" to **actively
tractable**. Next: (1) observer-mode variant — poll loop on cpu1, cpu0
boots normally, dump cpu0's GICR/GICD state each beat to catch what
changes at hang time; (2) `cpuidle.off=1` / `nohlt` test with display
enabled.

Discovered 2026-07-05 during first Phase 5 display bring-up hardware test
(`logs/2026-07-05-02-phase5-display-boot.log`). The full display pipeline
(`disp_ovl0` → `disp_rdma0` → `disp_color0` → `disp_ccorr0` → `disp_aal0` →
`disp_gamma0` → `disp_od0` → `disp_dither0` → `mutex` → `dsi0` → panel, plus
`mipi_tx0`) was enabled in the board DTS for the first time, and
`CONFIG_DRM_MEDIATEK`/`CONFIG_PHY_MTK_MIPI_DSI`/`CONFIG_DRM_PANEL_RENESAS_R63419`/
`CONFIG_MTK_MMSYS`/`CONFIG_MTK_CMDQ`/`CONFIG_BACKLIGHT_CLASS_DEVICE` forced
built-in (new fragment `configs/gemini-display.config` — required since the
`rdinit=/bin/sh` initramfs shell has no modprobe path, see B-7). Kernel and
DTB built and booted cleanly (no hang, no regression to the Phase 4
milestone), but the DRM driver never bound:

```
[    0.320587] mtk-scpsys: probe of 10006000.power-controller failed with error -22
[    0.370139] mediatek-drm mediatek-drm.1.auto: Failed to find disp-mutex node
...
[   10.738979] platform lcd-avee-regulator: deferred probe pending
[   10.739758] platform lcd-avdd-regulator: deferred probe pending
[   10.740509] platform 1401c000.dsi: deferred probe pending
```

**Root cause (confirmed by reading driver source in the VM, not guessed):**
`drivers/pmdomain/mediatek/mtk-scpsys.c`'s `scp_domain_data_mt6797[]` uses
C99 designated initializers indexed by the `MT6797_POWER_DOMAIN_*` enum
(`include/dt-bindings/power/mt6797-power.h`): `VDEC`=0, `VENC`=1, `ISP`=2,
`MM`=3, `AUDIO`=4, `MFG_ASYNC`=5, `MFG`=6, `MFG_CORE0..3`=7-10, `MJC`=11. Only
7 of these 12 slots have an initializer (`VDEC`, `VENC`, `ISP`, `MM`,
`AUDIO`, `MFG_ASYNC`, `MJC`) — the designated-initializer array's size is
fixed by the highest index used (`MJC`=11), so it's actually 12 elements,
and the 5 GPU-related slots (`MFG`, `MFG_CORE0`-`MFG_CORE3`) are silently
zero-filled (`.name = NULL`). `scpsys_probe()` → `init_scp()` loops
`for (i = 0; i < num; i++)` over **all 12** and calls
`devm_regulator_get_optional(&pdev->dev, data->name)` unconditionally. For
the 5 empty slots this passes `id == NULL` into `_regulator_get()`
(`drivers/regulator/core.c:2179`), which treats a NULL identifier as a hard
error (`pr_err("get() with no identifier\n"); return ERR_PTR(-EINVAL);`) —
**not** the "-ENODEV, no supply configured" path `devm_regulator_get_optional`
is meant to tolerate. `init_scp()` doesn't distinguish this from a real
error and aborts, so `scpsys_probe()` returns -EINVAL for the **whole
device**, not just the GPU domains. Since our `MM` domain (index 3, fully
populated, needed for the entire display path) lives on the same platform
device, every display component's `power-domains = <&scpsys
MT6797_POWER_DOMAIN_MM>` reference fails to resolve and every consumer sits
in permanent deferred probe.

This is a genuine upstream Linux 6.6 gap in MT6797 support, not a Gemini
board-DTS mistake — confirmed the DTS is unaffected: `mipi_tx0`/`dsi0`/all
`disp_*` nodes compile and show `status = "okay"` correctly in the built
DTB, and their DT wiring (`power-domains`, `clocks`, `mediatek,larb`) matches
the mt8173 reference pattern. The bug is entirely inside
`mtk-scpsys.c`'s MT6797 domain table + its all-domains probe loop.

**Not yet fixed** — a correct fix needs real SPM register offsets
(`ctl_offs`, `sta_mask`, `sram_pdn_bits`/`sram_pdn_ack_bits`) for the `MFG`/
`MFG_CORE0-3` domains, which are GPU (Mali T860, Panfrost) power gates that
are explicitly out of scope for Phase 5 (hardware.md: GPU work "Defer until
display works"). No verified register values for these are in the project
yet (B-5 gap: no full datasheet). Fabricating placeholder register offsets
for GPU-domain gating is exactly the kind of guess CLAUDE.md principle 7
(documented rationale, no guessing on hardware values) warns against —
wrong `ctl_offs` values here risk toggling live SPM state incorrectly.

**Two real fix paths, next session:**
1. **Correct:** source real MT6797 `MFG`/`MFG_CORE0-3` SPM register values
   (likely obtainable from the vendor 3.18 BSP's own SPM/scpsys driver in
   `drivers/misc/mediatek/base/power/mt6797/`, not yet checked) and add
   proper `scp_domain_data_mt6797[]` entries for indices 6-10.
2. **Safe workaround, less correct:** patch `init_scp()`'s probe loop (and
   the mirrored loop in `mtk_register_power_domains()`) to `continue` when
   `data->name == NULL`, i.e. skip unpopulated domain-table slots instead of
   treating them as fatal. This is a generically-applicable driver
   robustness fix (protects any future SoC with sparse domain tables, not
   Gemini-specific), and doesn't require GPU register values since it just
   stops the driver from tripping over its own data-table gap. Recommended
   starting point — unblocks `MM`/display without touching GPU power state
   at all.
- **Unblocks:** the actual kernel-driven display test (today's result was
  proof the DTS/build/config chain is right, not proof the panel can be
  driven — the LK bootsplash seen on screen is unrelated, confirmed by its
  timing: static and present from very early in boot, i.e. rendered by LK's
  own `logo`-partition splash code before Linux ever runs, not by our new
  DRM/panel patches).

**Update 2026-07-06 (fix re-tested, still not sufficient):** the "safe
workaround" patch above
(`patches/v6.6/pmdomain/0001-pmdomain-mediatek-skip-unpopulated-mt6797-domain-slots.patch`)
was committed 2026-07-04 but had never actually been flash-tested with
`configs/gemini-display.config` enabled until now. Re-enabled the display
fragment and retested (build #79/boot.md "BUILD #79"): boot progresses
further than the original 2026-07-05 discovery — `mediatek-drm` now gets as
far as adding component matches and the panel driver registers
(`panel-renesas-r63419 ... registered`) — but the kernel then hard-hangs and
the board enters a genuine watchdog reboot loop (5 cycles observed in one
capture, each dying at the identical line). An ATF `aee_wdt_dump` this cycle
symbolicated to `cpu_do_idle` on CPU1, which is a red herring: the
`inter-cpu-call interrupt is triggered` lines that precede it are ATF's
whole-system IPI broadcast for collecting a crash dump once some CPU's
watchdog trips, not evidence CPU1 is the stuck core. The real hang is
presumed to still be on the boot CPU inside the MM-domain power-on register
access itself, once a consumer actually touches it — the NULL-name skip fix
only prevents the scpsys *driver probe* from aborting early; it does not
supply working power-on register offsets/timing for the MM domain. **B-13 is
not resolved by this patch alone.** Device was recovered by re-flashing the
known-good `maxcpus=8`, no-display build (`logs/2026-07-06-77-maxcpus8/`) —
note the first re-flash attempt during this session silently failed to take
(capture still showed the old hung build); a second attempt succeeded and was
verified by checking the kernel banner in a fresh capture plus a live SSH
session. `configs/gemini-display.config` is left enabled in the repo since
the underlying scpsys probe fix is real forward progress, but it is not yet
safe to leave flashed on the device without further work on the actual
MM-domain power sequencing.

**Update 2026-07-06 (second infracfg block hypothesis, tested and falsified):**
cross-checking the vendor DTB (`docs/vendor-dtb/gemini_kali_boot.dts`, this
device's own flash) found MT6797 has **two distinct infracfg hardware
blocks**: `infracfg_ao@10001000` (what mainline's `mt6797.dtsi` models as the
`infrasys` node, used for infra clock gating) and a **second, separate**
`infracfg@10201000` node. The vendor's own `scpsys@10001000` node spans all
three physical regions (`0x10001000` AO infracfg, `0x10006000` SPM,
`0x10201000` this second block), strongly suggesting the real
`INFRA_TOPAXI_PROTECTEN`/`PROTECTSTA1` bus-protection registers
`scpsys_bus_protect_enable/disable()` needs live in the second block, not the
AO block mainline's `scpsys` phandle currently points at.

Added a new `syscon`-only DT node for the second block and repointed
`scpsys`'s `infracfg` phandle at it
(`patches/v6.6/dts/0010-arm64-dts-mediatek-add-mt6797-real-infracfg-node.patch`,
build #81). Flash-tested (`logs/2026-07-06-81-scpsys-b13-real-infracfg/`,
capture `logs/2026-07-06-82-scpsys-b13-real-infracfg-boot.log`): **no change
in observed behaviour** — boot reaches the identical point as the untested
build #79 (`panel-renesas-r63419 ... registered`), then hard-hangs with the
same ATF watchdog signature (`aee_wdt_dump: on cpu1` at 14.2s, `on cpu3` at
18.1s, then silence). The hypothesis is not confirmed by this result: either
(a) the second infracfg block isn't actually where bus protection lives
either (the vendor DTB's grouping of three regions under one `scpsys` node
doesn't necessarily mean all three are used by the *bus-protection* sub-
function specifically — SPM and AO infracfg alone could already satisfy
mainline's `scpsys` needs, and the 0x10201000 block could be for something
else the vendor driver also touches), or (b) the phandle target was right
but bus protection was never the actual hang cause -- the hang could equally
be inside `scpsys_power_on()`'s SRAM/power-on register sequencing itself
(`ctl_offs`/`sta_mask`/`sram_pdn_bits`) once the MM domain is genuinely
powered on and a consumer (the panel/DSI path, consistent with hanging right
after panel registration) touches its registers for the first time. The
DTS-only fix is not sufficient on its own; register-level confirmation via
the vendor's actual driver behaviour (e.g. instrumenting `scpsys_power_on`/
`scpsys_bus_protect_enable` with `dev_info` per-step, since the code path is
now provably reached but stalls somewhere inside it) is the next concrete
step, not further DTS-only guessing. Patch 0010 is retained (harmless, and
directionally justified by the vendor DTB evidence even if not sufficient by
itself) but does not close B-13.

**Update 2026-07-06 (per-step power-on trace — scpsys power-on EXONERATED,
hang relocated to DRM bind):** build #84
(`logs/2026-07-06-84-scpsys-b13-step-trace/`, banner `#14 ... 08:45:36`,
temporary patch
`patches/v6.6/pmdomain/0002-GEMINI-DEBUG-scpsys-power-on-step-trace.patch`)
added a `dev_info` before every step of `scpsys_power_on()`. Capture
(`logs/2026-07-06-85-scpsys-b13-step-trace-boot.log`, second boot in file):
**every domain — vdec, venc, isp, mm, audio, mfg_async, mjc — completes all
steps cleanly**, including MM's `sram_enable`, `bus_protect_disable` and
`done` at 0.3548s. Two key facts:

1. MM's ctl register already read `0xe0d` *before* the kernel touched it —
   PWR_ACK set, SRAM up: the vendor LK bootloader leaves the MM domain
   powered on for its splash screen. The kernel's power-on is a no-op ride
   on an already-live domain.
2. The hang therefore is **not in scpsys at all**. The last kernel line is
   still `panel-renesas-r63419 ... registered` (0.4569s) — the moment the
   final DRM component match completes and the component master binds. The
   stall is inside the mediatek-drm bind path, i.e. the first actual
   register access to the 0x14xxxxxx mmsys range (mmsys routing writes,
   ddp comp init) or a DMA/clock dependency of it.

Concrete confirmed gap found while investigating: DTS patch 0006 declares
`mediatek,mt6797-smi-larb`/`mediatek,mt6797-smi-common` nodes, but **no
driver implements those compatibles** — upstream `drivers/memory/mtk-smi.c`
has no MT6797 entries and no project patch adds them, so SMI never probes
and its clocks are never enabled. Whether the bind-time hang is (a) the
mmsys config register write path needing a clock nothing enables, or (b)
something touching the un-clocked SMI/larb, needs one more instrumented
build — next step: per-step trace of `mtk_drm_bind()` /
`mtk_drm_kms_init()` / `mtk_mmsys_ddp_connect()` to find the exact first
stalling register write. B-13's title (scpsys domain table) is now known to
be a mischaracterisation of the display hang; the scpsys probe fix was real
but the remaining blocker lives in the DRM/mmsys/SMI layer.

**Update 2026-07-06 (build #86/#87 — DRM bind also exonerated; hang pinned
to `mtk_dsi_probe()` tail):** the bind-path trace never printed a single
line — the component master bind never starts. Since the panel prints
"registered" only after `mipi_dsi_attach()` returns, the hang window is the
remainder of `mtk_dsi_probe()` after `mipi_dsi_host_register()`: clock
lookups → ioremap → `devm_phy_get` → `devm_request_irq`. The ATF dump PC
resolves to `cpu_do_idle` on cpu1 (idle victim); cpu0 (probe CPU) never
dumps — it is the wedged core. Leading hypothesis: `devm_request_irq`
unmasks the DSI IRQ while LK's splash has left the DSI engine live; a
stale/screaming interrupt wedges cpu0 in `mtk_dsi_irq()` (unclocked
`readl(DSI_INTSTA)`, unbounded `while (DSI_BUSY)` spin). Testing with build
#88 (`patches/v6.6/drm/0006-GEMINI-DEBUG-dsi-probe-tail-and-irq-trace.patch`).
See boot.md "BUILD #86/#87".

**Update 2026-07-06 (build #88/#89 — probe tail clean, IRQ-storm hypothesis
REFUTED; entire display stack exonerated):** every dsi probe-tail step
completed; the DSI IRQ fired exactly once (INTSTA=0x2 = CMD_DONE, handled
cleanly, no storm); the panel registered. Since `mipi_dsi_attach()` runs
before the panel's "registered" print and calls `mtk_dsi_host_attach()` →
`component_add`, the DRM master bind attempt had already happened and
deferred (no IOMMU) before that print — so scpsys (#84), DRM bind (#86) and
dsi probe/IRQ (#88) are all exonerated. cpu0 wedges with IRQs masked ~50ms
after the panel print in unmarked code (cpu1's ATF dump PC again resolves to
`cpu_do_idle` — idle bystander). Next: build #90 boots with `initcall_debug`
on the cmdline so the last `calling <fn>` line names the wedging function
directly. See boot.md "BUILD #88/#89".

**Update 2026-07-06 (build #92/#93 — wedging initcall identified:
`cacheinfo_sysfs_init`; culprit is an unresponsive secondary CPU):**
`initcall_debug ignore_loglevel` shows the display path completing and
returning (`probe of 1401c000.dsi.0 returned 0`, `r63419_driver_init
returned 0`), then the last line is `calling cacheinfo_sysfs_init` before
the 14s watchdog. That initcall's `cpuhp_setup_state()` waits on every
online CPU's hotplug thread in turn — cpu0 is blocked waiting, not wedged
itself. So the display build's real defect is that it silently wedges a
*secondary* CPU (cpu1–7) somewhere before 2.4s — scpsys domain writes or
display clock enables are prime suspects. Build #94
(`patches/v6.6/base/0001-GEMINI-DEBUG-cacheinfo-cpuhp-per-cpu-trace.patch`
+ `rcupdate.rcu_cpu_stall_timeout=6`) identifies which CPU. See boot.md
"BUILD #90–#93".

**Update 2026-07-06 (build #94/#95 — secondary-CPU hypothesis REFUTED; the
wedged CPU is cpu0 itself, unresponsive to IRQs):** the RCU stall report
fired at 8.4s and names **cpu0** as the stalled CPU, *detected by cpu4*
(cpus 1–7 are alive and healthy). Not one `cacheinfo_cpu_online` trace
print ran (strings confirmed in the packed kernel), so init blocks in
`cpuhp_setup_state()` waiting for the `cpuhp/0` thread — pinned to cpu0 —
which never runs because cpu0 stops taking interrupts at ~2.42s (RCU's 750
fqs attempts all failed). The remote task dump is useless (`__switch_to` /
`0x0` — no NMI on arm64 by default). So the display build kills interrupt
delivery/wakeup specifically for cpu0: GIC redistributor, cpu0's arch
timer, or a lost wakeup — plausibly a side effect of scpsys bus-protect
writes (the known wrong MT6797 bits) or a display clock change. Build #96
adds pseudo-NMI (`CONFIG_ARM64_PSEUDO_NMI=y` in
`configs/gemini-debug-b13.config` + `irqchip.gicv3_pseudo_nmi=1`, GIC is
v3) so the stall handler can NMI-backtrace cpu0 and show its real PC. See
boot.md "BUILD #94/#95".

**Update 2026-07-06 (build #96/#97 — pseudo-NMI REVERTED, regressed boot):**
`CONFIG_ARM64_PSEUDO_NMI=y` + `irqchip.gicv3_pseudo_nmi=1` broke boot
*earlier* than the bug it was meant to diagnose: total silence from
`el3_exit` (4.37s) to the ATF watchdog (14.38s), not even the earlycon
banner — this device's ATF/GIC evidently doesn't tolerate pseudo-NMI's
early priority-mask setup. Reverted (`configs/gemini-debug-b13.config`
removed, cmdline flag dropped). cpu1's ATF dump is the same
`cpu_do_idle`/`arch_cpu_idle` bystander as every prior build — no new data.
**Next:** an IPI heartbeat probe (kthread on cpu1 pinging cpu0 via
`smp_call_function_single` every ~50ms from early boot) to pinpoint exactly
when cpu0 stops acking IPIs, without touching NMI/GIC priority masking. See
boot.md "BUILD #96/#97".

**Update 2026-07-06 (build #98/#99 — cpu0's death window pinpointed to
2.48–2.54s; cpu0 loses ALL interrupt responsiveness, not one code path):**
the IPI heartbeat ran clean every 60ms from 0.72s to 2.4799s (seq 30), then
missed by 2.5399s (seq 31) — death lands inside `cacheinfo_sysfs_init`
(called 2.4237s) but well after it starts, so cpu0 is alive when that
initcall begins. Crucially, this heartbeat uses a *different* IPI mechanism
(`smp_call_function_single`) than the `cpuhp/0` thread wakeup cacheinfo
needs, and both fail in the same window — so cpu0 is losing the ability to
take **any** interrupt, not failing a specific code path. This also shifts
timing suspicion from the scpsys domain-power writes (done by 2.12s, now
~360ms earlier) toward the DSI/panel probe (2.412–2.419s, only 60–120ms
before death) as the more temporally-proximate trigger, though scpsys
remains the leading root-cause candidate for *why*. **Next:** tighten the
heartbeat to 10ms and add a periodic cpu0 GICR_WAKER read (GICv3
redistributor sleep-state register) to test whether the display build is
corrupting the GIC redistributor for cpu0 directly. See boot.md "BUILD
#98/#99".

**Update 2026-07-06 (build #100/#101 — GICR_WAKER refuted; death window now
20ms, 2.513s-2.533s):** `gicr0_waker=0x0` on every reading right up to the
final MISS — cpu0's redistributor never sleeps, so the "display build
corrupts/sleeps the GIC redistributor" hypothesis is refuted. With the GIC
confirmed healthy, cpu0 losing both a raw IRQ-context IPI callback and the
`cpuhp/0` kernel-thread dispatch (`kernel/cpu.c`
`cpuhp_invoke_ap_callback`/`__cpuhp_kick_ap`) at the same moment now points
to cpu0 either stuck in genuine WFI/idle without waking (cpuidle/PSCI
CPU_SUSPEND bug) or actually running/spinning with interrupts effectively
undeliverable (masked-IRQ-forever bug), rather than a GIC hardware fault.
**Next:** add `idle_cpu(0)` to the heartbeat (cheap scheduler-state read,
no IPI) to distinguish the two. See boot.md "BUILD #100/#101".

**Update 2026-07-06 (build #102/#103 — WFI-never-wakes REFUTED; cpu0 wakes
normally then hard-locks within 20ms, before reaching cacheinfo):** cpu0
goes idle at 2.4235s (matching `cacheinfo_sysfs_init`'s dispatch almost
exactly), sits idle ~100ms (unusually long for a routine wakeup), then
**wakes normally** at 2.523s (`idle_cpu(0)` flips back to busy) — the wake
mechanism itself works. Within 20ms of waking it's already unresponsive to
IPIs, and still shows `idle_cpu0=0` (busy, not asleep) at the miss — so this
is not a stuck-in-WFI bug; cpu0 hard-locks while actively running, before
its `cacheinfo_cpu_online()` entry trace ever fires (confirmed still
absent). The ~100ms idle-to-wake delay is itself abnormal and suggests
cpu0's wake path (broadcast/local arch timer) was already disturbed before
the hard lock. **Next:** arm an hrtimer pinned directly to cpu0 (independent
of the cross-CPU IPI heartbeat) to test whether cpu0's own local-timer
interrupt survives past the point where cross-CPU IPIs stop — this
distinguishes a fully halted CPU from an SGI/IPI-delivery-specific fault.
See boot.md "BUILD #102/#103".

**Update 2026-07-06 (build #104/#105 — cpu0's own local timer also dies;
build #106/#107 — SMI larb0/smi_common gating fix has NO effect; B-13
formally DEFERRED):** the pinned-hrtimer test confirmed cpu0's *own* local
timer interrupt dies at the same point as the cross-CPU IPI misses — this is
a genuine full hard lock of cpu0 (all interrupt sources, not an
SGI/IPI-delivery-specific fault). Last real evidence of forward progress is
still `calling cacheinfo_sysfs_init+0x0/0x40 @ 1`; nothing printk-reachable
runs after it.

Vendor-kernel forensics (extracted from `kali_boot.img`'s embedded 3.18
kernel image) suggested the display pipeline gates
`CG_MM_SMI_COMMON`/`DISP0_SMI_LARB0` clocks separately from scpsys's own
`CLK_MM`, and mainline had no MT6797 SMI compatibles at all
(`drivers/memory/mtk-smi.c`) so those clocks were never claimed by any
driver. Added `mediatek,mt6797-smi-larb`/`-common` (reusing MT6795/Helio X10
ops verbatim — no new logic) and enabled the corresponding `larb0`/
`smi_common` DTS nodes. Build #106, capture
`logs/2026-07-06-107-smi-mt6797-fix-boot.log`: DTB and vmlinux confirm the
fix compiled in correctly, but **the hang is bit-for-bit identical** — same
last initcall, same local-timer tick count at death, same heartbeat-miss
timing, same ATF watchdog dump timing — and neither SMI device ever shows a
`probe of ... returned` trace line (every other platform device does),
i.e. no observable bind attempt at all. The SMI hypothesis is falsified.

An ARM64 hardware lockup detector (`CONFIG_ARM64_PSEUDO_NMI`, needed to
NMI-backtrace the wedged cpu0) was already tried and reverted earlier
(build #96/#97): it regresses boot *earlier* than this bug (silence
immediately after `el3_exit`, before earlycon even prints), so this
hardware's ATF/GIC combination does not tolerate pseudo-NMI's priority-mask
setup. Retrying it requires independently validating ATF support first —
not a quick diagnostic.

**Conclusion: every register/driver-level hypothesis sourced from either the
vendor kernel or mainline's own display stack has now been tested — scpsys
power-on sequence, DRM component bind, DSI probe tail, and SMI bus-master
gating — and none moved the hang. The only remaining diagnostic (NMI-based
backtrace) is independently blocked by an ATF incompatibility. B-13 is
formally deferred** per CLAUDE.md principle 5 (bootability first, display
explicitly optional). Reusing the vendor `dispsys`/DDP framework wholesale
was considered and rejected: it's a large 3.18-era subsystem (mtkfb/ion/CMDQ
APIs with no 6.6 equivalent) whose *sequence* we already proved doesn't
matter here (scpsys and SMI sequence-parity tests both changed nothing), so
a port would most likely hit the identical hard lock while adding
significant vendor-code maintenance burden — against CLAUDE.md principle 3.
Revisit only if new evidence emerges (e.g. upstream MT6797 display support
lands, or a future non-NMI diagnostic surfaces cpu0's actual PC at the
lock). See boot.md "BUILD #106/#107".

**Update 2026-07-06 (new evidence, PINNED for later — vendor Halium kernel
source located, SMI/M4U IOMMU-bypass gap identified as untested hypothesis):**
the actual community kernel source for this device was located at
`/Volumes/extdata/github/gemini-android-kernel-3.18` (`dguidipc`'s Halium
kernel, confirmed by the `Linux version 3.18.41+ (dguidi@nowhere)` banner
matching `/Volumes/extdata/scratch/debian`'s extracted kernel). Cross-checked
its `drivers/clk/mediatek/clk-mt6797-pg.c` (the real MTCMOS/scpsys-equivalent
driver, DIS domain at `SPM_REG(0x030c)`) against mainline's `mtk-scpsys.c`
sequence — **bit-identical**, third independent confirmation that scpsys
register sequencing is not the bug.

New lead not yet tested: `drivers/misc/mediatek/video/mt6797/dispsys/ddp_drv.c`
(`disp_probe_1()`, ~line 784) unconditionally writes `0x0` to
`DISP_REG_SMI_LARB0_MMU_EN`/`..._LARB5_MMU_EN` (`larb_base + 0xfc0`) to force
SMI-larb IOMMU bypass whenever M4U support isn't compiled in. Mainline has
**no MT6797 IOMMU driver at all** (checked `drivers/iommu/mtk_iommu.c` and
`mtk_iommu_v1.c` — no compatible string; our `mt6797.dtsi` has no `iommu`/
`m4u` node either), and the `mtk-smi` larb ops we reused from MT6795
(`mtk_smi_larb_config_port_mt8173`, since `mediatek,mt6795-smi-larb` maps to
`&mtk_smi_larb_mt8173` in `drivers/memory/mtk-smi.c`) only writes the
`MMU_EN` register from `mtk_smi_larb_bind()` — called by the component
framework **only when an IOMMU master binds to the larb**, which never
happens here. So on this hardware the larb's MMU_EN register is left at
whatever the power-on-reset default is (untranslated DMA through an
unconfigured/enabled M4U path is plausible), and the larb's own `.probe()`
likely parks in `-EPROBE_DEFER` forever waiting on a companion IOMMU that
will never arrive — independently consistent with build #106/#107's
observation that neither SMI device ever printed a `probe of ... returned`
line. This would explain the *delayed* hang signature: DSI/DDP register
writes (non-DMA MMIO) succeed and print cleanly, but a hang surfaces shortly
after, timing-wise consistent with the point the display hardware would
first issue a real DMA fetch through the larb.

**Deliberately not pursued yet — pinned for a future session.** Proposed
fix, when resumed: a small patch forcing `larb0_base+0xfc0 = 0` and
`larb5_base+0xfc0 = 0` (IOMMU bypass) before the DRM/DDP pipeline can issue
any DMA, mirroring the vendor's unconditional bypass write — either as a
fallback path in `mtk-smi`'s larb probe when no IOMMU master ever binds, or
as a board-specific quirk. This is a genuinely new, unfalsified hypothesis,
distinct from the already-exhausted scpsys/DSI-probe-tail/SMI-clock-gating
tests. Untested — no build/capture evidence for or against it yet.

**Update 2026-07-06 (implemented and built — build #108):** rather than a
board-specific quirk, fixed this generically in `mtk-smi.c` itself: added a
`mmu_bypass` field to `struct mtk_smi_larb`, defaulting `larb->mmu` to point
at it (zeroed) in `mtk_smi_larb_probe()`. Previously `larb->mmu` stayed
**NULL** whenever no `mtk_iommu` master ever binds (always true for MT6797,
which has no mainline IOMMU driver at all) — and `mtk_smi_larb_resume()`
unconditionally calls `config_port()`, which dereferences `*larb->mmu`,
i.e. this was a latent NULL-pointer-deref bug on any IOMMU-less SoC using
this larb ops table, not just a missing bypass write. The fix makes the
zero-value default double as the vendor's forced bypass behavior; a real
IOMMU binding still overwrites the pointer with the live per-port mask, so
no other SoC's behavior changes. Patch:
`patches/v6.6/memory/0002-memory-mtk-smi-default-mmu-bypass-when-no-iommu-bound.patch`.
Build #108 (`logs/2026-07-06-108-smi-mmu-bypass/`, banner `#27 SMP PREEMPT
Mon Jul 6 11:28:49 UTC 2026`, `ALLOW_DEBUG=1`) built clean and packed —
**not yet flashed/captured**.

Corroborating evidence found while re-checking the vendor Halium source
(`/Volumes/extdata/github/gemini-android-kernel-3.18`): its M4U driver
(`drivers/misc/mediatek/m4u/mt6797/m4u_hw.c`) has named functions
`m4u_enable_error_hang()`/`m4u_disable_error_hang()` toggling a
`F_MMU_CTRL_INT_HANG_en` bit in the M4U core's own `REG_MMU_CTRL_REG`, plus
a `m4u_dump_reg_for_smi_hang_issue()` debug helper — i.e. MediaTek's own
engineers have a named "SMI hang" failure mode where an unconfigured/
misconfigured M4U turns a translation fault into a literal bus hang instead
of a recoverable interrupt. This is independent corroboration of the
general failure class (M4U/SMI misconfiguration → bus hang, not just a
crash), though it's a separate register in the M4U *core* block, not the
per-larb `MMU_EN` bit build #108 targets. **Fallback note for later:** if
build #108's larb-level bypass doesn't resolve the hang, check whether the
M4U core's own `REG_MMU_CTRL_REG`/`INT_HANG_en` needs equivalent handling —
mainline never touches it either, since there's no MT6797 `mtk_iommu`
driver to own it.

**Next action:** flash build #108 to both `boot` and `boot2`, capture, and
compare against the bit-identical #106/#107 baseline (same last initcall,
same local-timer tick count, same heartbeat-miss timing) to see if the hang
signature changes at all.

**Update 2026-07-06 (build #108 flashed and captured twice — NO CHANGE,
B-13 remains deferred):** two boots captured from the same flashed image
(`logs/2026-07-06-109-smi-mmu-bypass-boot.log`, both banner `#27`). First
boot hung earlier/differently (before panel registration); a repeat capture
of the *same* image reproduced the #106/#107 baseline exactly (panel
registers, `cacheinfo_sysfs_init` runs, heartbeat MISS within a few jiffies
of baseline) — so the first boot's variance is run-to-run jitter, not a
fix effect. In both captures the SMI larb/common devices still never show
a `probe of ... returned` line, meaning the code path the fix touches
(`config_port()`) very likely never executed either time. **The fix is
kept** (`patches/v6.6/memory/0002-...patch` — it's a genuine latent
NULL-pointer-deref fix for any IOMMU-less SoC reusing this larb ops table,
harmless elsewhere) **but it does not resolve B-13.** See boot.md
"BUILD #108/#109" for full detail.

This closes out the last concrete, evidence-based hypothesis from the
vendor-source cross-check. The open question is now more fundamental than
IOMMU bypass: **why do the SMI larb/common devices never complete probe at
all**, for or against, across every build tested so far. No new hypothesis
is queued. B-13 remains formally deferred per CLAUDE.md principle 5
(bootability first, display optional) and the earlier
build #96/#97 pseudo-NMI ATF incompatibility. Device should be recovered to
`logs/2026-07-06-77-maxcpus8/new_kali_boot.img` (no display, known-good)
after this test.

**Update 2026-07-06 (vendor-console test — confirmed LK hardcodes
`printk.disable_uart=1`, no usable vendor dmesg obtainable this way):**
separately from the fix work above, tried to get a comparable *working*
display bring-up trace by capturing the vendor 3.18 kernel's own dmesg
over the same UART, to diff against our mainline failure logs. The one
full vendor boot capture on file
(`logs/2026-07-04-08-vendor-full-boot.log`, a visually-confirmed successful
boot to the Android desktop with working display) shows zero output past
`el3_exit` — already established as a "Pivotal Result" 2026-07-04 (silence
after `el3_exit` is not a failure signal for either kernel on this UART).
Root cause traced this session: the vendor 3.18 kernel's cmdline carries
`printk.disable_uart=1`, appended by the LK bootloader itself — not present
in the boot.img header's own cmdline field (`bootopt=64S3,32N2,64N2
log_buf_len=4M`) nor in the DTB's `bootargs` (checked
`docs/vendor-dtb/gemini_kali_boot.dts` line 11 — no `atag,printk-disable-uart`
property either).

Tested empirically with a new tool, `scripts/patch-vendor-cmdline.py`
(patches only the Android boot.img header cmdline field, byte-identical
kernel+ramdisk otherwise — confirmed via sha256): flashed
`OUTPUT/vendor-uart-test.img` (header cmdline appended with
`printk.disable_uart=0 ignore_loglevel`) to both `boot`/`boot2`, captured
twice (`logs/2026-07-06-111-vendor-uart-test-boot.log`, two power cycles,
`boot_reason=1` then `boot_reason=4`). LK's own boot log confirms it *did*
pick up the header override (`[LK_BOOT] Android Boot IMG Hdr - Command
Line: ...printk.disable_uart=0 ignore_loglevel`), but the final merged
cmdline handed to the kernel has LK's own `printk.disable_uart=1` appended
**after** it (`...printk.disable_uart=0 ignore_loglevel
androidboot.veritymode=enforcing printk.disable_uart=1 bootprof...`) — the
later occurrence wins, so the override is clobbered every time. Both boots
end at `el3_exit` with nothing further, identical to the untouched
baseline.

**Conclusion:** LK unconditionally enforces `printk.disable_uart=1` for
`buildvariant=user` regardless of boot.img header content. Getting a real
vendor-kernel dmesg trace would require patching LK's own binary (a
proprietary, unsourced blob — out of scope per CLAUDE.md's upstream-first
principle, and high-risk to the boot chain for a deferred/optional Phase 5
item) or finding a different debug channel entirely (e.g. `pstore`/
`last_kmsg` on a data partition, or `adb logcat` if the ramdisk's USB
gadget supports it). No further action queued; B-13 remains deferred with
no vendor-side comparison log available. **Device left flashed with
`vendor-uart-test.img` on both `boot`/`boot2` per explicit instruction —
not yet recovered to the known-good mainline `maxcpus=8` build.**

---

## 🟡 B-14 — Software reboot does not reset the SoC (hangs after `reboot: Restarting system`)

**Opened:** 2026-07-05. **Severity: low** — hard power-cycle works; costs
convenience, not progress. Not a Phase 4/5 gate.

**Evidence:** boot.md EIGHTEENTH RESULT
(`logs/2026-07-05-39-reboot-test-boot.log`). A clean systemd shutdown ran to
completion; the final line is `reboot: Restarting system`
(`machine_restart()`), then nothing — no preloader/LK output, manual
power-cycle required. The mtk-wdt, left armed by systemd-shutdown as a
backstop (`watchdog did not stop!`), also never fired.

**Candidate mechanisms (undistinguished):**
1. Vendor ATF's PSCI `SYSTEM_RESET` hangs given the SoC state our 6.6 boot
   leaves behind (`maxcpus=1`, `clk_ignore_unused`, no scpsys domains) —
   plausibly the same PSCI/SPM oddity behind the B-list SMP secondary-CPU
   hang.
2. The mainline mtk-wdt `restart_handler` (toprgu `WDT_SWRST`) is what
   actually ran and it fails/deasserts on MT6797 — it may also explain the
   silent watchdog (the handler reprograms `WDT_MODE` first).

**Next diagnostic step:** on a live system check `/sys/kernel/reboot` (or
boot once with `initcall_debug`/restart-handler tracing) to learn whether
PSCI or mtk-wdt owns the restart; then test the other path via the `reboot=`
cmdline parameter. Revisit alongside the `maxcpus=1` SMP fix — if PSCI
`CPU_ON` is broken, PSCI `SYSTEM_RESET` being broken too would point at a
single ATF-interface cause.

---

## 🟢 B-15 — RESOLVED: apparent mtu3/T-PHY "hang" was the documented UART/USB mux switching, not a driver bug

**Opened & resolved same day: 2026-07-05.** No hardware or driver fix
required — this is a methodology note, kept as a blocker entry because it
cost ~13 build iterations (#40–#52) before being correctly diagnosed.

**Symptom:** every build from #40 onward appeared to hang (silent console,
eventual watchdog reset) at the same point — the first SIF register touch in
mainline `mtk-tphy`'s U2 PHY init, immediately after clearing
`FORCE_UART_EN`/`FORCE_SUSPENDM` in the shared PHY control register.

**Investigation path (see boot.md TWENTY-FIRST through TWENTY-FIFTH RESULT):**
missing bus clock → traced to first SIF read → IPPC power state → port
PDN/HOST_SEL → PMIC MT6351 rails (VUSB33/VA10) all ruled out in turn by
builds #40–#47, each with targeted register dumps that showed the hardware
state was correct at every step.

**Root cause:** `FORCE_UART_EN` is a literal hardware mux-select bit — the
Gemini's left USB-C port shares one physical differential pair between the
UART console and USB2 D+/D− (documented in CLAUDE.md Phase 8 note since
build #40, but not connected to this symptom until build #52). Mainline
`mtk-tphy` correctly clears this bit as part of normal U2 PHY bring-up. Doing
so switches the mux away from the console mid-boot, so all serial output
after that line vanishes — indistinguishable from a hang if you assume the
console keeps working. Build #52
(`logs/2026-07-05-58-ssusb-mux-recovery-test`) proved this by re-setting
`FORCE_UART_EN` after the "hang" point and observing the debug line reappear
250ms later, unchanged.

**Fix:** none needed — reverted all debug instrumentation for a clean build
(#53, `logs/2026-07-05-60-ssusb-clean-no-debug`). Verified working via the
single-cable-swap protocol (serial *or* direct-to-Mac USB-C, never both):
gadget enumerates as RNDIS on the Mac, gets an IP, ping and SSH succeed. See
boot.md TWENTY-SIXTH RESULT.

**Lesson for future USB/mux debugging on this platform:** if a boot
"hangs" immediately after a T-PHY/mux-adjacent register write, first check
whether it's actually a console-mux transition (test by reconnecting via the
non-serial path) before spending cycles on power/clock/PMIC forensics.

---

## 🟡 B-16 — Cortex-A72 cluster (CPU8/CPU9) PSCI `CPU_ON` hang: separate from B-13, root cause unknown

**Opened 2026-07-06** (split out from item 4 under B-2/Phase 3, which had
speculatively lumped this in with B-13).

**Symptom:** with no `maxcpus` cmdline limit, CPU0–7 (both Cortex-A53
clusters) bring up cleanly in ~35ms, but the PSCI `CPU_ON` SMC issued for
CPU8 (first Cortex-A72 "big" core) never returns. ~14s later ATF's own
watchdog fires (`aee_wdt_dump`, `Kernel WDT not ready`) and the board
reboots. This is an ATF (BL31) firmware hang, not a Linux-side defect — the
boot CPU blocks inside the SMC instruction itself. See boot.md "PSCI CPU_ON
diagnostic".

**Workaround in place:** `configs/gemini-cmdline.config` uses `maxcpus=8`,
which avoids the A72 cluster entirely and boots all 8 A53 cores cleanly
(validated `logs/2026-07-06-77-maxcpus8/`). This is the current baseline;
full 10-core SMP is not required for bootability.

**Originally hypothesized** to share B-13's root cause (both symptoms being
"a power domain never comes up"). **Disproven 2026-07-06** (boot.md "BUILD
#11", `logs/2026-07-06-82-cpu8-scpsys-retest/`): before testing, checked the
actual MT6797 scpsys domain table
(`drivers/pmdomain/mediatek/mtk-scpsys.c`, `scp_domain_data_mt6797[]`) and
found it defines no CPU-cluster/MP power-domain entry at all — only
`VDEC`/`VENC`/`ISP`/`MM`/`AUDIO`/`MFG_ASYNC`/`MJC`. So the scpsys driver
(and its NULL-name probe-abort fix, B-13) has no code path that could
influence A72 cluster power-on. Confirmed empirically: built with the B-13
fix applied, display fragment excluded (to isolate the variable), and no
`maxcpus` limit — the resulting boot hung with the byte-for-byte identical
signature as before the fix existed
(`logs/2026-07-06-83-cpu8-scpsys-retest-boot.log`, 8 reboot cycles).

**Status: root cause narrowed 2026-07-06** (previously "unknown") via read-only
analysis of a third-party vendor kernel image — the Planet Computers Gemini
Debian/Halium build (`debian_boot.img`, 3.18.41, downloaded by the user to
`/Volumes/extdata/scratch/debian/`, not part of this repo). That kernel's
`strings` output retains full debug source paths (built by
`dguidi@nowhere`, `/home/dguidi/Desktop/Kernel/kernel-3.18/...`), which is how
this was extracted — no source tree itself was recovered, only build-time
path/log strings baked into the binary.

**Finding:** the vendor 3.18 kernel does not bring up the A72 cluster via a
plain unconditional PSCI `CPU_ON` at boot the way our mainline `psci.c` does
for every `possible` CPU. It has an entire vendor-only subsystem for this,
absent from mainline in every respect (confirmed: no `mcucfg`/`idvfs` nodes in
mainline's `mt6797.dtsi`, none in our `mt6797-gemini-pda.dts` — see "PSCI
CPU_ON diagnostic" in boot.md):

- `drivers/misc/mediatek/base/power/mt6797/mt_hotplug_strategy_{main,algo,cpu,ops_mt6797}.c`
  — a load-based governor that decides *when* to online/offline the A72
  cores; the big cluster is not simply "on" from boot.
- `drivers/misc/mediatek/base/power/mt6797/mt_idvfs.c` — "IDVFS" (Intelligent
  DVFS): sets up an **SRAM LDO + PLL for the big cluster over I2C6** before
  the cluster can run. Log strings recovered from the binary confirm this is
  a hard precondition, not best-effort: `"[mt_idvfs] FAILED TO PREPARE I2C
  CLOCK (%u). iDVFS only 750MHz."`, `"[mt_idvfs] SRAM LDO setting = %u(x100mv)
  success."`, `"[mt_idvfs] Error: SRAM LDO volte = %umv, out of range
  500mv~1200mv."`
- `mt_cpufreq.c` / `mt_cpufreq_hybrid.c` — cluster-specific DVFS built on top
  of the above.
- A **CPU-HVFS hardware sequencer**, kicked by a `swctrl` register write, that
  actually powers a cluster on — separate from and prior to any PSCI
  `CPU_ON`: `"[CPUHVFS] (%u) [%08x] cluster%u on, pause = 0x%x, swctrl =
  0x%x (0x%x)"`, plus a `cspm_cluster_notify_on` symbol.

**Refined hypothesis:** mainline's generic `psci_cpu_boot()` just issues the
SMC and assumes ATF handles everything. On this SoC, ATF's `CPU_ON` for an A72
core plausibly expects the "big cluster ready" precondition (voltage/PLL
settled) — normally driven from Linux by `mt_idvfs`/CPU-HVFS `swctrl` — to
already be true. Our kernel never drives any of that, so the SMC blocks
forever waiting on a state nothing ever sets. This would mean the hang is not
an ATF firmware bug but firmware correctly waiting on a real precondition —
narrowing the fix path from "maybe impossible without vendor ATF source" to
"port (or minimally reimplement) the `mt_idvfs`/CPU-HVFS pre-hotplug voltage
sequencing," though this is not yet confirmed against real register-level
behavior on this hardware and no code has been written yet.

**Not yet done:** no register addresses, I2C6/PMIC-wrap sequence details, or
CPU-HVFS `swctrl` offsets have been extracted — only log-string evidence that
these subsystems exist and gate cluster power-on. Next step if this is
pursued: locate the actual register writes (vendor kernel binary
disassembly, or the vendor DTB's `mcucfg`/`ptp3_idvfs` `reg`/`clock` values
already on file in `docs/vendor-dtb/gemini_kali_boot.dts`) before attempting
any kernel-side sequencing code.

**Recovery:** re-flash `logs/2026-07-06-77-maxcpus8/new_kali_boot.img` (sha256
`4643f685358efdaca7db5ac12e5ab8721f35c081ece18821801b8de46dc28078`) to both
`boot` and `boot2` if a full-SMP test build leaves the device in a reboot
loop. Verify recovery with a fresh capture showing the `#8` kernel banner
before relying on the device being back to a good state.

---

## 🟡 B-17 — DRM atomic commit never completes (`flip_done`/vblank timeout loop), panel stays dark

**Opened 2026-07-08**, split out of B-13 once B-13's original scope (cpu0
hard-lock + `-517` DSI-attach probe-defer) was confirmed fully resolved
(see B-13's "Update 2026-07-08" above and boot.md "BUILD #161 recheck / new
blocker found: mtk_mipi_tx D-PHY probe EBUSY").

**Correction 2026-07-08 (same day, live SSH investigation on build #159):**
the D-PHY `-EBUSY` this blocker was originally opened around is a **red
herring**, not the cause. Live check on the running device:
```
# /proc/iomem
10215000-1021508f : 10215000.mipi-dphy mipi-dphy@10215000
# /sys/kernel/debug/clk/clk_summary
mipi_tx0_pll   1  1  1  927504000  0  0  50000  ?
```
The D-PHY *is* bound (built in via `CONFIG_PHY_MTK_MIPI_DSI=y`) and its PLL
is running live at 927.5 MHz — proof the real, built-in copy of
`mediatek-mipi-tx` probed successfully. The `-EBUSY`/"already registered"
message logged later at boot is a **second, stale registration attempt**:
`/lib/modules/6.6.0-dirty/kernel/drivers/phy/mediatek/phy-mtk-mipi-dsi-drv.ko`
is a leftover `.ko` from an earlier build configuration (when this driver
was `=m`) still present on the rootfs; something (module autoload/coldplug
replay) tries to insert it after the built-in driver already owns the
`"mediatek-mipi-tx"` driver name, and the second registration is correctly
rejected. Harmless duplicate-load noise — not a probe failure of the real
D-PHY, and not the reason the panel stays dark. (Cleanup: the stale `.ko`
should be removed from the rootfs module tree in the next `mkrootfs.sh`
run so this noise stops appearing in logs.)

**Actual symptom (root cause still open):** on build #159 (banner #48),
with live SSH access confirmed and the full DSI/panel/D-PHY/DRM bind chain
completing successfully — DSI host attaches on deferred retry after ~62s,
`panel-solomon-ssd2092 1401c000.dsi.0: Solomon SSD2092 FHD DSI panel
registered`, `probe of 1401c000.dsi.0 returned 0`, `fb0: mediatekdrmfb`
created, `GEMINI-DEBUG bind: complete` — every DRM atomic commit (driven by
the fbdev helper's hotplug retry) times out waiting for vblank/flip
completion, in an infinite ~10-second-period loop:
```
mediatek-drm mediatek-drm.1.auto: [drm] *ERROR* flip_done timed out
mediatek-drm mediatek-drm.1.auto: [drm] *ERROR* [CRTC:51:crtc-0] commit wait timed out
mediatek-drm mediatek-drm.1.auto: [drm] *ERROR* [PLANE:33:plane-0] commit wait timed out
mediatek-drm mediatek-drm.1.auto: [drm] *ERROR* [CONNECTOR:32:DSI-1] commit wait timed out
[drm:mtk_drm_crtc_atomic_begin] *ERROR* new event while there is still a pending event
WARNING: ... drm_atomic_helper_wait_for_vblanks.part.0+0x23c/0x260
```
System otherwise remains stable and fully reachable over SSH throughout —
this is not a hang, just a permanently-dark, permanently-retrying display
pipeline. No panel-driver `prepare`/`enable` activity (regulator/reset/init
command sequence) is visible in the default-level kernel log — this is
expected at default log level (no dynamic-debug enabled for
`panel-solomon-ssd2092.c` or `mtk_dsi.c`), not evidence they were skipped.

**Not yet investigated:** why the CRTC never produces a real vblank/frame.
Leading candidates, in the order they should be checked next:
1. Whether `drm_panel_prepare()`/`drm_panel_enable()` are actually being
   invoked by the DSI bridge's atomic enable path, and whether the SSD2092
   init command sequence (`panel/0005-drm-panel-add-solomon-ssd2092-fhd-panel.patch`)
   completes or errors silently — enable `dyndbg` for both `mtk_dsi.c` and
   `panel-solomon-ssd2092.c` on the next boot to see this.
2. Whether the DSI host's own vblank/TE (tearing-effect) IRQ path is
   correctly configured post-B-13 fix (patch
   `0008-…-dsi-keep-irq-disabled-b13-test.patch` intentionally holds the IRQ
   masked until DSI power-on — confirm it is actually unmasked again once
   the pipeline reaches enable, otherwise no vblank can ever fire by
   construction).
3. Whether `disp_ovl0`/`mutex`/`disp_rdma0` etc. actually reach a running
   state (their `status = "okay"` in `dts/0001` doesn't guarantee correct
   runtime configuration) — cross-check the vendor 3.18 `dispsys`/DDP
   config sequence for post-power-on register pokes not yet ported.
The vendor 3.18 source (`/Volumes/extdata/github/gemini-android-kernel-3.18`,
per CLAUDE.md) remains the reference for whichever of the above needs a
concrete register/sequence answer.

**Recovery:** no special recovery needed — the system remains stable and
SSH-reachable with this failure present; it is a rendering-pipeline stall,
not a hang or crash. Current known-good baseline is build #159 (`boot`/
`boot2` identical, flashed 2026-07-08).

**Update 2026-07-08 (evening) — debug build #164 (candidate #1 trace) itself
appears to hang/stall before reaching USB gadget config:** built and flashed
`patches/v6.6/zz-debug/0001-GEMINI-DEBUG-dsi-panel-enable-trace.patch`
(candidate #1 from the list above — `pr_info()` inside `mtk_dsi_irq()` on
every fire, plus `dev_info()`/`pr_info()` traces in `mtk_dsi_poweron`,
`mtk_output_dsi_enable`, the bridge `atomic_enable`/`atomic_pre_enable`
callbacks, and `ssd2092_prepare`/`enable`/`get_modes`). Packed as build #164
(banner #53, `ALLOW_DEBUG=1` — the pack script's debug-instrumentation gate
correctly caught this and required the override).

Across multiple flash/power-cycle attempts, build #164 **never presented a
USB gadget device at all** (`ioreg` showed nothing but the always-attached
FTDI serial adapter — no RNDIS/Ethernet Gadget, ever, at any point). Serial
capture couldn't help distinguish "still booting" from "genuinely stuck",
because the UART/USB mux cutoff (`mtu3` driver flipping the mux register
during its own probe, ~0.44-3.0s kernel time) happens in software
regardless of which cable is physically connected — confirmed this session
by capturing with the FTDI left connected throughout (no swap), which still
cut off at the identical point as every prior capture.

**Control test:** reflashed known-good build #159 (banner #48, no debug
instrumentation) on both `boot`/`boot2` with no other change. RNDIS gadget
enumerated normally, link came up, `ping` and `ssh root@10.15.19.82`
succeeded immediately (`uname -a` confirmed banner #48). This isolates the
stall to something specific about build #164, not a Mac-side/cable/RNDIS-
service problem (a stale macOS network service was also removed and USB
services restarted along the way, with no effect on #164 — ruling out
Mac-side state as the cause).

**Working hypothesis:** the `pr_info()` inside `mtk_dsi_irq()` is the prime
suspect. If DSI's IRQ (SPI 229) is firing at high frequency — which is
exactly candidate #2's concern, IRQ storming — a synchronous console print
on every fire from interrupt context could starve the CPU badly enough that
boot never reaches the point of configuring the USB composite gadget
(which happens from userspace, well after kernel init). This would
actually be a positive result for root-causing B-17 (confirms the IRQ is
storming) if true, but the trace as written can't get the data out to
confirm it, since it may itself be the reason nothing further happens.

**Next step:** rate-limit the IRQ trace (`pr_info_ratelimited()` instead of
unconditional `pr_info()`, and/or a bounded per-boot counter) so it can
report whether the IRQ is storming without adding enough overhead to stall
boot outright. See `patches/v6.6/zz-debug/` for the revised patch.

**Update 2026-07-08 (later same evening) — IRQ-storm hypothesis inconclusive
after three isolation builds; reframed by a known-good build ALSO failing:**
followed the isolation path above through three further debug builds, each
flashed and captured on hardware:
- **Build #168** (`patches/v6.6/zz-debug/0001-...patch` v2, banner #54): same
  full trace set as #164 but with the `mtk_dsi_irq` print rate-limited via an
  `atomic_long_t` fire counter (log only the 1st and every 4096th fire). Did
  not reach USB gadget networking.
- **Build #170** (v3, banner #55): stripped to *only* the rate-limited IRQ
  counter — every other trace point removed, to isolate whether the IRQ
  print alone (regardless of frequency) was the problem. Still did not reach
  USB gadget networking.
- **Build #172 / #174** (v4, banners #56/#58): added an IRQ-storm circuit
  breaker (`disable_irq_nosync()` once the fire count crosses 200000,
  guarded by `atomic_xchg` so it only fires once) so that even a genuine
  storm would be forcibly broken and boot could proceed regardless of root
  cause. #174 additionally carried the pstore config fix (see below). Neither
  build reached USB gadget networking.

**Critical pivot:** after build #174 also failed, known-good build **#159**
(previously reliable, zero debug instrumentation, the same image that
isolated #164 in the first control test above) was reflashed as a sanity
check — and **it also failed to bring up the USB gadget, and the device
self-reset unprompted**. This directly contradicts the working hypothesis
that the debug patches (IRQ storm / print-in-ISR starvation) were
responsible: #159 has none of that code and failed anyway. A follow-up
serial-only sanity capture (build #177, no USB involved) confirmed the board
itself boots completely normally on this same #159 image — clean banner,
reaches the expected `mtu3`/mux cutoff at ~2.99s, no panics or anomalies —
ruling out a boot-level kernel hang. So the board boots fine; specifically
USB-C data enumeration/link-up was failing intermittently across every build
tried late in this session, including known-good ones.

**Working hypothesis revised: marginal battery / power delivery, not
software.** The user observed the device's battery had not been charging
throughout the session's many flash/power-cycle operations and was very low.
A low/marginal battery would explain the whole pattern independent of which
kernel was flashed: brownout-induced resets under a current spike (USB
gadget enumeration, display init, CPU ramp), USB data-line negotiation being
the first thing to suffer when the rail is marginal, and a previously
reliable build suddenly failing with no code change. This is considered the
leading explanation for the late-session #164/#168/#170/#172/#174/#159
failures as of 2026-07-08, superseding the IRQ-storm hypothesis as the
primary suspect (though the IRQ-storm circuit breaker and rate-limited trace
remain harmless/available in `patches/v6.6/zz-debug/` if needed again).
**Not yet confirmed** — next step is to retest once the device has had a
proper charge: reflash the known-good baseline (build #178/banner #63, see
below) and confirm consistent gadget enumeration and SSH reachability across
multiple power cycles.

**Unrelated fix folded in this session — stable gadget MAC address:**
separately, `CONFIG_USB_ETH` is built in (`=y`), so `g_ether` had no
persistent MAC and randomized one on every boot; macOS keys its Ethernet
"service" identity off the MAC, so every boot produced a brand-new `enNN`
interface and network service, making "is the gadget really not coming up"
indistinguishable from "it came up as a different interface than expected."
Fixed via `g_ether.dev_addr=42:00:15:19:82:01 g_ether.host_addr=42:00:15:19:82:00`
added to `CONFIG_CMDLINE` in `configs/gemini-cmdline.config` (built-in
drivers still honor `<modname>.<param>=` on the kernel cmdline). Also folded
in: `configs/gemini-pstore.config` (new file) enabling `CONFIG_PSTORE_RAM`/
`CONFIG_PSTORE_CONSOLE`/`CONFIG_PSTORE_PMSG` — the `ramoops@44410000`
reserved-memory node already existed in `dts/0001` (matches the vendor's own
pstore region for dual-boot safety) but the kernel config to actually back
it with pstore had never been enabled. Both changes built cleanly with debug
instrumentation removed, packed as **build #178 (banner #63,
`logs/2026-07-08-178-stable-boot-fixed-mac/`, sha256
`eeca62d1ef9cddbbdc825c63b708568870f2b669e407eb43f55448c00c2e1b7c`)** —
this is the current baseline pending the battery-recharge retest above.

**Also investigated, dead end:** while troubleshooting the late-session USB
failures, checked whether stock Android's `/proc/last_kmsg` (via `adb shell`
in a production, non-rooted build) held anything from the #159 self-reset —
it only contained an empty ram-console header (`hw_status: 0`, no crash
recorded), and `/sys/fs/pstore/` was inaccessible without root. Android's
ram-console format is unrelated to the Linux pstore/ramoops format just
enabled above (different formats, even sharing the same physical region), so
this path can't retroactively explain the #159 reset — only a future boot
with build #178's pstore config, followed by a crash, followed by *our own*
kernel's `/sys/fs/pstore/` would be informative.

**Update 2026-07-09 — retested post full scatter-file reflash; gadget/SSH
failure reproduces even on a known-clean baseline, battery hypothesis now in
doubt:** the Gemini was fully restored to stock (SP Flash Tool + scatter
file, all partitions incl. `boot`/GPT back to factory Android/Kali) and
confirmed RNDIS worked fine on the Linux workstation with the *stock* image.
Build #178 (banner #63, same sha256 as above) was then reflashed to `boot2`
fresh against this known-clean baseline (`logs/2026-07-09-181-post-scatter-
reflash-boot2.log`). Kernel boot itself is clean — same banner, same benign
`-517` DSI defer, reaches the same `mtu3` mux-cutoff point with no
anomalies — but the `g_ether` gadget again enumerates on the Mac with the
correct fixed MAC (`en12`, `42:00:15:19:82:00`) and then sits at `status:
inactive` indefinitely; no ping/SSH to `10.15.19.82`. This is the **same
symptom** as the pre-reflash failures this blocker attributed to a low
battery — but now reproduced immediately after a full factory restore and a
presumably-charged battery (device was freshly reflashed, not sitting idle
draining). This weakens the battery-only explanation: either the battery
issue is still present independently of state, or there is a genuine
software-side regression in how `g_ether`/CDC networking comes up under
Linux 6.6 on this device that coincidentally overlapped with the low-battery
period. **Not yet root-caused** — next step is to get a shell some other way
(serial console login, if enabled, or checking `dmesg`/journal for the
`g_ether`/`dwc3`/`mtu3` gadget-side attach sequence) rather than relying on
inferring gadget health purely from the Mac-side link state.

**Aside — LK splash successfully reaches the panel (2026-07-09):** during
this same boot, the user observed the screen flash briefly with color (no
text) a few seconds after power-on. Log analysis shows this came from LK's
own bootloader-side display driver (`DDP/mgr`/`videolfb` lines, ms-based
timestamps, *not* the Linux kernel's `[   0.xxx]` log) actively binding
`ovl0`→`dsi0` and loading `lcmname = aeon_ssd2092_fhd_dsi_solomon` around the
4.1s mark — well before `Linux version 6.6...` even prints. The Linux
kernel's own DRM/DSI probe in the same log still fails with the same benign
`-517` EPROBE_DEFER it always has. This is useful confirming evidence for
B-17: the DSI physical link, panel, and LK's own driver can successfully
push real pixels to this exact panel, so "colorful, no text" is most likely
LK loading a corrupted/uninitialized logo buffer, not an electrical/panel
fault — the still-open problem is purely getting the *Linux* DSI driver past
its own probe-defer, not proving the hardware path works (it already does).

**Update 2026-07-09 — build #159 (previously verified live-SSH) now
reproduces the identical gadget failure, ruling out #178's changes as the
cause:** reflashed `boot2` with build #159 (banner `#48`,
`logs/2026-07-07-159-ovl-larb-devicelink/new_kali_boot.img`, sha256
`09b2ea91a80e850c099fcf5dfe958a89033129e18983871f3b96f384ffe06b98`) — the
same image that was live-SSH validated in an earlier session (this blocker's
"Critical pivot" note above) — as a control against build #178. Two boot
attempts landed on the stock **Android** `boot` partition instead of `boot2`
(confirmed by the dumped LK cmdline: `androidboot.hardware=mt6797
buildvariant=user printk.disable_uart=1`, not our Linux cmdline) before a
third attempt correctly reached `boot2` (`logs/2026-07-09-182-build159-post-
scatter-recheck.log`, confirmed by `Linux version 6.6.0-dirty ... #48 SMP
PREEMPT Tue Jul  7 10:13:15 UTC 2026` at kernel time 0). Boot itself is
clean, same `mtu3` mux-cutoff point as always.

Result: **identical failure to #178.** `ioreg` confirms the USB gadget
device itself enumerates on the Mac (`RNDIS/Ethernet Gadget`, `active`,
matched), `en12` is created, but `unified log` shows the actual link-layer
state: `configd: (IPConfiguration) MANUAL en12: status = 'media inactive'`
— i.e. this is not an IP/DHCP/routing problem, it is the USB
CDC/RNDIS **carrier/link** signal itself never asserting from the Gemini
side, even though USB enumeration (descriptors, driver match) succeeds.
Same result on both #159 and #178 rules out every software delta introduced
between them (fixed-MAC cmdline, pstore config, all the DSI-IRQ debug
patches) as the cause. Remaining candidate explanations, in order of
likelihood:
1. **Battery/power** (original hypothesis) — still not conclusively ruled
   in or out; the device read ~42% at the time of this test, healthier than
   the earlier near-dead state, but marginal current-delivery under USB
   enumeration load can't be excluded without a controlled bench-supply test.
2. **Physical layer** (cable, port, or connector wear) — untested this
   session; worth swapping cable/port as a cheap isolation step.
3. A genuine kernel-side regression in `mtu3`/`g_ether` link-state signaling
   that predates #159 (i.e., was already broken when #159 was thought
   "known-good" via SSH, and something about the *test conditions* that day,
   not the kernel, made it work) — cannot be ruled out without a shell on
   the device via a path that doesn't depend on this USB link (e.g. serial
   getty login, if enabled on `ttyS0`).

**Next step:** try a different USB cable/port for the next attempt (rules
out #2 cheaply); if it still fails, get a shell over serial instead of USB
to inspect `dmesg`/`journalctl` for the gadget-side attach sequence directly,
rather than continuing to infer gadget health only from the Mac-side state.

**Update 2026-07-09 (continued) — exhaustive isolation across cable, Mac
state, and kernel age; USB link itself proven healthy; root cause still
unresolved.** A full round of isolation steps, each ruling out one
candidate:

- **Different USB cable** (user-tested): no change, same symptom. Rules out
  a worn/marginal cable.
- **Full Mac power-off + restart**, then removing and letting macOS
  recreate the "RNDIS/Ethernet Gadget" network service from scratch: no
  change. Rules out any stale `configd`/`IOUSBHostFamily`/cached-service
  state on the Mac as the cause.
- **Static IP re-verified intact** on the freshly recreated service
  (`10.15.19.1/24`, matches the device's `10.15.19.82` config) — not an IP/
  DHCP misconfiguration.
- **`ioreg` USB link diagnostics, captured live while build #159 was
  running:** `UsbLinkSpeed = 480000000` (full USB2 High-Speed — the
  electrically demanding chirp handshake succeeded), `bNumConfigurations = 2`
  (both descriptor configs advertised, as expected for `g_ether`'s
  RNDIS+ECM composite), `kUSBCurrentConfiguration = 1` (macOS selected and
  fully enumerated a configuration). This is strong proof the physical
  link, connector, and low-level enumeration are entirely healthy — the
  failure is narrowly scoped to *after* configuration selection, at the
  interface-level data alt-setting/carrier handshake (where Linux's
  `u_ether`/`usb_f_ecm` is supposed to call `netif_carrier_on()`).
- **Manually cycling the interface** (`ifconfig en12 down` / `up`) while the
  device stayed connected: no change — rules out the well-known "macOS ECM
  driver needs a nudge" community workaround.
- **Control test with build #71** (`logs/2026-07-06-71-usb-gadget-plus-uart-
  clk-fix/new_kali_boot.img`, banner `#5`, Mon Jul 6 06:22:43 UTC 2026) — the
  very first build CLAUDE.md documents as fully validated end-to-end over
  SSH-over-USB, predating every later display/DSI/SMI/IRQ change. Reflashed
  fresh to `boot2`; boots clean to the same `mtu3` cutoff point
  (`logs/2026-07-09-184-build71-earliest-good-recheck.log`); **identical
  failure** — `en12` exists, `UsbLinkSpeed`/config selection identical to
  #159, `status: inactive`, no ping/SSH.

**This is the most significant result of the session: the literal kernel
bytes that gave working SSH on 2026-07-06 now fail identically, on a
Mac that has been fully power-cycled, with a swapped cable, and a freshly
recreated network service.** This conclusively rules out every software
delta accumulated across builds #71→#178 (DSI-IRQ debug patches, fixed-MAC
cmdline, pstore config, SMI-larb work) as the cause — the kernel image
itself is not the variable. It also weakens the pure-Mac-state theory,
since the Mac is now about as clean as it can be without an OS reinstall.

**What's left, in order of likelihood given the evidence above:**
1. **Something changed on the Gemini's own analog/hardware side that
   persists across kernel reflashes but isn't kernel-controlled** — most
   plausibly PMIC/charging-IC state or NVRAM-backed calibration data reset
   by the full SP Flash Tool scatter-file restore (which, unlike a
   `boot2`-only reflash, rewrites `nvram`/`nvcfg`/`proinfo`). A full HS link
   negotiation succeeding doesn't rule out a marginal analog condition that
   only manifests at the specific point Linux's gadget stack tries to
   signal carrier.
2. **Battery/charging state** — still not conclusively excluded; a
   controlled bench power supply (bypassing the battery/PMIC entirely)
   would be the definitive test, not yet performed.
3. A genuine bug in Linux's `mtu3`/`u_ether`/`usb_f_ecm` interaction that
   was *never* actually reliable on this hardware, and appeared to work in
   earlier sessions only due to a — currently unidentified — favorable
   condition that no longer holds. Cannot be fully ruled out without a
   kernel-side shell (blocked by the UART/USB mux sharing the same port,
   see B-15) or persistent logging (blocked by `journald`'s default
   volatile storage on this rootfs, see the mkrootfs.sh discussion this
   session).

**Not yet tried:** connecting the Gemini to a genuinely different host
machine (e.g. the Linux workstation, which already saw RNDIS work
successfully once this session on the stock Android image) to determine
whether the failure is Mac-specific or universal — this is the next
highest-value isolation step, since it's the one major variable (the host)
not yet swapped.

### PENDING TEST (as of 2026-07-09) — cross-host isolation, run this next

**Read this whole block before doing anything — it's written so a fresh
Claude Code session with no memory of prior conversation can pick this up
cold on the Linux workstation.**

**Background:** `g_ether`'s USB gadget networking (the fast-track SSH-over-
USB path from Phase 8) has stopped working partway through this session,
identically across three kernel builds spanning the whole project history
(#71 — the very first ever validated build, #159, #178) and after
exhaustive Mac-side isolation (different cable, full Mac power-cycle, fresh
network service, static IP re-verified, `ioreg` confirms a fully healthy
480 Mbps USB link with configuration selection succeeding). See the "Update
2026-07-09" entries above this block for the full trail. The remaining
open question: **is this failure specific to the Mac, or does it reproduce
on any host** (pointing instead at the Gemini's own hardware/firmware
state)?

**What to actually do:**

1. This machine (Linux workstation) has **no build VM, no FTDI rig, no
   mtkclient, and no direct hardware access** — see the Machine Profiles
   section in `claude.md`. The Gemini itself, already flashed with a known
   kernel build on `boot2`, needs to be physically brought to this machine
   and plugged in via USB-C by the user — you cannot flash or drive the
   device yourself from here.
2. Once the user has the Gemini connected via USB-C to this Linux machine
   (booted into whichever kernel is currently on `boot2` — ask the user
   which build, or check the last blockers.md/boot.md entries for the most
   recently flashed one), check for the gadget interface the same way the
   Mac side was checked, translated to Linux equivalents:
   - `ip link show` / `ip addr show` — look for a `usb0` or similar
     interface (Linux typically auto-names CDC-ECM/RNDIS gadgets `usb0`,
     `enxAAAAAA...`, or similar, unlike macOS's `enNN`).
   - `dmesg | grep -i "cdc_ether\|rndis\|usb0"` — Linux hosts have a
     built-in `cdc_ether`/`cdc_ncm` driver; check whether it binds and
     reports a link-up/link-down (carrier) message, which is the direct
     equivalent of macOS's `ifconfig ... status: inactive`.
   - `ethtool usb0` (or whatever the interface is named) — reports `Link
     detected: yes/no`, the Linux equivalent of the carrier check.
3. If a static IP is needed on the Linux side to talk to the Gemini's
   `10.15.19.82` (see `configs/gemini-cmdline.config`'s `usb0.network`
   config, which sets that address on the device side), configure e.g.
   `sudo ip addr add 10.15.19.1/24 dev usb0` (adjust interface name) and
   then `ping 10.15.19.82` / `ssh root@10.15.19.82`.
4. **Interpreting the result:**
   - If the Linux workstation *also* sees no carrier / no link, that's
     strong evidence the problem is on the Gemini's side (hardware,
     firmware, or NVRAM state from the SP Flash Tool restore), not
     something Mac-specific — refocus investigation there (see the
     numbered candidate list above this block).
   - If the Linux workstation *does* get a working link/SSH, that's
     surprising given the Mac-side isolation done so far, and would point
     back at something specific to the Mac (perhaps a lower-level
     Thunderbolt/USB-C controller or driver state that a full OS restart
     didn't clear) — in that case, re-open the Mac-side investigation with
     that new fact in hand, and note it doesn't fully square with the
     `ioreg` evidence already gathered (healthy 480 Mbps link, successful
     config selection) which argued against a Mac hardware/driver problem.
5. **Document the result** in this same B-17 section of `blockers.md`
   (append, don't overwrite) and in `boot.md`, then commit and push so the
   Mac-side session (or the next session on either machine) has it. Follow
   the existing per-attempt provenance convention (see CLAUDE.md's Logging
   Requirements) even though no build/flash happened on this machine —
   note which build was on `boot2` at the time, and the exact Linux-side
   commands/output.

**Update 2026-07-08 — cross-host isolation complete; failure reproduces on Linux workstation; Mac-specific cause ruled out.**

Run on the Linux workstation (machine with no build VM/FTDI, per CLAUDE.md Machine Profiles). Gemini plugged in via USB-C while already running whatever build was on `boot2` at the time.

Build identity from this machine: the host-side MAC presented was `3a:d7:49:25:ce:01` (a random locally-administered MAC), which does **not** match build #178/#179's configured fixed host MAC (`42:00:15:19:82:00`). This indicates the build on `boot2` was older than #178 — most likely build #159 (banner #48), based on the last confirmed reflash in the prior session's "Update 2026-07-09" entries above. (User should confirm if unsure.)

Commands and output:

```
$ lsusb | grep -i "rndis\|ethernet gadget\|gadget"
Bus 001 Device 072: ID 0525:a4a2 Netchip Technology, Inc. Linux-USB Ethernet/RNDIS Gadget

$ ip link show enx3ad74925ce01
61: enx3ad74925ce01: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc fq_codel state DOWN ...
    link/ether 3a:d7:49:25:ce:01 brd ff:ff:ff:ff:ff:ff

$ ethtool enx3ad74925ce01
...Speed: 425Mb/s...Auto-negotiation: off...Link detected: no

$ sudo ip addr add 10.15.19.1/24 dev enx3ad74925ce01 && sudo ip link set enx3ad74925ce01 up
$ ip link show enx3ad74925ce01
61: enx3ad74925ce01: <NO-CARRIER,BROADCAST,MULTICAST,UP> ...

$ ping -c 3 10.15.19.82
PING 10.15.19.82 ... Destination Host Unreachable (3 packets, 0 received, 100% loss)
```

`cdc_ether` bound correctly (USB enumeration and descriptor exchange fully succeeded; `DRIVER=cdc_ether`, `PRODUCT=525/a4a2/606` confirmed via sysfs). The failure is the same as on the Mac: carrier never asserts from the Gemini side after the host driver binds — `NO-CARRIER`/`Link detected: no` throughout, identical to macOS's `status: inactive`.

**Interpretation (per the guidance block above):** the failure reproducing on a fully independent host, after a complete Mac power-cycle and scatter-file restore, **conclusively rules out Mac-specific hardware/software state as the cause.** The problem is on the Gemini's own side.

**Root cause identified 2026-07-08:** all of the "identical failure across builds #71/#159/#178" and both Mac + Linux host failures trace to a single cause: **the SP Flash Tool scatter-file restore wiped p29 (`linux` partition) and replaced the Debian 13 rootfs with the factory Kali image.** Every working SSH session in this project ran against the Debian 13 rootfs built by `scripts/mkrootfs.sh`, which installs `usb0.network` (static `10.15.19.82/24`) and enables `systemd-networkd`. The Kali image has none of that — so `usb0` on the device side is never configured, `10.15.19.82` is never assigned, and SSH is impossible regardless of kernel build or host machine. The USB enumeration and gadget bring-up themselves are fine (built-in `CONFIG_USB_ETH=y`, no userspace involvement needed for those). The kernel was never the problem. Every diagnostic trail from this blocker that blamed the kernel, NVRAM, battery, or PMIC can now be set aside pending a rootfs reflash.

**Fix — reflash Debian 13 rootfs (run on Mac, build VM must be running):**

```bash
# 1. SSH into build VM (adjust IP/port as needed, see claude.md Machine Profiles)
ssh -p 10022 root@localhost

# 2. In the VM: rebuild the rootfs (takes ~5 min)
cd ~/linux-6.6          # or wherever the repo is cloned in the VM
bash scripts/mkrootfs.sh
# Output: /mnt/host/OUTPUT/debian13-rootfs.img

# 3. Exit VM; on Mac: put Gemini in preloader mode and flash linux partition
# (hold Vol-Up while powering on with USB-C connected, or use mtkclient's
# auto-detect — NEVER use `mtk wl`, only `mtk w linux ...`)
/tmp/mtk-venv/bin/python3 ~/mtkclient/mtk.py w linux ~/gemini-build/OUTPUT/debian13-rootfs.img

# 4. Power-cycle the Gemini (boot2 should still have the last-flashed Linux kernel)
# 5. Confirm SSH:  ping 10.15.19.82  →  ssh root@10.15.19.82  (password: toor)
# 6. On device after first boot, grow the partition to fill p29's full 25.8 GiB:
#    resize2fs /dev/mmcblk0p29
```

After SSH is restored, resume B-17's original display investigation (the `flip_done` timeout / vblank loop) from the "Not yet investigated" candidates at the top of this section.

**Update 2026-07-08 — fix verified end-to-end; B-17's gadget/SSH sub-issue CLOSED.**

Ran the reflash procedure above (build VM on the Mac, `scripts/mkrootfs.sh` rebuilt a fresh `debian13-rootfs.img`, sha256
`a87d4780e7ccbbdba0a281b7e174c60f0eff181c1e470c5bdc8c5b3e8cd8c79e`, flashed to `linux` (p29) with
`mtk w linux ~/gemini-build/OUTPUT/debian13-rootfs.img`, boot2 left untouched at build #71). Serial capture
(`logs/2026-07-09-185-freshrootfs-boot-check.log`) confirms a clean boot through `mtu3 11271000.usb` init (the
expected UART/USB mux handoff point per B-15) with no new kernel-side errors. Post-boot, macOS's `en12`
(RNDIS/Ethernet Gadget) came up `status: active` at 100baseTX — the carrier/link problem is gone, confirming the
diagnosis. Mac side needed a static IP added manually (`sudo ifconfig en12 alias 10.15.19.1 netmask
255.255.255.0`) since the interface only self-assigned an APIPA address; once set, `ping 10.15.19.82` and
`ssh root@10.15.19.82` (password `toor`, fresh host key — expect and clear the one-time `ssh-keygen -R
10.15.19.82` host-key-changed warning) both succeeded:

```
$ ssh root@10.15.19.82 uname -a
Linux gemini 6.6.0-dirty #5 SMP PREEMPT Mon Jul  6 06:22:43 UTC 2026 aarch64 GNU/Linux
Debian GNU/Linux 13 (trixie)
```

This closes the gadget-networking sub-thread of B-17 (root cause: SP Flash Tool scatter restore had wiped the
rootfs, not a kernel/driver defect — no code change was needed, only a rootfs reflash). The **display** sub-issue
(DRM atomic commit / `flip_done` timeout, panel dark) that gives this section its title remains open — see the
"Not yet investigated" candidates above for where to resume that separately.

| Date | Was | Resolution |
|------|-----|-----------|
| 2026-06-10 | Console identity contradiction (ttyMT0 vs ttyMT3 vs ttyS0) — risk of silent dead boot | **ttyMT0 = UART0 @ 0x11002000 @ 921600**, triple-sourced (vendor DTB bootargs + spec Table 2-7 pinmux + mainline dtsi). ttyMT3 was a never-used `CONFIG_CMDLINE` fallback. See kernel.md. |
| 2026-06-10 | Reserved-memory carve-outs unknown — risk of stomping ATF/TEE | Full map recovered from vendor DTB; carve-outs + ramoops added to `dts/0001`. See kernel.md / boot.md. |
| 2026-06-10 | Vendor decompiled DTS lived in volatile `/tmp` | Re-extracted and committed: `docs/vendor-dtb/` (DTB + DTS + known-good kernel config). |
| 2026-06-08 | WiFi/BT port feasibility unknown | Researched: ~75–103 KLOC vendor stack, broken upstream since 5.7/6.0. Deferred to Phase 9; USB-Ethernet is the Phase 8 plan. See research.md. |
| 2026-06-07 | GCC ≤4.9 believed required | Empirically debunked; GCC 15.2.0 works for both 3.18 and 6.6. See CLAUDE.md. |
| 2026-06-07 | `mtk wl` GPT corruption | Banned; targeted `mtk w` writes only. See CLAUDE.md Flashing. |

---

## 📌 Baseline snapshot — 2026-07-08 (known-good, post B-17 rootfs fix)

Recorded for future reference after B-17's gadget/SSH sub-issue was closed (root
cause: SP Flash Tool scatter restore had wiped the rootfs, not a kernel bug —
see B-17 above). This is the full state of the device at the point SSH-over-USB
was reconfirmed working end-to-end.

**Flashed images and hashes:**

| Partition | Image | sha256 |
|-----------|-------|--------|
| `boot2` | `logs/2026-07-06-71-usb-gadget-plus-uart-clk-fix/new_kali_boot.img` (build #71, banner #5) | `c38e176bf18870a17636d66d22081c2e463384f9587c322bd4de2d8fe484d98e` |
| `linux` (p29) | `debian13-rootfs.img` (fresh, via `scripts/mkrootfs.sh`, 2026-07-08) | `a87d4780e7ccbbdba0a281b7e174c60f0eff181c1e470c5bdc8c5b3e8cd8c79e` |

**GPT partition table** (read via `mtk.py printgpt`, read-only — matches the
documented layout exactly, no corruption from any prior `mtk wl` incident):

```
recovery:    Offset 0x0000000000008000, Length 0x0000000001000000
para:        Offset 0x0000000001008000, Length 0x0000000000080000
expdb:       Offset 0x0000000001088000, Length 0x0000000000a00000
frp:         Offset 0x0000000001a88000, Length 0x0000000000100000
nvcfg:       Offset 0x0000000001b88000, Length 0x0000000000800000
nvdata:      Offset 0x0000000002388000, Length 0x0000000002000000
metadata:    Offset 0x0000000004388000, Length 0x0000000002000000
protect1:    Offset 0x0000000006388000, Length 0x0000000000800000
protect2:    Offset 0x0000000006b88000, Length 0x0000000000c78000
seccfg:      Offset 0x0000000007800000, Length 0x0000000000800000
oemkeystore: Offset 0x0000000008000000, Length 0x0000000000200000
proinfo:     Offset 0x0000000008200000, Length 0x0000000000300000
md1img:      Offset 0x0000000008500000, Length 0x0000000001800000
md1dsp:      Offset 0x0000000009d00000, Length 0x0000000000400000
md1arm7:     Offset 0x000000000a100000, Length 0x0000000000300000
md3img:      Offset 0x000000000a400000, Length 0x0000000000500000
scp1:        Offset 0x000000000a900000, Length 0x0000000000100000
scp2:        Offset 0x000000000aa00000, Length 0x0000000000100000
nvram:       Offset 0x000000000ab00000, Length 0x0000000000500000
lk:          Offset 0x000000000b000000, Length 0x0000000000080000
lk2:         Offset 0x000000000b080000, Length 0x0000000000080000
boot:        Offset 0x000000000b100000, Length 0x0000000001000000
logo:        Offset 0x000000000c100000, Length 0x0000000000800000
tee1:        Offset 0x000000000c900000, Length 0x0000000000500000
tee2:        Offset 0x000000000ce00000, Length 0x0000000000500000
keystore:    Offset 0x000000000d300000, Length 0x0000000000d00000
system:      Offset 0x000000000e000000, Length 0x00000000a0000000
cache:       Offset 0x00000000ae000000, Length 0x000000001b000000
linux:       Offset 0x00000000c9000000, Length 0x0000000671700000
boot2:       Offset 0x000000073a700000, Length 0x0000000001000000
boot3:       Offset 0x000000073b700000, Length 0x0000000001000000
userdata:    Offset 0x000000073c700000, Length 0x00000007520fbe00
flashinfo:   Offset 0x0000000e8e7fbe00, Length 0x0000000001000000

Total disk size: 0x0000000e8f800000, sectors: 0x000000000747c000
```

**Verified working at this snapshot:** `ssh root@10.15.19.82` (password
`toor`) over the `g_ether` USB gadget; kernel banner
`Linux gemini 6.6.0-dirty #5 SMP PREEMPT Mon Jul  6 06:22:43 UTC 2026 aarch64`;
`Debian GNU/Linux 13 (trixie)` userspace.

**To restore this exact baseline later:** flash `boot2` and `linux` with the
two images above (`mtk w boot2 ...` / `mtk w linux ...`), leave all other
partitions untouched.

## Update 2026-07-09 — B-17 DSI IRQ bounded-timeout fix attempted, regresses intermittently, still open

Attempted a fix for the recurring cpu0 hard-lock (the same class of failure
B-13 already root-caused): `patches/v6.6/drm/0012-drm-mediatek-dsi-bound-irq-busy-wait-timeout.patch`
bounds the unbounded `while (tmp & DSI_BUSY)` spin in `mtk_dsi_irq()` with
`readl_poll_timeout_atomic()` (1us poll / 20ms timeout).

**First version regressed hard**: builds #195/#197 (boot.md) both hit a
full watchdog reset (`wdt_by_pass_pwk`) — root cause was the timeout branch
returning `IRQ_HANDLED` without clearing `DSI_INTSTA` or waking
`irq_wait_queue`, turning a level-triggered IRQ's bounded poll into an
unbounded hardirq-storm with the status bit never cleared. Fixed by always
clearing/waking on both paths.

**Corrected version (build #200) is still not reliable.** Same flashed
image, three power-on attempts, three different outcomes: a full ATF
`aee_wdt_dump` hang (cpu0 stuck, no console output at all), then two
clean-looking serial boots that never brought up USB gadget networking
(`en12` stayed `inactive`, no device visible to `system_profiler` at all).
See boot.md "BUILD #200" for full detail. `/sys/fs/pstore/` was checked
after each recovery and found empty — no crash record survives, consistent
with the failure being ATF's own pre-Linux hang detector (which never
reaches Linux's panic/oops path) combined with the physical power-cycles
likely dropping DRAM self-refresh.

**Working hypothesis:** this is a timing-dependent race in how/when LK's
leftover DSI engine state (from framebuffer/logo display during boot) gets
touched by Linux's `mtk_dsi` driver — not a deterministic bug reachable by
re-reading patch 0012's C code, since the same image produces different
outcomes run to run. Patch 0012 is held out of the default patch stack
until this is understood; `boot2` is back on the known-good build #71
baseline.

**Update 2026-07-09 — stress test result: 0008-alone (no 0012) also hangs, same signature. Race is upstream of both DSI patches.**

Built #203 (`logs/2026-07-09-203-b17-0008-only-plus-pstore-trace`, banner #73,
sha256 `3eda93ee165eb4cb6a37fa2d6eab5647483df618d61e655af7ba5d46f0f87344`):
patch 0012 held out entirely (only 0008 in the drm stack), plus a new debug
patch (`patches/v6.6/zz-debug/0002-GEMINI-DEBUG-dsi-irq-poweron-poweroff-trace.patch`)
adding unconditional `pr_info` trace points around `mtk_dsi_irq()` entry/exit
and `mtk_dsi_poweron`/`poweroff` entry/exit, relying on
`CONFIG_PSTORE_CONSOLE=y` to mirror them into `/sys/fs/pstore/console-ramoops-0`
even across a warm (watchdog) reset.

Capture `logs/2026-07-09-204-b17-0008-only-plus-pstore-trace-boot.log`
spans two power-on sessions:

- **Session 1** (first ~1880 lines): booted clean on serial, reached the
  normal `mtu3` mux-switch cutoff, `RGU STA: 0` / "WDT does not trigger
  reboot" confirms this was a genuine cold start, not a post-hang reset. But
  `en12` never enumerated (`status: inactive`, no USB device visible to
  `system_profiler` at all) even after ~45s of polling — same silent
  gadget-networking failure seen twice on build #200.
- **Session 2** (device power-cycled again): the *new* capture opens with
  `RGU STA: A0000000` / `"SW reset with bypass power key flag"` /
  `"[PLFM] WDT reboot bypass power key!"` — meaning **session 1's kernel
  silently hung and self-reset via hardware watchdog sometime after we
  stopped polling it**, even though its serial log looked clean up to the
  `mtu3` cutoff. Session 2 itself then hangs identically: `el3_exit` at
  4.324s, **no kernel console output at all** (not even the `Linux version`
  banner), then `aee_wdt_dump: on cpu0` at 14.327s with
  `pc == lr == 0xffffffc000087fa8` — byte-for-byte the same hang address
  seen on build #200's first attempt. No `GEMINI-DEBUG` trace lines appear
  anywhere in either session, meaning the kernel never got near
  `mtk_dsi_irq()`/`mtk_dsi_poweron()` before hanging.

**Conclusion: this is not a patch 0012 regression.** Patch 0008 alone,
predating 0012 entirely, reproduces the identical early cpu0 hard-lock
(same hang PC, same `aee_wdt_dump` signature) and the identical silent
USB-gadget failure. The race is upstream of both DSI patches — most likely
in how early cpu0 boot collides with LK's leftover DSI/display engine
state, independent of what either patch does once Linux's own `mtk_dsi`
driver code starts running (trace evidence shows the hang precedes that
code executing at all in the fatal case). This reframes the investigation:
re-reading/adjusting `mtk_dsi.c` further is unlikely to fix it, since the
hang is already over by the time that code would run.

**Next steps (agreed 2026-07-09, not yet executed):**
1. Stress-test patch 0008 *alone* (no 0012) across several consecutive
   power cycles — 0008 predates this regression and has been assumed
   stable, but was never specifically stress-tested back-to-back the way
   0012 just was. If 0008-alone is also flaky, the race is upstream of
   0012 entirely and this investigation has been chasing the wrong patch.
2. Add unconditional (non-ratelimited) debug `printk`/`pr_info` trace
   points around `mtk_dsi_irq()` entry, the RACK write, the poll result,
   and `mtk_dsi_poweron`/`poweroff` entry/exit — tagged so they're
   greppable, and using plain printk (not `dev_err_ratelimited`) so a
   storm isn't suppressed. Since `CONFIG_PSTORE_CONSOLE=y` is already
   enabled, these should land in `/sys/fs/pstore/console-ramoops-0` even
   across a *warm* reset (watchdog-triggered), letting us revert to the
   baseline image afterward and read the trace without needing to catch
   it live over UART. Caveat: this only works if DRAM self-refresh
   survives whatever reset path fires — a full physical power-cycle by the
   user appears to wipe it (observed empty pstore after build #200's
   attempts), so where possible prefer waiting for/triggering the
   automatic watchdog reset rather than manually power-cycling, to
   maximize the chance the trace survives to be read.
3. Once forward progress is possible, consider the GIC pending/active-IRQ
   dump technique from the parked bare-metal plan (`SPI 229`
   pending/active state at hang time) to identify definitively whether
   the same DSI IRQ is implicated across all three failure modes.

## Update 2026-07-09 (later) — hang re-attributed: the "early cpu0 hard-lock" was almost certainly the ANDROID kernel, not ours

Resolving the recorded hang address against build #203's `System.map`
(`logs/2026-07-09-203-b17-0008-only-plus-pstore-trace/System.map`) overturns
the conclusion above:

- Our Linux 6.6 kernel's text starts at `0xffff800080000000` (`_text`,
  confirmed from System.map; all 171k symbols live in `0xffff8000...`).
  The hang PC `0xffffffc000087fa8` is **not in our kernel's address space at
  all.**
- `0xffffffc000080000` is exactly the text base of the **pre-4.20 arm64 VA
  layout used by 3.18-era kernels** — i.e. the vendor Android kernel
  (offset `0x7fa8` from text start, inside early head.S-era setup code).
- The same hang session contained `[LK]jump to K64 0x40080000` — the
  **Android `boot` partition's kernel load address**, not boot2's
  `0x40200000`. Every clean session in these captures shows
  `jump to K64 0x40200000` followed by our correct banner.
- Android boots are consoleless by design (LK hardcodes
  `printk.disable_uart=1`), which fully explains "el3_exit then total
  silence then aee_wdt" — no need to hypothesize our kernel dying before
  console init.

**Revised hypothesis:** on the "hang" cycles, LK selected/fell back to the
Android `boot` partition (boot-partition selection on the Gemini is
power-on-button-combo dependent, and LK may also fall back after a WDT
flag), and the *Android 3.18 kernel* hung and watchdog-looped. Patch 0008
(and 0012) may never have hung at all — every capture where LK jumped to
`0x40200000` booted our kernel cleanly on serial. The "byte-identical hang
PC across builds #200 and #203" is explained trivially: both were the same
Android kernel image.

**What survives of B-17 regardless of the above:** the silent
USB-gadget-enumeration failure. Now observed on three genuinely-clean boots
(2x build #200, 1x build #203 session with `RGU STA: 0`, correct #73
banner, clean serial log to the `mtu3` cutoff): `en12` stays
`status: inactive`, `system_profiler SPUSBDataType` shows **zero** matching
USB devices (so the device never appears on the Mac's USB bus at all — not
an IP-config issue), SSH times out. This is independent of any hang and is
now the primary open B-17 question. Also unresolved: blockers.md's earlier
claim that build #203 session 1 "silently hung after polling stopped"
(post-hoc `RGU STA: A0000000`) — that WDT flag could equally have been set
by a subsequent Android-fallback cycle; treat as unconfirmed.

**Evidence-handling lesson:** the raw hang captures were lost —
`ftdi-monitor.py` was relaunched to the *same* log path each power cycle,
overwriting prior sessions (only the final clean session survives in
`logs/2026-07-09-204-...`). Per the existing logging rules, every capture
attempt must get a fresh `NN`-numbered filename.

**Revised next steps (2026-07-09):**
1. **Button-controlled power-on test** (zero-build; build #203 still on
   boot2): several consecutive power-ons deliberately selecting the Linux
   boot entry, fresh log file per attempt, checking the `[LK]jump to K64`
   address in each. If `0x40200000` boots are always clean and only
   `0x40080000` cycles hang, the hang half of B-17 closes as a
   boot-selection artifact.
2. **Read the AEE crash record from the `expdb` partition** via mtkclient
   (`mtk r expdb expdb.bin` — targeted read, safe): MTK's AEE writes
   watchdog dumps there, so the hang cycles' register/stack dumps are
   likely recoverable and symbolicatable against a vendor 3.18 System.map
   (buildable from `gemini-android-kernel-3.18` in the VM).
3. Investigate the USB-gadget enumeration failure as its own thread
   (likely `mtu3`/UART-USB mux timing) — it will not be fixed as a side
   effect of display work.

## Update 2026-07-10 — B-17 crash ROOT-CAUSED and FIXED (OVL leftover IRQ → NULL-deref panic); flip_done timeout is the remaining display blocker

Full narrative and evidence in boot.md ("B-17 ROOT-CAUSED AND FIXED",
2026-07-10). Summary:

- **#203 never reached userspace** (journal on shared rootfs: all 10 boots
  banner #5). Its crash hid in the 0.5–6s window behind the mtu3 console-mux
  cutoff. Disabling USB entirely (build #218, banner #76) kept serial alive
  and captured the death: **NULL deref in interrupt context** —
  `mtk_disp_ovl_irq_handler → mtk_crtc_ddp_irq → mtk_crtc_ddp_config`
  dereferencing `crtc->state` (NULL until the first atomic commit). LK
  leaves the OVL scanning out the splash with `OVL_INTEN` armed; probe
  requests the IRQ and the leftover interrupt fires mid-bind. Panic → WDT →
  Android fallback (this also finally explains the fallback boots).
- **Fixed by `patches/v6.6/drm/0012`** (quiesce OVL_INTEN/INTSTA at probe +
  NULL-state guard in the IRQ path). Build #221 (banner #77) validated:
  no oops, kernel alive 93+s, DRM bound, DSI IRQ clean.
- **pstore/ramoops is a dead end on this device**: the preloader
  re-initializes DRAM on every boot path (proven by pmsg-marker and
  sysrq-panic tests with readout build #212/banner #75, even at the
  vendor's own `mediatek,pstore` address 0x44410000). Crash capture
  strategy = serial visibility via no-USB debug builds, not RAM.
- **Remaining B-17/display blocker:** `flip_done timed out` / vblank wait
  timeouts — OVL frame-done never fires after enable; no frames flow, panel
  dark, fbcon commit-retry loop appears to stall boot before systemd.
  Lead: verify DSI video-vs-command mode, TE/trigger and mutex SOF against
  vendor 3.18 source (LK log says `vido_mode`).
- The B-17 *gadget* half (silent USB failure on clean boots) is unchanged;
  the FTDI-first-then-swap cable protocol remains the reliable workaround.

**Cleanup state:** boot = readout #212 (#75), boot2 = fix-validation #221
(#77, no USB). Before resuming normal work: rebuild with
`configs/gemini-usb.config` restored (currently parked as
`.disabled`; delete `configs/gemini-nousb-debug.config` and also remove it
from the VM — build-pack rsync doesn't `--delete`), and reflash baseline.

## Update 2026-07-10 (later) — flip_done: three stacked defects fixed, pipeline now error-free but frameless; register-dump diagnostic built

Working the remaining flip_done/vblank timeout, three real, cumulative
defects were found and fixed (full evidence in boot.md builds #223–#229):

1. **Mutex EOF bits** — `mt6797_mutex_driver_data` borrowed
   `mt2712_mutex_sof`, which sets only the SOF field; vendor
   `ddp_get_mutex_src()` sets SOF *and* EOF to DSI0 for a video-mode path,
   and without EOF the OVL never receives frame-done. Fixed in
   `patches/v6.6/soc/0001` (new `mt6797_mutex_sof[]`, `SOF | SOF<<6`,
   mirroring mainline mt8183). Build #223 — necessary but not sufficient.
2. **LK leftover DSI video mode** — `DSI_MODE_CTRL` left in video mode by
   the splash survives `mtk_dsi_reset_engine()`, making every panel init
   command time out (-62) in `mtk_dsi_host_transfer()`. Fixed in
   `patches/v6.6/drm/0013` (force cmd mode in `mtk_dsi_poweron`). Build
   #225 — **validated**: init sequence now completes (187 CMD_DONE IRQs).
3. **MIPI-TX PLL sleeping in atomic context** — our mt6797 mipitx PHY had
   `usleep_range()` in clk `.enable` (runs under the CCF enable spinlock);
   `BUG: scheduling while atomic` in every display boot. Fixed in
   `patches/v6.6/phy/0004` (ops moved to `.prepare/.unprepare`, as mt8173
   mipi_tx). Build #227 — **validated**: BUG gone (capture 228).

Despite all three, flip_done ×9 / vblank ×4 persist: the pipeline
configures with zero software errors but no frame-done interrupt ever
arrives. Next step is visibility, not another guess:
`patches/v6.6/zz-debug/0003-GEMINI-DEBUG-ddp-register-dump.patch` (build
#229, banner #81) dumps raw mmsys/mutex/OVL0/RDMA0/DSI0 registers at t≈8s
and t≈8.5s while the stuck commit holds the pipeline powered — the
interpretation matrix is in boot.md's BUILD #229 entry. Awaiting flash and
capture 230.

## Update 2026-07-10 (evening) — flip_done/vblank timeout ROOT-CAUSED: OD0 misconfiguration (mainline mtk_od_config clobbered by mtk_dither_set)

The register-dump campaign (builds #229–#241, boot.md captures 230→242)
walked the failure to a single engine:

1. Eliminated in hardware, in order: mmsys routing table (soc/0002,
   verified mux-by-mux), OVL cascade wiring, layerless-frame limitation
   (layer poke, capture 234), MM CG clock gating, engine clock rate
   (mm_sel = 325 MHz from imgpll, capture 236), wedged-OVL0-FSM from LK
   handoff (OVL_RST poke, capture 238).
2. Capture 238's OVL FLOW_CTRL_DBG decode (vendor ovl_printf_status):
   both OVLs stuck in eng_act with out_valid=1/out_ready=0 → downstream
   backpressure, not head-engine failure.
3. Capture 240's mid-chain pixel counters: OD0 IN_CNT frozen while its
   OUT_CNT free-runs — OD0 blocks its input, self-generates output
   (which is why DSI streamed and RDMA0 underflowed).
4. **Root cause:** OD_CFG[1:0] is the mode field (vendor
   common/od10/ddp_od.c: 0x1 relay/bypass, 0x2 core-en; vendor default
   0x1). Mainline `mtk_od_config()` writes OD_RELAYMODE, then
   `mtk_dither_set()` overwrites OD_CFG with DISP_DITHERING only →
   hardware ends at 0x4 = dither on, no mode. MT8173 tolerates this;
   MT6797's OD (needs table/DRAM init mainline never does) does not.
5. **Confirmed live (capture 242, build #241):** poking OD0_CFG=0x5
   (relay+dither) at 8.7 s instantly completed the stuck atomic commit —
   fbcon bound (`fb0: mediatekdrmfb`), panel registered, plane enabled
   (OVL0 SRC_CON=0x1), old FME_UND/ABNORMAL_SOF signature gone.

**Fix to write:** `patches/v6.6/drm/0014` — preserve the relay bit in
`mtk_od_config` (OD_CFG = OD_RELAYMODE | dithering). Upstream candidate.

**New follow-on blocker (next up):** ~0.4 s into first real scanout,
right after `clk: Disabling unused clocks`, the system bus-hung and
WDT-reset to the Android slot (capture 242). Suspects: (a) SMI larb0
IOMMU-bypass gap (the earlier B-13 vendor-source finding) biting on
first real layer DMA — new latched layer-0 FIFO-underflow bit fits;
(b) late clk cleanup gating a now-needed clock (imgpll refcount). Plan:
build with drm/0014 + `clk_ignore_unused` temporarily restored to
separate (a) from (b) in one flash.

**Update 2026-07-10 (night) — flip_done FIXED and validated (capture 244, build #243):**
`patches/v6.6/drm/0014` (re-assert OD_RELAYMODE after mtk_dither_set)
confirmed: fbcon binds at 1.0 s, zero flip_done/vblank timeouts, full
boot to graphical.target in 10 s with the display stack enabled. The
capture-242 scanout WDT-reset did not reproduce with `clk_ignore_unused`
(TEMPORARY, in configs/gemini-cmdline.config) → the crash suspect is
late clk cleanup, not the SMI larb0 gap. Remaining before this blocker
closes: (1) find which clock clk_disable_unused kills during scanout and
hold a proper reference (then remove the temporary flag); (2) confirm
pixels on the physical panel; (3) strip zz-debug/0003 and restore the
production USB config for a clean production build.

**Update 2026-07-10 (late night) — panel-dark follow-up:** on the
milestone build #243 boot, the physical panel shows **backlight lit,
image black** (PWM confirmed enabled at 200/255 via serial login;
systemd-backlight not the culprit). Pixels aren't reaching the glass
despite a fully clean pipeline → active suspect is DSI video
timing/format mismatch vs. the panel's requirements. LK's own DSI
register dump in every capture is the golden reference; /dev/mem is
blocked, so build #245 (banner #89) extends the zz-debug dump to the
full DSI block 0x000–0x1AC for a kernel-vs-LK register diff. See
boot.md "BUILD #245".

**Update 2026-07-10 — DSI diff complete (capture 246), fix candidate
built (build #247):** kernel-vs-LK register diff shows format/lanes/
resolution all match; mismatches are (1) TXRX_CTRL — kernel disables EOT
packets and runs continuous HS clock where LK enables EOT + non-continuous
clock (mtk_dsi's DIS_EOT logic is inverted vs the flag name), and (2)
vertical/horizontal porches (panel patch used vendor-3.18 LCM values;
LK programs VSA=3/VBP=15/VFP=10 and wider horizontal blanking). Build
#247 (banner #90) updates panel/0005 to match LK on both. PHY_TIMCON
diffs deliberately deferred. See boot.md "CAPTURE 246 result".

**Update 2026-07-10 — controller theory exhausted; panel side
implicated (capture 248):** build #247's registers landed LK-identical
(TXRX_CTRL bit-for-bit, LK porches), link streams frames error-free,
still black. User confirms **LK's Planet logo displays, then goes dark
at kernel takeover** — panel HW and LK init are good; our panel
driver's reset/regulator/init takeover is the killer, or the panel
rejects our config internally. Build #249 (banner #91, zz-debug/0004)
adds differential DCS read-back (0x0a–0x0e) before our reset pulse (LK
state) and after our init, to name the failing step. See boot.md
"CAPTURE 248 result".

**Update 2026-07-10 — panel-dark ROOT-CAUSED (capture 250): TPS65132
bias never programmed.** DCS read-back: panel initialized, display ON,
booster OFF (0x0a=0x1c) — no analog rails. AVDD/AVEE come from a
TPS65132 on I2C1 @0x3e whose volatile VPOS/VNEG registers LK reprograms
every boot; our DTS had GPIO-only fixed regulators, so after the panel
driver's power-cycle the chip runs unprogrammed. Fix in build #251
(banner #92): mainline `ti,tps65132` regulator node (outp/outn 5.4 V,
enable-gpios 60/251) + CONFIG_REGULATOR_TPS65132=y. See boot.md
"CAPTURE 250 result".

**Update 2026-07-10 — second-layer bug: I2C1 combined transfers broken
(captures 252/253).** tps65132 probe timed out; interactive i2cdetect
proved the bus and chip fine but write-then-read (WRRD) transfers dead:
mt6797.dtsi i2c nodes fall back to the mt6577 compat (no auto-restart,
no aux-len). Fix `i2c/0001` (build #254, banner #93): match
"mediatek,mt6797-i2c" to mt8173 driver data (same IP generation,
confirmed against vendor mt6797 mt_i2c). Upstream candidate. See
boot.md "CAPTURE 252/253 result".

**Update 2026-07-11 — thick horizontal-band artifact appears on BOTH the
vendor-live-TIMCON build AND the plain mainline-formula build; not caused
by the TIMCON patch, and NOT a confirmed regression (no prior baseline
was actually documented).** Harvested live, steady-state `PHY_TIMCON0-3`
register values off the stock vendor 3.18 kernel while it was actively
driving the panel correctly (see boot.md "Full scatter-file recovery
reflash..." entry) and hardcoded them in debug patch `zz-debug/0008` as a
controlled experiment (build #105, `logs/2026-07-11-279-...`). Result:
kernel boot fully clean (no flip_done/vblank timeouts, DSI bound, panel
registered, DCS reads all normal); physical panel showed thick,
regularly-spaced light-blue/black horizontal bands — real pixel content.
Photo: `logs/2026-07-11-279-dsi-timcon-vendor-live-values/panel-thick-bars-result.jpg`.

Initially treated as a regression and reverted (patch 0008 disabled,
rebuilt as `logs/2026-07-11-281-revert-timcon-back-to-baseline/`, banner
`#106`) — reflashed #106 (**pure mainline-formula TIMCON, confirmed by
reading the built tree directly, no override present**) and the user
confirmed on physical hardware: **"same horizontal lines as the previous
build."** D-PHY timing (`PHY_TIMCON0-3`) is therefore **ruled out** as the
cause — visually identical result with the vendor-harvested override and
without it. Further, boot.md was checked and contains **no prior entry
describing a "thin top-of-frame corruption" baseline** before this
session's own (now-corrected) write-up — the last actually-documented
visual state (#243/#245) was backlight-lit but fully **black**, not
corrupted. So there is no confirmed evidence this banding is a
regression at all; it may be the first real pixel content this panel has
shown under our own kernel.

Clock-domain cross-check remains valid context: `mm_dsi0_mm`/`mm_sel` =
325 MHz and PLL CON0 = `0xf0002001` are confirmed identical between our
build and the vendor's (build #235/#237) — consistent with the banding
being unrelated to clock/PLL/D-PHY-timing setup generally, not just the
TIMCON registers specifically.

**Next step:** redirect investigation away from D-PHY bit-timing,
toward: (1) OVL/DDP layer config — the coarse, regular band pattern is
consistent with a scanline-count/line-stride mismatch rather than a
signal-integrity issue; (2) panel init command sequence — check for a
missing/incorrect column/page-address-set or memory-write command
producing a short repeating pattern instead of a full frame; (3)
framebuffer/scanout stride — cross-check the documented 1088-px
GPU-aligned stride vs. the panel's native 1080px on this code path. A
deliberate reference photo of build #106 is still worth capturing, but
TIMCON tuning is no longer the active lead. See boot.md "BUILD #105 ...
vendor-live TIMCON experiment" and "BUILD #106 recheck" for the full
account and correction.

**Update 2026-07-11 (later) — lead #2 (DSI HSA/HBP/HFP word counts) also
closed off; DSI-level config now doubly confirmed correct, root cause is
upstream of DSI.** Same method as the TIMCON test: overrode
`DSI_HSA_WC`/`DSI_HBP_WC`/`DSI_HFP_WC` with LK's exact proven register
values (`0x1c`/`0x94`/`0x74`, capture 244) instead of mainline's
formula-plus-correction derivation, which the panel patch's own comment
admits only lands "within one byte" of LK's values (build #107,
`zz-debug/0009-...`, `logs/2026-07-11-283-.../`). Kernel-side register
readback confirmed the override applied exactly as intended, and also
confirmed `DSI_PSCTRL` word-count = 1080×3 (RGB888, native panel width, not
the 1088-aligned GPU stride) with `PACKED_PS_24BIT_RGB888` selected —
correct. Boot fully clean, no flip_done/vblank timeouts, no DSI/panel
errors. User confirmed on hardware: **"same orange white black horizontal
bars then fade to black"** — identical to builds #105/#106.

Two independent, hardware-verified-correct DSI-level fixes (D-PHY bit
timing, and now line word-counts) have produced **zero visible change**.
This rules out the DSI protocol/timing layer as the cause with fairly high
confidence — the DSI engine is provably transmitting a well-formed,
correctly-timed stream. **The problem is upstream: what the OVL/RDMA layer
is actually reading from memory and handing to DSI** (layer pitch/format/
address vs. what DRM/fbcon actually allocated, or CRTC blend config) is now
the primary suspect, since it has not yet been directly instrumented the
way the DSI registers have. Next action: extend the existing DDP debug
dump (`zz-debug/0003`/`0006`) to also capture the per-layer OVL registers
(`OVL_CON`, `OVL_ADDR`, `OVL_PITCH`/`HDR_PITCH`) so the live pitch/format/
address can be read back and cross-checked against the DRM/fbcon-side
allocation. See boot.md "BUILD #107" for full detail.

**Update 2026-07-12 — PANEL LIT: display path RESOLVED end-to-end (build
#132, banner #119, ⭐).** The banding/dark-panel saga is over; three
stacked defects, each individually necessary:

1. **Init-table packet type** (found 2026-07-11, `zz-debug/0020`): vendor
   `DSI_set_cmdq_V2` sends commands ≥0xB0 as GENERIC packets; we sent DCS.
   The whole manufacturer init table had been corrupt from the start —
   this was the actual cause of the banding artifact (not OVL, not DSI
   timing).
2. **D-PHY LP/turnaround timing** (found 2026-07-12, `zz-debug/0008`
   re-enabled): mainline's TIMCON formula yields LP windows ~40% shorter
   than LK's proven values; the panel answered with ACK+Error and LP reads
   failed. With LK's TIMCON0–3, DCS reads work for the first time.
3. **Link mode** (found 2026-07-12): the vendor *kernel* LCM driver runs
   this panel in SYNC_PULSE **video mode** (`LCM_DSI_CMD_MODE=0`); LK's
   command-mode splash misled the 07-11 command-mode pivot (which also
   reintroduced flip_done timeouts). Video mode restored.

Result on hardware: solid-white test fill visible on the glass, clean boot,
zero flip_done/vblank timeouts, graphical.target in 21 s. See boot.md
"BUILD #132". Remaining follow-ups: fbcon-on-glass check (build #134),
then productization — fold 0020 into `panel/0005`, derive/fold correct
TIMCON values properly (vendor formula, not hardcode), strip zz-debug
patches, re-enable USB gadget config, re-verify `clk_ignore_unused` removal.

**Update 2026-07-12 (evening) — PHASE 5 COMPLETE: readable text console on
the physical panel.** After first light (build #132), the residual banding
on structured content was root-caused with an RGB-thirds test pattern to a
video line-timing mismatch: the mode timings had been reverse-engineered
from LK's register dump, but LK drives the panel in command mode, so its
video porches are meaningless. Switching to the vendor kernel LCM driver's
video timings (HFP26/HSA4/HBP20, VFP76/VSA1/VBP43, 167333 kHz) produced a
perfect stable image (build #138) and then a readable landscape console
(rotate:3 + TER16x32, build #143). All fixes productized in build #145
(banner #126): folded into panel/0005 and drm/0015, zz-debug stripped, USB
restored, clk_ignore_unused dropped. See boot.md builds #136–#145.

---

## 🟢 B-18 — AW9523B keyboard enablement breaks USB gadget (SSH-over-USB) — RESOLVED 2026-07-13

**Symptom evolution (all 2026-07-12, Phase 6):** on every build with the
AW9523B GPIO expander enabled (`GPIO_AW9523B=y` + DTS node okay) AND
`USB_MTU3` enabled:
- #147/#157: with a USB host (Mac) attached at power-on → boot wedges
  before userspace (panel stuck at penguins, no gadget enumeration, no
  console visibility — serial dies at the B-15 mux switch t=0.45s).
- #159/#166: boot completes (login on panel, keyboard works on #166) but
  the gadget never enumerates on the Mac: no interface with the fixed
  host MAC 42:00:15:19:82:00, device unreachable at 10.15.19.82.
- Baseline #145 (no aw9523b) boots + SSH works with the same USB config,
  so the regression tracks the aw9523b bring-up, NOT key scanning (the
  keypad node was still status-disabled in #147–#157; the expander probe
  alone — soft-reset + register init + GPIO58/SHDN driven high — is the
  active ingredient).

**Suspects (untested):** GPIO58 (SHDN) high or the AW9523B INT line
(GPIO87/EINT10, now floating enabled) interacting with the left-port
USB-C mux / charger / CC logic when VBUS is present; check vendor 3.18
sources (aw9523_key.c power-up sequencing, USB-C mux GPIO usage) and the
vendor DTB for GPIO58/87 dual roles before the next hardware experiment.
Device-side dmesg of a failed-gadget boot (#166) was not captured — the
working keyboard cannot type `|`/`-`/`>` (no Fn layer yet) and serial is
dead on mtu3 builds; capture it once the Fn layer or a file-based
diagnostic exists.

**Decision (user, 2026-07-12):** disable USB entirely and operate over
the serial console + on-device keyboard: `configs/gemini-usb.config` →
`.disabled`, new `configs/gemini-serial-console.config` (USB_MTU3 off +
clk_ignore_unused + console=tty0 cmdline). With mtu3 off the B-15 mux
never switches, so ttyS0 (console + getty) works for the whole session —
USB-broken + mtu3-on would have left no remote access at all.
clk_ignore_unused is mandatory in this mode (build #153 wedged in the
unused-clock sweep without mtu3 holding SSUSB clocks).

**Root cause found and fixed 2026-07-13:** desk research (vendor
`aw9523_key.c` in gemini-android-kernel-3.18) showed the chip's INT pin
(GPIO87/EINT10) gets an explicit `bias-pull-up` pinctrl state selected at
probe (`aw9523_key_setup_eint()`). Our DTS already *defined* the matching
state, `aw9523b_pins` (`patches/v6.6/dts/0001-...patch`: SHDN/GPIO58
output-high + GPIO87/INT `bias-pull-up`/`input-enable`) — but it was never
referenced by any `pinctrl-0` property on the `aw9523b` i2c node, so it was
dead DTS: GPIO87/INT was left **floating**, right next to USB/mtu3 IRQ
activity, which is consistent with both failure modes (#147/#157 hard wedge
with a host attached at power-on; #159/#166 silent gadget non-enumeration).

**Fix:** add `pinctrl-names = "default"; pinctrl-0 = <&aw9523b_pins>;` to
the `aw9523b: gpio@5b` node. One-line functional change; regenerated the
three DTS patches touching `mt6797-gemini-pda.dts` (0001/0009/0011) via
apply-edit-rediff so their line-number context stays consistent
(`patches/v6.6/dts/0001-arm64-dts-mediatek-add-gemini-pda-board.patch`,
`.../0009-...ssusb-gadget.patch`, `.../0011-...smi-larb0-common.patch`).

**Verified on hardware, build #175 (banner #140,
`logs/2026-07-13-175-b18-aw9523b-pinctrl-fix/`):** clean boot to prompt,
keyboard works, USB gadget enumerates (`en12`, fixed MAC
`42:00:15:19:82:00`), ping + `ssh root@10.15.19.82` both succeed — all
three B-18 symptoms cleared in one fix, no diagnostic matrix needed.
`configs/gemini-usb.config` restored (from `.disabled`);
`configs/gemini-serial-console.config` retired to `.disabled` (its
USB-off/`clk_ignore_unused` fallback is no longer needed — mtu3 + keyboard
now coexist). **New baseline:** display + keyboard + USB gadget SSH, all
together, for the first time since Phase 6 began.

## 🟢 B-19 — WiFi Stage 1 Gate G1a: USB host mode — RESOLVED 2026-07-15 (build #248: RTL8156 ethernet adapter enumerates + SSH-over-LAN, no-hands cold boot verified)

**RESOLVED 2026-07-15.** Build #248's four baked-in #231 fixes all worked;
the final live root cause was **external charge power suppressing the
BQ2589x OTG boost** (chip enters charge mode, REG0B VBUS_STAT=001, OTG
bit dropped — no VBUS ever sourced, so every prior test with a charger
attached was doomed regardless of kernel state). With the charger
unplugged: RTL8156 USB-C ethernet adapter enumerates from a cold boot
with zero manual pokes, r8152 binds, DHCP, SSH from the Mac over the LAN
(192.168.100.144). Full timeline + rough edges (charger hot-plug kills
boost without self-resume — /root/h.sh recovers; one unexplained panic
on first reboot, pstore empty; rtl8156b-2.fw missing but works) in
boot.md "BUILD #248 flashed". Gate G1b's original purpose (SSH not via
the gadget) is satisfied by this ethernet path; WiFi-dongle work can
reuse it directly.

**History — resumed 2026-07-15 (user decision — CONSYS G2b hunt parked in turn):**
target is a USB ethernet adapter on the left port, giving SSH-over-LAN as
the debug channel for later WiFi work. Build #248 (sha256
`99bf2c1aa53a46348a55e0e43e1f898f594435dd99370dd7c4559450e2b76edb`) bakes
in all four #231 defects: (1) bq25890_vbus_enable re-asserts WD-off each
enable (power/0001); (2) autosuspend root-caused to Debian's
60-autosuspend.rules hwdb writing power/control=auto — countered by rootfs
udev rule 99-gemini-usb-host-pm.rules (both controllers + all USB devices
pinned "on"); (3+4) new DTS-gated `mediatek,force-usb-host` in phy/0001
(host IDDIG + SUSPENDM forced in u2 power_on — mtu3 never calls
phy_set_mode(), so mainline's host-role path is dead code here). dts/0012
re-enabled (dts/0013 EOF-context regenerated to apply after it);
gemini-usb.config back to the host build + usbnet adapter drivers
(CDCETHER/RTL8152/AX88179/AX8817X/RNDIS/SMSC95XX); rootfs also got DHCP
on any en*/eth* (not usb0) and re-staged /root/h.sh + /root/s.sh (s.sh now
reads the queued linestate monitor 0x11290870/74). New pre-build evidence:
**MT6351 VUSB33/VA10 rails proven ON live** via pwrap regmap on #247
(0x0A16=0xda62, 0x0A6E=0xda62, EN bits set) — the #231 "analog rails"
suspect is weakened. If #248 still shows Powered/Not-connected, the
linestate adapter-out-vs-in comparison at the panel console is the
deciding diagnostic. See boot.md "BUILD #248".

**History — parked 2026-07-14 → 2026-07-15:** build #231 exhausted the vendor-sourced GPIO/mux
candidates and four PHY/runtime-PM defects were root-caused without
producing a connect event. WiFi pivoted to the internal CONSYS path
(B-21) until G2b stalled (see B-21). Host-mode overlay was retired to
`patches/v6.6/dts/0012-...patch.disabled`; `configs/gemini-usb.config`
restored to the gadget build (build #233). Both reversals undone in #248.

**Symptom:** with `mtu3` in host/OTG mode (`patches/v6.6/dts/0009-...`),
`xhci-mtk` binds and the controller comes up without crashing, but a USB
stick plugged into the right-hand port never appears beyond the virtual
root hub in `lsusb`, and `/proc/interrupts` never shows a single fire on
the xhci IRQ (SPI 126) — consistent with no electrical connect event ever
being registered, across every build tried.

**Ruled out, in order (see boot.md builds #142–#148):**
- xhci sysfs device-name collision with the parent ssusb node (#142→#143
  fix: separate MAC-only register window for the xhci child).
- Pure `dr_mode="host"` never flipping the port0 U2/U3 mux, because that
  only happens via the OTG role-switch path (#143→#144 fix: `dr_mode="otg"`
  + `usb-role-switch` + `role-switch-default-mode="host"` — this also
  fixed a real "HC died" crash, but did not fix enumeration).
- Missing VBUS gating: GPIO94 (`usb1_drvvbus`) alone is not the real power
  switch — SW7226 (GPIO72) is a separate load-switch IC in series (#145
  fix, vendor-sourced from `usb_typec.c`'s `fusb300_eint_work()`).
- Missing FUSB301A-mux idle state: GPIO70/71 floating instead of the
  vendor's documented safe-idle values (#146 fix, same vendor source).
- FUSB340 USB3 redriver (GPIO251/252, a fourth, separate mux found in the
  vendor DTB's `usb_c_pinctrl@0` node) — **tried in #147, caused a real
  display regression** (panel went blank, no crash visible in the serial
  log up to the expected B-15 mux death) and was reverted in #148 (display
  confirmed restored on hardware). Either the vendor-DTB pin decode for
  GPIO251/252 is wrong, or those pins are genuinely shared with/gate the
  display power path — do not re-attempt without independent GPIO
  debugfs readback *and* a test that isolates display from USB, not both
  changed in the same build.

**Current state (build #148, vendor GPIO fixes 94/72/70/71 all present,
confirmed via `/sys/kernel/debug/gpio` readback on hardware):** every
GPIO-level gate documented in the vendor 3.18 source/DTB for this signal
path is now asserted correctly, and the stick still does not enumerate.
This is a materially different situation from B-18 (which was a genuine
one-line dead-pinctrl-reference bug) — the GPIO layer is very likely
exonerated at this point.

**Not yet investigated:** whether this is a physical issue (bad
cable/adapter/stick — should be tested with a second known-good stick and
cable before further kernel changes), or a deeper mtu3/xhci-mtk driver gap
specific to this SoC that isn't visible in the vendor 3.18 source (which
never ran xhci/host mode at all — Android only ever used gadget mode on
this port). Recommend a physical-layer sanity check (different stick,
different cable, multimeter/scope on VBUS at the connector if available)
before spending further flash cycles on driver-side theories.

**Blocks:** WiFi Stage 1 Gate G1a (plan.md Phase 8), and therefore Stage
1.2 (MT7921U dongle) and Gate G1b.

**Update 2026-07-13 (post build #148):** a second, different USB2.0 device
(SD card reader, VID:PID 349C:0418, confirmed via Mac-side `ioreg`) was
tested in the same port and also shows nothing beyond the root hub — rules
out "bad first stick" as an explanation. Next candidate, not yet tested:
cable/CC orientation. GPIO70/71 (`fusb301a_sw_sel`) hardcode the CC1
orientation default; if the physical connector is inserted CC2, that mux
may not be a simple polarity swap but could route D+/D- to nothing at all
in the "wrong" orientation. Zero-risk test recommended before any further
kernel changes: flip the cable/adapter 180° and recheck `lsusb`.

**Correction 2026-07-13 (confirmed with user): wrong physical port tested
throughout builds #142-148.** The Gemini PDA has two physical USB-C ports.
`mtu3`/xhci-mtk (all the GPIO/mux work in this blocker) is wired to the
**left** port — the same one used for UART/FTDI (B-15's `FORCE_UART_EN`
mux bit lives inside mainline `mtk-tphy`'s PHY init for this exact
connector) and for gadget SSH (build #175). The **right-hand** port —
where every test device in this blocker was plugged in — is driven by the
separate legacy `usb1@11200000` MUSB-style controller
(`mediatek,mt6797-usb11`), which has **no mainline driver** (hardware.md,
driver_ports.md). Nothing was ever going to enumerate there regardless of
GPIO state. `plan.md`'s Gate G1a instructions ("right-hand port") were
written before this was verified against physical hardware and are wrong.
**Next step: retest with the SD card reader in the left port** (single
cable-swap with the FTDI rig, same protocol as gadget-SSH verification).

**Update 2026-07-13 (build #150): likely root cause found -- CC-less
adapter cable.** Enabled the existing (previously unused) FUSB301A driver
(`patches/v6.6/usb/0001-...`) as an I2C-only diagnostic (not wired to
usb-role-switch). With the SD card reader plugged into the confirmed-correct
left port via a **USB-C-to-USB-A adapter**, the chip itself reports
`status=0x00 type=0x00 cc=CC1 role=0` -- i.e. the ATTACH bit has never been
set. A bare/passive C-to-A adapter typically carries no CC pins at all
(just VBUS/GND/D+/D- passthrough), so this is consistent with the cable
itself never presenting a valid Rp/Rd to the FUSB301A, independent of any
kernel/GPIO work. The vendor's own fusb300_eint_work() only asserts the
VBUS/mux switch GPIOs *after* confirming CC attach over I2C -- our static
"skip negotiation, assert post-attach state" approach may not be
sufficient if the physical switch ICs (sw7226/fusb301a-sw) have any
hardware interlock tied to genuine CC attach, separate from the GPIOs we
drive from Linux. **Next step (zero kernel changes): retest with a native
USB-C storage device, or a C-to-A adapter/dongle confirmed to implement
real Type-C CC signaling**, before any further driver/DTS work on this
gate.

**Stopping point 2026-07-13 (Gate G1a paused, not resolved).** Final test:
enabled the FUSB301A driver's DFP-mode write and re-probed with a
**native USB-C dongle** (MediaTek network dongle, proper Type-C plug, no
adapter) on the confirmed-correct left port. Result: identical
`status=0x00 type=0x00 cc=CC1 role=0` to the CC-less USB-A adapter test --
ATTACH never asserts regardless of device or cable. This rules out the
CC-less-adapter theory too.

**Summary of everything ruled out this investigation (builds #142-150):**
- xhci sysfs device-name collision (fixed, #143)
- dr_mode host-only never flipping the port mux (fixed, #144 -- also fixed
  a real "HC died" crash)
- Missing VBUS gating (GPIO94, sw7226/GPIO72) -- confirmed correctly
  asserted (#145)
- Missing FUSB301A-mux idle state (GPIO70/71) -- confirmed correctly
  asserted (#146)
- FUSB340 redriver (GPIO251/252) -- caused a real display regression,
  reverted (#147/#148); dead end, not a safe lead
- Wrong physical port (right-hand, driven by the driverless legacy
  `usb1@11200000` MUSB controller) -- corrected to the left port (mtu3),
  confirmed via B-15/gadget-SSH precedent
- Bad test device -- ruled out with two different devices (SD reader,
  network dongle)
- CC-less adapter cable -- ruled out with a native USB-C dongle

**Remaining unknown:** the FUSB301A's `MODE` register write
(`regMode = 0x04`, meant to force DFP/host mode) is explicitly flagged
`FIXME`/unverified in the driver source -- it was reverse-engineered from
the vendor 3.18 driver's usage, not from a real ON Semiconductor FUSB301
datasheet. If that encoding is wrong, the chip may never actually enable
CC toggling/attach detection, which would explain `ATTACH=0` regardless of
what's plugged in. **Do not attempt further register-level changes to
this driver without the real FUSB301A/FUSB301 datasheet** (or the vendor
Android BSP driver's register `#define`s, which were not consulted for
this field -- only the call-site logic was). Paused here rather than
continue guessing bit patterns blind.

**Reverted to known-good baseline:** flashed back to build #175
(banner #140, `logs/2026-07-13-175-b18-aw9523b-pinctrl-fix/`, sha256
`d34d58474bca24a851eda4c93ac660aada268c8cb3de1f231d44b00d7c7883c8`) --
keyboard + display + USB gadget SSH all working together. All of builds
#142-150's DTS/config changes (dr_mode=otg, xhci child node, VBUS/sw7226/
fusb301a-mux/fusb340 gpio-hogs, FUSB301A diagnostic) remain in
`patches/v6.6/` for whenever this gate is resumed, but are NOT in the
currently flashed image.

**Blocks:** WiFi Stage 1 Gate G1a (plan.md Phase 8), and therefore Stage
1.2 (MT7921U dongle) and Gate G1b. Phase 8 networking is otherwise fully
functional today via gadget SSH (build #175 baseline).

**Update 2026-07-14 — LIKELY EXPLANATION FOUND (vendor-source harvest +
live verification, research.md "USB Left-Port PHY & Type-C Harvest"):**
1. **Wrong chip all along.** The Gemini has TWO FUSB301 chips at 0x25:
   i2c0 (vendor node `fusb301a@25`) serves the RIGHT port and its
   OTG/HDMI muxes; **i2c1 (`fusb301@25`) is the LEFT port's CC
   controller** — proven live on #177 by plugging the Mac into the left
   port: i2c1 Status=0x2b (ATTACH/VBUSOK/CC2), i2c0 Status=0x00. Every
   Stage 1 experiment read/wrote the i2c0 chip, so "ATTACH never asserts"
   was the truthful state of the empty right port.
2. **Real register map recovered** (vendor `fusb301.h`): Mode is reg
   0x02 (SOURCE=0x01, SINK=0x04, DRP=0x10); the old guessed "0x04 MODE"
   write hit the Manual register. Both chips power up in Mode=0x04
   (SINK), so a downstream device presenting Rd is invisible — consistent
   with zero connect events at G1a.
3. **Vendor DID ship host mode on this port** (contrary to earlier
   note): known-good config has `CONFIG_USB_XHCI_MTK=y`, and the DTB's
   `usb3_xhci@11270000` has an `usb_iddig_bi_eint` (EINT 181) — vendor
   host/device switching keyed off IDDIG, not CC.
   **Next steps when resumed:** program i2c1 chip Mode=0x01 (SOURCE),
   retest left-port enumeration; trace how IDDIG is generated on a
   Type-C port before more role-switch DTS work.

**Update 2026-07-14 — Stage C Phase 1 (vendor IDDIG/VBUS harvest) complete
(research.md harvest §7).** Key facts:
- Vendor host-mode trigger = pure ID-pin OTG: EINT 181 level-low →
  debounced `mtk_xhci_mode_switch()` loads xhci and enables VBUS; no CC
  logic anywhere in the host path. Who drives IDDIG low on a Type-C
  connector is still unproven (i2c1 FUSB301's eint handler is a stub;
  FUSB301 has no legacy ID output pin) — to be resolved empirically in
  Phase 0 by watching EINT181 while attaching a sink with the chip in
  SOURCE mode.
- **Left-port host VBUS = RT9466 charger OTG boost** (`set_chr_enable_otg`
  → CHG_CTRL1 reg 0x01 bit0 OPA_MODE, chip at i2c0 0x53), NOT the MT6351
  PMIC (`CONFIG_MTK_OTG_PMIC_BOOST_5V` unset in the known-good config).
  Mainline `rt9467-charger.c` exposes exactly this boost as a
  `usb-otg-vbus-regulator` — clean Phase 2 shape is RT9466 node +
  regulator as `vbus-supply` of ssusb (caveat: driver hard-requires its
  IRQ, the B-11 EINT gap — patch it optional or fix B-11).
- ~~**Phase 0 zero-kernel live test (next, needs hardware):** on #225 over
  FTDI serial — i2c1 0x25 Mode(0x02)=0x01 SOURCE, RT9466 boost on via
  i2c0 0x53 reg 0x01 bit0, plug real-Type-C sink into left port, read
  Status(0x11)/Type(0x12) expecting ATTACH=1, and check EINT181 level.~~
  **DONE 2026-07-14 — see below.**

**Update 2026-07-14 — Stage C Phase 0 COMPLETE: full left-port CC+VBUS
chain proven live, zero kernel changes** (research.md harvest §8, logs
`2026-07-14-227..230-b19-phase0-*.log`). Run over gadget SSH with staged
scripts (serial console is unusable on #225 — see B-20 note below). The
working recipe, all three elements required:
1. **FUSB301 i2c1 0x25 Mode(0x02)=0x01 SOURCE** → ATTACH=1 + Type=SINK for
   real devices, both CC orientations verified.
2. **BQ25896 OTG bit (i2c0 0x6b REG03 bit5) with I2C watchdog disabled**
   (REG07[5:4]=00; the 40s WD silently resets REG03 otherwise).
3. **GPIO107 HIGH** (`GPIO_OTG_DRVVBUS_PIN`, aeon dws) — the BQ25896 boost
   is pin-AND-register gated and fails silently (no fault) when low; LK
   hands it over low. This was the final missing piece.
   Result: VBUS_STAT=111, VBUS ADC 5.0V, device LEDs lit.
- **Charger correction: the device has a TI BQ25896 at i2c0 0x6b
  (REG14=0x06), NOT an RT9466** — nothing at 0x53 on any bus. All RT9466
  references in hardware.md/Phase 7 corrected; mainline driver =
  `bq25890_charger.c` (`ti,bq25896`), which also exposes the boost as a
  `usb-otg-vbus` regulator.
- **Remaining for Stage C:** Phase 2 build (host-mode DTS + FUSB301A
  driver rewrite for i2c1/real regmap + bq25896 node + GPIO107 + gating
  the B-20 force-b-session-valid in host role), then Gate G1a enumeration
  test. IDDIG (EINT 181) still untraced — may be unnecessary with
  role-switch-default host.

**Side-finding 2026-07-14 (belongs to B-20/B-15 ledger):** on build #225
the serial console is dead on EVERY boot (FTDI protocol included) — the
forced session-valid bits hold the PHY pads in USB mode; #226's "FTDI
regression clean" capture actually ends at 0.447s (mtu3 probe). Worse, a
boot with the FTDI rig attached at power-on appeared to hang at
`clk: Disabling unused clocks` (panel confirmed stuck, not just serial
loss); boot with NO cable then hot-plug works. serial-login/serial capture
are unavailable on #225 until the force bits are gated by role or DTS knob.

**Update 2026-07-14 — Stage C Phase 2 patches drafted (not yet built):**
- `patches/v6.6/usb/0001` REWRITTEN for the real chip/regmap: binds the
  **i2c1** left-port FUSB301, Mode reg 0x02 = 0x01 SOURCE, Status
  0x11/Type 0x12 decode per the live Phase 0 verification. Polling (500ms,
  B-11 = no EINT), dev_info on CC change, SINK restored in
  shutdown/remove for vendor-chain handoff.
- NEW `patches/v6.6/power/0001-power-bq25890-allow-probe-without-irq.patch`:
  mainline `bq25890_charger.c` hard-fails probe without an IRQ; patched to
  warn-and-continue (B-11). Driver already disables the 40s watchdog in
  hw_init (F_WD=0) — matches the Phase 0 recipe.
- NEW `patches/v6.6/dts/0012-arm64-dts-mediatek-gemini-left-port-host-mode.patch`
  (applies after dts/0009, keeps 0009 gadget baseline intact for easy
  revert): (a) i2c0 charger node corrected to `ti,bq25896`@0x6b with the
  seven required ti,* props (defaults matching live-observed hardware
  values) and an `otg_vbus: usb-otg-vbus` regulator child; (b) i2c1
  `typec@25` FUSB301 node enabled; (c) GPIO107 gpio-hog output-high
  (`otg-drvvbus`); (d) ssusb → dr_mode="otg" + usb-role-switch +
  role-switch-default-mode="host" + xhci child @0x11270000 SPI 126 (the
  #142 sysfs-collision and #143 pure-host-mux lessons baked in),
  vbus-supply=<&otg_vbus>; (e) **B-20 `mediatek,force-b-session-valid`
  REMOVED from u2port0** in this build — it pins the PHY to device role
  (and killed serial); serial console should return to normal B-15
  behaviour. The old GPIO94/sw7226/fusb301a_sw hogs from #144-146 are NOT
  revived (right-port wiring); FUSB340 GPIO251/252 hogs stay excluded
  (display regression, #147).
- `configs/gemini-usb.config` updated: MTU3_DUAL_ROLE, XHCI_MTK,
  TYPEC_FUSB301A, CHARGER_BQ25890, plus usb-storage/usbnet class drivers
  so G1a devices bind.
- Validated: full patch stack applies clean on pristine v6.6; board DTS
  compiles with dtc. Next: /build-pack, regression-check keyboard+display
  (+serial return), then Gate G1a (SPI 126 count + lsusb beyond root hub).

**Update 2026-07-14 (late) — build #231 flashed and live-debugged: all
Phase 2 software works, Gate G1a still not passed.** Full session detail
in boot.md "BUILD #231 flashed". Regression gate passed (boot, display,
keyboard, FTDI-attached boot no longer hangs); FUSB301 driver, bq25890
regulator, dual-role mtu3 + xhci root hub all live. Device never
enumerates: portsc stuck "Powered Not-connected", SPI 126 never fires.
Four real defects found and worked around by hand (all must be fixed in
build #232):
1. bq25890 boost state lost post-boot (REG03/REG07 reset; harden
   `bq25890_vbus_enable` to rewrite WD-off + OTG each enable);
2. runtime PM autosuspend clears IPPC HOST_SEL and power-cycles the PHY
   — with no USB wakeup wired this permanently kills connect detection
   (disable autosuspend for ssusb/xhci in the build);
3. U2PHYDTM1 needs explicit host forcing (FORCE_IDDIG|RG_IDDIG=0 =
   0x200); LK leftovers differ by boot cable (0x43E2E FTDI / 0x0 clean);
4. U2PHYDTM0 SUSPENDM=0 on clean handover — PHY analog asleep; forced
   FORCE_SUSPENDM|RG_SUSPENDM.
Even with all four fixed live, no linestate: ruled out usb2uart mux,
usb2jtag mux, ACR4 GPIO mode, ACR6 config, GPIO70/71, orientation.
NEXT: PHY linestate monitor (0x11290870/74) adapter-out vs -in to split
MAC-side break vs analog-blind; prime remaining suspect = MT6351 PMIC
PHY rails (VUSB33/VA10, no mainline driver) per vendor
`usb_phy_recover()`, the canonical host U2-PHY bring-up sequence.
Debug tooling: `/root/h.sh` + `/root/s.sh` on the rootfs (survive kernel
reflashes; see boot.md). — USB gadget enumeration intermittently dead: root cause = U2PHYDTM1 session-valid FORCE bits (RESOLVED 2026-07-14, build #225)

**Opened 2026-07-13 (late).** The #175/#177 gadget baseline (verified
working twice on 2026-07-13: morning #175, and once mid-evening #177 with
UDC `configured` + SSH) intermittently boots with the mtu3 UDC stuck at
`not attached` and ZERO enumeration on the Mac — across kernels (#175
content), rootfs (pristine and rebuilt), Android bounces, cold boots and
hot replugs. Android itself always enumerates (`Gemini_4G`), so the
hardware path is intact.

**Ruled out (evidence in boot.md "BUILDS #176/#177 + B-20"):**
- Kernel content (byte-identical to verified-working #175)
- Rootfs (fails on pristine hash-verified image; failure is below the
  rootfs layer — no enumeration at all)
- FUSB301A state: register dump with the REAL vendor map shows a perfect
  attach (Status=0x2b: ATTACH=1 VBUSOK=1 ORIENT=CC2; Manual=0x00 — the
  Stage 1 "0x04 = MODE" write theory is dead, 0x04 is the Manual reg and
  it is clean)
- GPIO70/71 mux pins: vendor source proves they belong to the USB1
  (right-port) OTG/HDMI path; driving all 4 states changed nothing.

**Correlation:** every break followed an mtkclient preloader/DA session;
the one mid-evening recovery followed FTDI-serial boots + live cable
swap. Not yet causally explained.

**Prime suspect:** the B-15 left-port UART/USB console "mux" is the
MT6797 U2 PHY's usb2uart function (FORCE_UART_EN/RG_UART_EN in the PHY
DTM registers). LK leaves the PHY in UART mode for its console; if our
tphy init does not (always) clear it, D+/D- stay routed to UART while CC
attach looks perfect — exactly the observed signature.

**Next actions:** (1) genuine #177 FTDI boot capture — does serial die
at ~0.45s? (the earlier "#177 serial to prompt" report was a misread of
the #176 log); (2) devmem the U2 PHY DTM registers on a broken boot;
(3) if UART bits stuck, clear live to prove, then fix tphy init/probe
ordering permanently.

**Blocks:** SSH-over-USB reliability (Phase 8), and any workflow that
flashes then expects gadget access without a magic boot sequence.

**Update 2026-07-14 (early): WORKING AGAIN + pattern identified as the
documented cable protocol.** SSH restored end-to-end (#177, UDC
`configured`, keymap active, rootfs resized to 26G) after: boot with FTDI
attached (serial dies at 0.454s = PHY switch), then hot-swap the cable to
the Mac → RNDIS enumerates. This matches the 2026-07-10 session note
verbatim: "Cable protocol: FTDI in at boot, swap to USB after — booting
with USB in breaks gadget." So B-20's *operational* face is known,
reliable behavior, reproduced twice tonight; what remains open is the
root cause (what LK/U2-PHY/mtu3 do differently when VBUS+host are present
at power-on) and a software fix so boot-with-host-attached works.
Downgrading from 🔴 to 🟡. Workaround: never boot with the Mac cable in;
boot with FTDI (or nothing) in the left port, plug the Mac in after boot.

**Update 2026-07-14 (Stage A/B of USB plan): registers now source-backed,
good-boot baseline captured, broken-boot diagnostic staged.** Vendor
harvest (research.md "USB Left-Port PHY & Type-C Harvest") pinned the
usb2uart registers: U2PHYDTM0=0x11290868, U2PHYDTM1=0x1129086C, plus an
AP-side mux at 0x10005600 (0x80=UART, 0x00=USB) that mainline never
touches. Live dump on a WORKING #177 gadget boot: DTM0=0x52000008
(RG_UART_MODE[31:30]=01 — nominally "uart mode"!), DTM1=0x00043E2E,
MISC=0x80, UDC=configured — so RG_UART_MODE/MISC alone do NOT block
gadget; the good-vs-broken differential will isolate the bits that do.
Vendor gadget attach is PMIC BC1.2 + CHRDET (`mu3d/drv/mt_usb.c`), not
controller VBUS sensing — supports the mtu3 role/VBUS-sensing suspect.
A run-once diagnostic harness is now installed in the rootfs
(`run-once.service`, see boot.md 2026-07-14) and `/root/run-once.sh` is
staged with the full register/FUSB/dmesg dump.

**ROOT-CAUSED AND PROVEN LIVE 2026-07-14 (same session, boot.md "B-20
ROOT-CAUSED"):** the broken/good differential is NOT uart mode (broken
boots have the *cleaner* PHY state) — it is U2PHYDTM1's session-signal
FORCE bits [13:9]. Good boots inherit LK's software-forced
"device-role/session-valid" state (DTM1=0x43E2E); broken boots
(host attached at power-on → different LK path) get DTM1=0x26 with no
FORCE bits, and mtu3 waits forever on hardware VBUS sensing this
platform doesn't have (vendor mu3d forces these bits from PMIC BC1.2
detection — mt_usb.c). Causal proof on a broken boot via the run-once
harness: `devmem 0x1129086C 32 0x3E2E` flipped UDC `not attached` →
`configured` in <5s, RNDIS enumerated on the Mac, SSH worked — first
ever enumeration on the boot-with-host-attached protocol.

**Fix built, awaiting hardware verification:** build #225
(`logs/2026-07-14-225-b20-force-session-valid/`, sha256 `78b71ad3...`,
banner #225) = `patches/v6.6/phy/0001-phy-mtk-tphy-force-b-session-valid
-for-mt6797.patch` (DTS-gated: new `mediatek,force-b-session-valid`
property on u2port0 in dts/0009; forces the proven 0x3E2E state in
`u2_phy_instance_power_on`, undone in power_off, dev_info logged).
Success criterion: boot with Mac cable attached from power-on → gadget
enumerates unaided, ≥3 consecutive boots; FTDI-protocol boots
unregressed (keyboard+display+gadget). Then B-20 closes 🟢 and the
cable protocol is retired.

**VERIFIED ON HARDWARE AND CLOSED 2026-07-14.** Build #225 flashed to
boot2. Three consecutive cold boots with the Mac cable attached from
power-on — the protocol that previously failed 100% of the time — all
enumerated unaided: banner #225, `u2 phy0: forcing session-valid/device
mode` at 0.449s, DTM1 reads 0x3E2E, UDC `configured`, SSH working.
FTDI-protocol regression boot also clean
(`logs/2026-07-14-226-b20-ftdi-regression-boot.log`: banner #225 on
serial, gadget `configured` + SSH after cable swap; serial still dies at
the ~0.45s PHY switch — that is B-15, unchanged and expected). The
cable protocol ("never boot with the Mac cable in") is retired: boot
with the host attached now just works.


## ⏸️ B-21 — Internal WiFi via MT6797 CONSYS (Phase 8 Stage 2, activated 2026-07-14, **PARKED 2026-07-16**)

**PARKED (user decision 2026-07-16):** WiFi work paused in favour of
Phase 9. Parking state: **build #262** (`consys-g2b-fw-push`) is packed,
banner-verified and ready in `logs/2026-07-16-262-consys-g2b-fw-push/`
but **never flashed or tested** — it implements the full re-scoped G2b
firmware push (protocol in research.md "WMT Firmware-Push Protocol").
Resuming = flash that image to `boot2`, capture serial, judge the gate
per the boot.md #262 expected-outcome checklist. Interim networking:
USB ethernet on the right port (internet-enabled 2026-07-16, boot.md
entry) covers connectivity needs meanwhile.

**Goal:** working internal WiFi (scan/associate/DHCP/SSH-over-WiFi) via
the on-die CONSYS block — the vendor gen2 stack is the only
implementation that has ever existed (~150 KLOC WiFi; no mainline
support; frank-w's same-core port broke at kernel 6.0, unfixed). Staged
with hard gates so we can stop cheaply (plan.md Phase 8 "WiFi plan"
Stage 2; approved plan in research.md "CONSYS Stage W0 harvest").

- **Stage W0 (DONE 2026-07-14, no flash):** vendor power-on sequence
  fully source-harvested (corrections: CONN_PWR_CON=0x280 not 0x32C; no
  clk-mt6797 change needed); LK proven to leave CONSYS cold (devmem on
  #225); firmware blobs + wmt binaries extracted from Android p27 to
  `docs/firmware-consys/`; golden-reference harvest script
  `scripts/consys-golden-harvest.sh` ready for the optional vendor-Kali
  boot (W0b — needs `boot2 planet/kali_boot.img` + slow 5.5GB
  `linux planet/linux.img` flash, then Debian restore).
- **Stage W1: Gate G2a PASSED (proven live by hand 2026-07-14).** Two
  fixes en route: build #234 = pwrap reset made optional (soc/0004 —
  mt6797 has no mainline reset provider, mt6797 pwrap caps demand one);
  then scpsys "Failed to power on domain conn" root-caused live to a
  STALE vendor CONN_PWR_CON define — real offset is SPM+0x32C, not
  0x280 (0x280 rejects writes; 0x32C idles at the 0x112 off-pattern and
  acks in PWR_STATUS bit1). Manual devmem sequence at 0x32C returned
  chip-ID **0x0279** with VCN rails off and no aux pokes. Build #236
  flashed and VERIFIED: full driver-level pass at 0.58s boot, chip-ID
  0x279 first read, CONN genpd on, zero regressions (display/keyboard/
  gadget SSH). **Stage W1 COMPLETE 2026-07-14.** New:
  scpsys CONN domain (pmdomain/0002), minimal MT6351 VCN regulator
  driver over pwrap (regulator/0002 — first Linux PMIC access in the
  project), consys spike driver (soc/0003), pwrap+mt6351+consys DTS
  (dts/0013), `configs/gemini-consys.config`. Pass/fail is one dmesg
  line, checkable over gadget SSH.
- **Stage W2 (in progress 2026-07-14): Gate G2b.** Desk harvest complete:
  the WMT handshake runs over **BTIF** (AP↔CONSYS FIFO @0x1100c000,
  mainline `CLK_INFRA_BTIF` gate exists) in STP *mand mode* (4-byte hdr
  `0x80|seq<<3, type<<4|len_hi, len_lo, 0x00` + payload + 2 zero CRC,
  WMT task=4) — the full 3.5-KLOC STP core is NOT needed for the gate.
  Builds ≤#236 left the MCU held in the WDT swsysrst (bit12, key
  0x88<<24); releasing it boots the ROM. **Build #237** (sha256
  `c646178a…`, `logs/2026-07-14-237-consys-w2-g2b-mcu-handshake/`)
  extends soc/0003: EMI remap (TOPCKGEN+0x1340 = base>>20 | BIT(12)) +
  zero the 343K ctrl window, BTIF PIO init, MCU release, then
  WMT_QUERY_STP (`01 04 01 00 04`) expecting ROM event `02 04 06 00 00
  04` = **Gate G2b PASS** dmesg line. On FAIL the RX hex dump is logged
  and state left up for devmem. dts/0013 gains the btif clock.
  **#237 booted (banner verified): G2a still passes; G2b failed at step
  one with `memory-region unresolved (-22)`** — code bug: `consys_mem`
  is a dynamic reserved-memory node (no `reg`), so
  `of_address_to_resource()` can't resolve it; must use
  `of_reserved_mem_lookup()` (kernel allocated it at 0x42600000 this
  boot). **Build #238** (`consys-g2b-emi-lookup-fix`, sha256
  `1766aeb3…`, `logs/2026-07-14-238-consys-g2b-emi-lookup-fix/`) fixes
  exactly that in soc/0003. **#238 booted: EMI/remap OK, but G2b still
  -110 (TX out, 0 RX). Live SSH session then proved the MCU ROM IS
  RUNNING** (CONSYS_CPUPCR 0x18070160 changes every read) — so power/
  clock/EMI/reset are all correct and only the BTIF channel is at
  fault. Root cause: BTIF FIFOCTRL clear bits are level-held (vendor
  pulses them; we left both FIFOs in reset, discarding the ROM's
  reply), plus the never-done BTIF_WAK (+0x64) ap_wakeup_consys pulse
  before TX. **Build #239** (`consys-g2b-btif-fifo-wakeup`, sha256
  `d18973f8…`) fixes both, adds a 500ms retry and CPUPCR/LSR/IIR
  logging on FAIL. **#239 booted: still -110, but the live session
  found the real root cause — the CONN domain's TOPAXI bus-protect
  mask is bits 17|18 (vendor clk-mt6797-pg.c, the actual runtime
  path), not the MT2701 2|8 our scpsys entry used; PROTECTSTA1 bit 18
  was never released, blocking all BTIF traffic into CONSYS while
  chip-ID/CPUPCR reads (different path) worked. Build #240**
  (`consys-conn-busprot-17-18`, sha256 `2ba9b70960b8a880…`) fixes
  pmdomain/0002. **#240 booted: protect fix VERIFIED (STA1 bit 18
  clear, first query frame drained fully — path open), but still
  G2B FAIL (-110): the ROM runs (CPUPCR alternates 0x55AA55xx
  idle-pattern with real addresses 0x428/0x3538) yet never services
  BTIF — its link FIFO swallowed the first frame and stayed full;
  live MCU re-reset + immediate re-query, OSC_EN(0x10001f00 bit9) and
  BTIF_WAK pulses all no-effect; EMI ctrl window untouched by ROM;
  HW_VER 0x8A00 healthy; ACR MBIST already set; PMIC DCXO CW00 bit5
  (XO_WCN) already 1. Every register vendor's power-on touches now
  matches. See boot.md 2026-07-14 #240 entry. Next: Stage W0b
  golden-reference harvest from the working vendor Kali 3.18 stack
  (user decision — needs 5.5GB linux.img reflash + restore), to
  capture healthy-idle CPUPCR, DCXO/pwrap DCXO_CONN bridge state, and
  ROM-boot EMI signature.** **W0b golden harvest COMPLETE 2026-07-15**
  (boot.md entry; logs 2026-07-15-242/243): healthy CPUPCR = 0x0009997A
  steady → our 0x55AA55xx is ABNORMAL; working system runs with
  CONN_PWR_CON=0x10D (bit 8 SET — vendor never touches SRAM_PDN, our
  scpsys entry was clearing it: top suspect); BTIF golden HANDSHAKE=0x3
  TRI_LVL=0x18; DCXO_CONN bridge all-zero (clock-buffer theory dead);
  ROM answers the query ~50ms after reset release on golden hardware;
  0x10001f00 golden 0x6D403A00 vs our 0x11403200 (bit 11 — reserve
  suspect). **Build #244** (`consys-g2b-golden-fixes`, sha256
  `7d681d06…`) = sram_pdn_bits→0 (pmdomain/0002) + BTIF golden config +
  mand-frame byte0 fix (soc/0003). Awaiting flash (+ Debian rootfs
  restore after the Kali detour). ROM-patch download (opcodes 0x08/0x01,
  ≤1000-byte frags) is the step after the query handshake proves the
  channel. **#244 was a silent no-op** (2026-07-15): the regenerated
  soc/0003 lost its Kconfig hunk (uncommitted Mac-tree edit) and the
  untracked spike.c, so `CONFIG_MTK_CONSYS_SPIKE` was dropped by
  olddefconfig and the driver never built — #244's boot tested nothing.
  Patch fixed (Kconfig + Makefile + full spike.c). **Build #247**
  (`consys-g2b-spike-kconfig-fix`, sha256 `3810bd14…`) = the real
  golden-fixes run. **#247 booted: G2a PASS, G2b still FAIL (-110).**
  Long live-debug session (boot.md #247 entry) eliminated, one variable
  at a time on the running system: SWSYSRST bit16, MCU_CFG_ACR bits
  24/25, full golden AP2CONN_OSC_EN 0x6D403A00, the vendor AFE/WBG
  analog table (0x180B6000 — step the spike never did), BTIF
  HANDSHAKE/WAK/FIFO-clear combinations, and the EMI-MPU theory
  (remapping to golden 0xBFA00000 window + MCU reset-cycle — no
  change). Signature refined: BTIF TX shifter hard-blocks (LSR 0x60→
  0x20 on first byte, FIFO-clear resets it, next byte re-sticks), i.e.
  the CONN-side BTIF peer never initializes; MCU ROM executes (real
  PCs interleaved with 0x55AA55xx sleep samples) but parks. Remaining
  hypotheses: golden *pre-patch* ROM-idle state was never captured
  (all golden numbers are post-firmware); vendor 3.18 CCF
  `clk_scp_conn_main` (scpsys) side effects beyond our sequence;
  co-clock/XO detail (`RG_VCN28_ON_CTRL=1` HW-mode before VCN28
  enable). Device left safe: MCU parked in reset, EMI mapping restored.
- **Update 2026-07-16 — source audit of the real vendor CONSYS driver**
  (`mtk_wcn_consys_hw.c`, `wmt_core.c`, `wmt_ic_soc.c` in the 3.18 reference
  tree, not just the generic scpsys `clk-mt6797-pg.c` checked in earlier
  builds). Findings:
  - **Hypotheses 2 and 3 (from the #247 session) are now conclusively
    ruled out with source citations, not just build-log elimination.**
    `mtk_wcn_consys_hw_reg_ctrl()` is the real platform power-on function;
    its VCN18→VCN28(+`RG_VCN28_ON_CTRL=1` HW-mode switch, written *before*
    LDO enable)→`CONN2AP_SLEEP_MASK`→WDT-hold→`SPM_PWRON_CONFG_EN=0x0b160001`
    →CONN MTCMOS→chip-ID-poll→MBIST-bit sequence matches our
    regulator/0002 + soc/0003 patches step-for-step, same order, same
    values. The `mtk_wcn_consys_hw_gpio_ctrl()` companion (PIN_BGF_EINT/
    GPS_SYNC/GPS_LNA/I2S_GRP) is a dead end for us — confirmed via the
    device's own extracted DTB (`docs/vendor-dtb/gemini_kali_boot.dts`)
    that `btif@1100c000` has no pinctrl properties; BTIF is a pure
    internal AP↔CONSYS bus block on this SoC-integrated CONSYS design,
    not routed through external GPIO pins.
  - **New candidate found in `wmt_core_stp_init()`/`mtk_wcn_soc_sw_init()`
    (`wmt_core.c`, `wmt_ic_soc.c`):** the vendor's BTIF bring-up is not a
    single query/response — it's `init_table_1_2` (query, mand mode) →
    `init_table_4` (set STP options) → switch STP mode to
    `MTKSTP_BTIF_FULL_MODE` → sleep 10ms → `init_table_5` (query again, now
    in full mode). Our G2b spike sends only the equivalent of
    `init_table_1_2`'s single query and never performs the FULL_MODE
    switch — this on its own doesn't explain a zero-byte RX on the very
    first attempt (the first query should still be answerable in mand
    mode per the vendor's own `init_table_1_2` step), but it means our
    "single query is sufficient for the gate" assumption is not what the
    vendor actually does, and the fuller sequence is untested.
  - **Concrete bug found: our G2b PASS/FAIL check
    (`soc/0003`'s `wmt_query_stp_evt[]`) only matches the first 6 bytes of
    the expected reply.** The real vendor constant
    (`wmt_ic_soc.c:123`) is 10 bytes:
    `WMT_QUERY_STP_EVT_DEFAULT[] = {0x02,0x04,0x06,0x00,0x00,0x04,0x11,0x00,0x00,0x00}`
    — our `wmt_query_stp_evt[]` is missing the trailing `11 00 00 00`.
    Our TX command itself is byte-for-byte correct
    (`WMT_QUERY_STP_CMD = {0x01,0x04,0x01,0x00,0x04}`, confirmed against
    `wmt_ic_soc.c:122`). A prefix-only match wouldn't itself cause a
    zero-byte RX failure, but it means our RX path may not be reading/
    draining the full expected frame length, which is a plausible
    contributor to the observed "TX shifter blocks on retry" symptom
    (an under-drained previous reply jamming the link for the next
    attempt). Confirmed our own STP mand-mode frame-wrapping assumption
    (4-byte hdr + WMT payload + 2-byte zero CRC) is architecturally
    correct — the 5-byte `WMT_QUERY_STP_CMD` is the inner WMT payload,
    wrapped by the (skipped, ~3.5-KLOC) vendor STP core before it reaches
    BTIF; our hand-rolled equivalent framing was already sourced
    correctly in the W2 harvest.
  - **Fix implemented 2026-07-16 (not yet built/flashed):**
    `patches/v6.6/soc/0003-soc-mediatek-add-mt6797-consys-spike.patch`'s
    `wmt_query_stp_evt[]` widened to the full 10-byte
    `WMT_QUERY_STP_EVT_DEFAULT` (`02 04 06 00 00 04 11 00 00 00`). No other
    change needed: `wmt_cmd_evt()` already passes `sizeof(wmt_query_stp_evt)`
    through to the memcmp scan, and `btif_rx_drain()`'s 64-byte buffer /
    1000ms timeout already exceed 10 bytes, so the existing RX drain covers
    the wider match with no code changes beyond the constant. Verified
    `git apply --check` clean against a fresh v6.6 tree. Next: rebuild
    (build-pack), flash `boot2`, re-run Gate G2b, capture serial.
  - **Not yet attempted:** replicating the vendor's fuller BTIF bring-up
    sequence (`init_table_1_2` query → `init_table_4` set-STP-options →
    switch to `MTKSTP_BTIF_FULL_MODE` → 10ms settle → `init_table_5` second
    query) — our spike only ever sends the equivalent of `init_table_1_2`.
    Worth trying if the widened-constant fix alone doesn't flip G2b to PASS.
  - **Build #257 tested 2026-07-16 — widened constant confirmed NOT the
    root cause.** G2a still passes (chip ID 0x279). G2b still FAILs at -110
    (`ETIMEDOUT`) — both attempts report **RX 0 bytes**, so the fix (matching
    the full 10-byte event) never had a byte stream to compare against; this
    rules out "truncated match constant" as *the* cause, though the fix is
    still correct/retained (dead code otherwise). CPUPCR samples are
    changing between reads (`0x55aa55d2` → `0x55aa55d6` → `0x55aa55da`),
    confirming the MCU ROM is genuinely executing after reset release — it
    simply never answers the WMT_QUERY_STP command over BTIF. On retry, the
    *second* TX itself stalls (`BTIF TX stuck, LSR=0x20` — TEMT never sets),
    suggesting either the first frame is still sitting un-drained in the ROM
    side (no far-end consumer clearing the shifter) or our retry re-sends
    into a BTIF state the first failed exchange left wedged. This points
    back toward hypothesis territory: either (a) the ROM needs something
    from the not-yet-replicated `init_table_4`/`FULL_MODE` sequence before
    it'll answer even the first query — contradicted by vendor source
    showing `init_table_1_2` is sent standalone in mand mode first — or
    (b) our STP mand-mode frame is malformed/misaddressed in a way the ROM
    silently drops (wrong WMT task index, wrong CRC handling, wrong wakeup
    timing) even though byte-level construction matches `stp_core.c` on
    paper. **Next recommended step:** capture the TX frame bytes against a
    real vendor STP core trace/logic-analyzer if possible, or re-examine
    `stp_core.c`'s `stp_send_data_no_ps` mand-mode path byte-by-byte (only
    partially audited so far) for a subtler framing mismatch (e.g. CRC not
    actually zero, task-index bit position, or a required wakeup/ready
    handshake before the ROM's UART-equivalent ISR is listening).
  - **Update 2026-07-16 (cont.) — full BTIF hardware-init audit
    (`btif_plat.c` `hal_btif_hw_init()`, `mtk_btif.c` `_btif_send_data()`/
    `hal_btif_is_tx_allow()`, `mtk_btif_exp.c` `mtk_wcn_btif_wakeup_consys()`).**
    Traced (b) exhaustively — every BTIF register poke our spike's
    `btif_hw_init()` does was checked bit-for-bit against the real
    `hal_btif_hw_init()`: FAKELCR (both write `0x0`/normal mode), new-
    handshake-mode enable (`BTIF_HANDSHAKE_EN_HANDSHAKE`, matches), Rx/Tx
    FIFO clear-then-release sequence (matches, and is the fix from build
    #237/#238 - still correct), TRI_LVL trigger levels (matches, computed
    from the same `BTIF_TX_FIFO_THRE`/`BTIF_RX_FIFO_THRE` constants),
    loopback disabled, DMA disabled + auto-reset enabled (matches). One
    real difference found: the vendor **leaves Rx IER enabled**
    (`hal_btif_rx_ier_ctrl(p_btif, true)` at the end of hw_init) since it's
    interrupt-driven; our spike masks all IERs including Rx (`writel(0,
    BTIF_IER)`) since it polls LSR.DR instead - this is host-side-only
    register state (doesn't reach the MCU/bus), so it cannot explain the
    MCU never answering, but is worth ruling in/out empirically since it's
    now the only unexplained divergence at the BTIF hardware layer. The
    wakeup-pulse mechanism (`hal_btif_raise_wak_sig`: clear WAK, sleep
    64-96us, set WAK) is confirmed to exactly match our `btif_wakeup_consys()`,
    and per its own doc comment is only meaningful "once sleep command is
    sent to consys" (i.e. is a no-op after a cold MCU-ROM release, so its
    absence/presence shouldn't matter here). The CPU-reset-release register
    path (`mtk_wdt_swsysret_config((1<<12), ...)` = `AP_RGU_SWSYSRST` bit
    12, `0x10007018`) is confirmed identical between `mtk_wcn_consys_hw.c`'s
    two chip variants and our spike. **Conclusion: the entire AP-side
    hardware path (power-on, BTIF init, MCU release, STP mand-mode framing)
    now matches the vendor driver as closely as static source review can
    verify** - CPUPCR advancing proves the ROM is alive, yet it never
    answers on BTIF. This makes hypothesis 1 (parked pre-patch golden
    capture, per 2026-07-16 checklist) the most likely remaining
    explanation: the ROM may genuinely require something delivered by the
    proprietary WMT firmware/patch download path (not visible in the GPL
    driver source, since patch blobs and their loader protocol are closed)
    before it will respond to STP commands at all - i.e. Gate G2b as
    currently defined may be unreachable pre-firmware regardless of how
    correct our register sequencing is. Try widening the Rx IER divergence
    fix first (cheap, rules out a real if unlikely difference); if that
    doesn't change the outcome, the pre-patch-capture experiment (parked)
    becomes the most information-dense next step, since it would show
    whether the *vendor's own* pre-firmware ROM answers this same query at
    all, or whether even the real driver only gets a BTIF reply after WMT
    firmware is pushed.
  - **Build #259 tested 2026-07-16 — Rx IER fix confirmed NOT causal, as
    expected.** Matched vendor's `hal_btif_hw_init()` exactly (leaves
    `BTIF_IER_RXFEN` set instead of masking all IERs). Result: bit-identical
    failure signature to build #257 — G2a PASS (chip ID 0x279), G2b FAIL
    (-110), RX 0 bytes on both attempts, CPUPCR still advancing
    (`0x55aa55de → 0x55aa55e2 → 0x55aa55e6`), retry TX still stalls
    (`LSR=0x20`). Confirms the divergence was host-side-only as predicted
    and rules it out. **The entire AP-side hardware/software path is now
    verified correct against vendor source to the limit of static review.**
    Proceeding to hypothesis 1: the parked pre-patch golden capture
    (`logs/2026-07-16-b21-golden-prepatch-checklist.md`), simplified this
    time to flash `boot2`+`linux` with the vendor Kali stack directly
    (skip the risky `boot`-partition/Debian-rootfs combination that
    reboot-looped in the 2026-07-16 attempt) - this is the only remaining
    way to determine whether the real vendor driver's ROM answers
    WMT_QUERY_STP pre-firmware at all, or whether Gate G2b is structurally
    unreachable without the proprietary WMT patch blob.
- **Hypothesis 1 test (2026-07-16, vendor Kali stack, `boot2`+`linux`
  flashed with `planet/kali_boot.img`/`planet/linux.img`):** confirmed
  root cause for why every prior "extensive" W0b golden harvest
  (`scripts/consys-golden-harvest.sh`, builds #240/#247) only ever
  captured **post-firmware** CONSYS state, and why a true pre-firmware
  capture is not achievable from a live shell. dmesg shows
  `wmt_launcher` fires and completes both WMT firmware fragment
  downloads (`ROMv3_patch_1_1_hdr.bin`, `ROMv3_patch_1_0_hdr.bin`) by
  **11.7s uptime** — `wmt_launcher` is registered `class core` in
  `on init` inside the Android LXC's `init.connectivity.rc` (found at
  `/var/lib/lxc/android/rootfs/init.connectivity.rc` on the running
  device), Android init's earliest service class. No shell (serial,
  SSH, ADB) is reachable that early, so the firmware push always wins
  the race before any harvest script can run.
  Attempted fix: added `disabled` to the `service wmt_launcher` stanza
  and rebooted — **did not work**, because `/var/lib/lxc/android/rootfs`
  is a `tmpfs` re-populated from `/system/boot/android-ramdisk.img` by
  `pre-start.sh` on every container (re)start, so the live-tmpfs edit
  was discarded before the next boot. Attempted to patch the ramdisk
  image directly: blocked because `/system` is a loop-mounted image
  (`/data/system.img` on `/dev/loop0`) that refused `mount -o
  remount,rw` ("write-protected" at the loop-device level, not just the
  mount) — no changes were made, remount failed cleanly.
  **Conclusion (user decision 2026-07-16): stop here.** A genuine
  pre-firmware capture would require either fixing the loop-device
  write protection to patch the ramdisk properly, or a kill-loop racing
  `wmt_launcher`'s ~0.5s firmware-push window — both treated as
  disproportionate effort for this gate. **Hypothesis 1 is treated as
  confirmed by the timing evidence above without a direct pre/post
  diff:** firmware is resident on the MCU before any userspace
  observation point exists, so the AP-side path (verified correct
  against vendor source in the build #259 audit) cannot be the
  remaining blocker — G2b's WMT_QUERY_STP handshake is answered by
  ROM+firmware together, never ROM alone, and our spike (ROM-only,
  no firmware push) failing to get a reply is expected vendor-matching
  behaviour, not evidence of a driver bug.
- **Stage W3:** go/no-go on the full gen2 port (frank-w 5.6→6.6 delta
  audit); if GO, port order = WMT core → AHB HIF → cfg80211 glue, WiFi
  only. Given the hypothesis-1 conclusion above, G2b as originally
  defined (ROM-only handshake) is not a fair pass/fail gate — Stage W3
  should re-scope the gate to require pushing the real WMT firmware
  patch (already extracted to `docs/firmware-consys/`) as part of the
  spike before judging G2b, or fold G2b into the full gen2 port
  decision directly.

**Risk:** highest-uncertainty workstream in the project; the gates exist
precisely because the gen2 port may prove uneconomical. NO-GO returns
WiFi to the (parked) USB path.

- **2026-07-16 — extracted firmware review (`docs/firmware-consys/`):**
  reviewed the CONSYS firmware set pulled from the vendor image before
  attempting the G2b re-scope. Contents:
  - `ROMv3_patch_1_0_hdr.bin` (211,908 B) / `ROMv3_patch_1_1_hdr.bin`
    (46,472 B) — MediaTek ALPS ROM-patch container format (`ALPS` magic
    at offset 0x0C, build timestamp `20180615091545a`, multi-segment
    offset/length table). Filenames match exactly what `wmt_launcher`
    was observed pushing in the boot-timing capture above, so this is
    confirmed to be the right firmware, not a guess.
  - `WIFI_RAM_CODE_6797` (451,904 B) — `MTKE` magic at offset 0x00,
    chip-specific to 6797 per filename; this is the WiFi RAM-code image
    loaded after the ROM patches.
  - `WMT_SOC.cfg` — plaintext board config (coex antenna mode, GPS LNA
    pin disabled, `co_clock_flag=0`); trivial, no parsing concerns.
  - `wmt_launcher` / `wmt_loader` — vendor userspace ELF binaries,
    reference only.
  - No corruption or chip-mismatch red flags found. Gap: no local parser
    for the ALPS ROM-patch segment table/checksums, and no public spec
    to validate against — sha256 of each file recorded above for future
    integrity checks.
- **2026-07-16 — WMT firmware-push protocol extracted and spike extended
  (Stage W3 / G2b re-scope, not yet built).** Full protocol writeup:
  research.md "WMT Firmware-Push Protocol". Key findings:
  - The SoC patch path is `mtk_wcn_soc_patch_dwn()` in `wmt_ic_soc.c`
    (NOT the `opfunc_flash_patch_*` ops in `wmt_core.c` — those are for
    external-flash chips). Our extracted blobs are directly downloadable:
    28-byte `WMT_PATCH` header (datetime/"ALPS"/HwVer 0x8a00 — matches
    the HW_VER we read live) + body pushed as 1000-byte `WMT_PATCH_CMD`
    fragments (`01 01 len flag`), evt `02 01 01 00 00` per fragment,
    `WMT_RESET` after each patch. Per-patch RAM address and download
    order come from header bytes 24-27 (launcher `srh_patch()`):
    `_1_1` = seq 1 → 0xF00A0000-style addr bytes `00 00 0a f0`;
    `_1_0` = seq 2 → `00 00 09 00`. Preceded by two 6797-specific
    reg-write commands (opcode 0x08) to 0x02090508/0x02090b2c, the DLM
    power-on writes, and MCU-clock speed-up/restore tables.
  - **Vendor source contradicts strong hypothesis 1:** `sw_init` sends
    `WMT_QUERY_STP` pre-patch in mand mode and ABORTS if unanswered —
    so on working hardware the ROM alone does answer the query. The
    firmware push therefore can't be what unlocks the query, but the
    re-scoped gate is still "push firmware, then query" and the push's
    opcode-0x08 commands double as a diagnostic (does the ROM ignore
    only opcode 0x04, or all BTIF traffic?).
  - **Implemented in soc/0003** (regenerated with all hunks, verified
    `git apply --check` clean + 3 diff sections present): ROM-only query
    kept (result logged as PASS/FAIL but non-fatal), then DLM + mcuclk
    tables (non-fatal, vendor-matching), both patches pushed in seq
    order via `request_firmware()`, final `WMT_QUERY_STP` = the
    re-scoped **Gate G2b** pass/fail line. Blobs are built into the
    kernel image via `CONFIG_EXTRA_FIRMWARE` (spike probes before
    rootfs mount) — `configs/gemini-consys.config` gained
    `CONFIG_EXTRA_FIRMWARE(_DIR)` and `scripts/build-pack.sh` now
    rsyncs `docs/firmware-consys/` into the VM. `btif_rx_drain()`
    gained a 30ms idle-exit so ~260 fragment acks don't serialize on
    the 1s timeout.
  - **Build #262** (`consys-g2b-fw-push`, sha256 `c8a958d2…`,
    `logs/2026-07-16-262-consys-g2b-fw-push/`) is this change, packed
    and banner-verified, firmware confirmed embedded in vmlinux.
    Awaiting flash of `boot2` + serial capture (boot.md #262 entry has
    the expected-outcome checklist).

## 🟢 B-22 — RESOLVED 2026-07-16: right-port USB host (MUSB) + left-port charging work simultaneously — opened 2026-07-15

**RESOLVED — build #255 verified on hardware.** With the charger plugged
into the LEFT port and the RTL8156 ethernet adapter in the RIGHT port at
the same boot: `bq25890-charger-0` reports `status=Charging`,
`online=1`; `enxec9a0c162365` (right-port RTL8156) shows live RX/TX
traffic with zero errors; the left port's `usb0` gadget (RNDIS) also came
up automatically (a bonus of restoring `mediatek,force-b-session-valid`
in dts/0015 — gadget mode auto-enumerates again whenever a host is
present on the left port, same as pre-B-19 behaviour). This is the first
time charge-left + ethernet-right has been confirmed working together —
the original goal of this blocker. Full chain of fixes across builds
#252→#255, in order: (1) full-speed cap to keep the right-port MUSB link
inside the pad chain's limits (usb/0002 `maximum-speed`), (2) vendor-
accurate `num_eps=6`/trimmed EP1-5 FIFO table replacing mainline's
MT8516-shaped 8-EP config (fixed the actual bulk-data TX-stuck/three-
strikes failure, build #254), (3) `multipoint` staying at mainline's
`true` default (build #253's `multipoint=false` regressed enumeration
itself — musbfsh doesn't support multipoint addressing but mainline's
default value doesn't harm it either), (4) retiring the LEFT port's
leftover B-19 host-mode DTS (`dts/0012` behaviour) back to
`dr_mode="peripheral"` (`dts/0015`, build #255) so BQ25896 isn't forced
into OTG-source mode at every boot, blocking charger input.

**UPDATE 2026-07-16 (latest) — root cause found for "charger plugged in
but not charging": LEFT port DTS still forced host mode, unconditionally
enabling the BQ25896 OTG boost at every boot.** User plugged a charger
into the left port to test the B-22 goal; `power_supply` sysfs stayed
`Discharging`/`online=0`. dmesg showed `bq25890-charger 0-006b: enabling
OTG boost (watchdog re-disabled)` firing at 3.156s on every boot,
regardless of charger presence — traced to `patches/v6.6/dts/0012` (the
now-superseded B-19 Stage C left-port-host overlay): the `ssusb` node
still had `dr_mode="otg"` + `role-switch-default-mode="host"` +
`vbus-supply=<&otg_vbus>`, so `mtu3`'s role-switch probe auto-enables the
OTG boost regulator unconditionally, putting the charger IC into
source/OTG mode — which cannot simultaneously sink an external charger.
This was pure leftover: host duty moved to the RIGHT port (usb1/MUSB) in
build #248, but the LEFT port's DTS was never reverted to
peripheral-only. **Fix: new patch `dts/0015`** (applies after 0014,
built as **BUILD #255**) restores `dr_mode="peripheral"` on `ssusb`,
drops the `xhci` child node and OTG/role-switch/vbus-supply properties,
and swaps `u2port0`'s `mediatek,force-usb-host` back to
`mediatek,force-b-session-valid` (B-20's original device-role force —
still needed since this PHY has no hardware VBUS/session sensing).
Banner `#255` verified, DTB grep confirms `dr_mode="peripheral"` (left)
alongside the right port's unaffected `dr_mode="host"` (dts/0014). Full
analysis: boot.md 2026-07-16 "charger plugged in but NOT charging".
**Not yet tested on hardware** — awaiting flash + charger-in-left-port
retest; if `status` reads `Charging`/`online=1` with an ethernet adapter
simultaneously in the right port, B-22 closes.

**Why the two ports must be treated as fully separate problems:** the left
and right USB-C ports are driven by two different, unrelated controller IP
blocks — they do not share hardware and cannot share driver settings.
- **Left port** = `xhci-mtk`/`mtu3` at `0x11271000` — MediaTek's modern
  USB3-capable SSUSB controller (xHCI + USB2 companion), driven by the
  mainline `xhci-mtk`/`mtu3` drivers. Both the RTL8156 and Naxiang
  adapters enumerate here cleanly (bus 2 in `lsusb`).
- **Right port** = `usb11`/MUSB at `0x11200000` — a much older, USB2-only
  host-only IP (vendor calls its driver "musbfsh"), driven by mainline's
  generic MUSB core + `drivers/usb/musb/mediatek.c` glue (bus 1 in
  `lsusb`). This is a legacy Mentor Graphics MUSB IP, architecturally
  unrelated to xHCI.
Because they are different silicon with different register layouts, each
enumerates fully independently (separate USB bus, separate root hub, no
shared FIFO or arbitration) — plugging a device into one port has zero
effect on the other. But it also means **the left port's working
configuration cannot simply be copied to the right port**: `xhci-mtk`/
`mtu3` has no equivalent of MUSB's `multipoint`/`num_eps`/per-endpoint FIFO
table concept at all, so there is nothing there to port over. The right
port's correct settings have to come from the vendor's musbfsh driver for
this specific legacy IP block (see the config mismatch below) — proven on
2026-07-16 (both the RTL8156 and Naxiang worked flawlessly on the left
port on the same boot/build #253 where the right port failed for both,
confirming the fault is specific to the right-port MUSB config, not the
adapters or a general USB fault).

**UPDATE 2026-07-16 (latest) — BUILD #254 CONFIRMED: right-port bulk data
works, root cause fixed:** tested on hardware — RTL8156 in the RIGHT port
enumerated full-speed, bound `cdc_ether`, got IP `192.168.100.146`, and
this exact SSH session was carried over that interface end-to-end
(`ip -s link`: 43510B/279pkts RX, 22182B/78pkts TX, zero errors/drops; no
watchdog timeout, no three-strikes, no babble, no TXPKTRDY-stuck). Left
port's gadget (`usb0`) was confirmed `DOWN`/no-carrier during the capture,
so there is no ambiguity about which port carried the traffic. **Root
cause: `num_eps=6` + the trimmed EP1-5 512B FIFO table (matching vendor
musbfsh_config_mt65xx) was the real fix for the original TX-stuck/
three-strikes bulk failure; `multipoint=false` (added alongside it in
#253) was an incorrect extra change that broke control-transfer
enumeration entirely — reverting multipoint to `true` (mainline default)
while keeping the EP/FIFO fix resolved everything.** Full analysis:
boot.md 2026-07-16 (later) "BUILD #254 flashed and tested: RIGHT-PORT BULK
DATA WORKS". **Remaining before this blocker can close:** the actual B-22
success gate — charger plugged into the LEFT port while the ethernet
adapter runs on the RIGHT port simultaneously, confirmed via
`power_supply` sysfs showing "Charging"/`online=1` while network traffic
keeps flowing on the right interface. Not yet tested (no charger was
connected during the #254 capture — battery read "Discharging").

**UPDATE 2026-07-16 (later) — BUILD #253 REGRESSED right-port enumeration
itself; BUILD #254 isolates the variable:** #253 (multipoint=false +
num_eps=6 combined) made things worse than #252: both the RTL8156 and
Naxiang, tried on the right port, got stuck in an endless
`device descriptor read/all, error -71` retry loop — never even
completing enumeration, let alone reaching bulk. #252's 8-EP/
multipoint=true baseline at least enumerated the Naxiang fully before
failing at bulk. On the SAME boot, both adapters worked flawlessly when
swapped to the LEFT port (confirmed over SSH, .145/.146) — proof the
regression is specific to the right-port musbfsh config change, not the
adapters or a general fault (see "why the two ports must be treated as
fully separate problems" above). **Build #254** (packed+banner-verified,
`logs/2026-07-16-254-b22-right-port-multipoint-revert/`) reverts
`multipoint` back to `true`, keeping only `num_eps=6`/the trimmed EP1-5
FIFO table, to determine which half of the vendor-config change was
responsible. Full analysis: boot.md 2026-07-16 "BUILD #254".

**UPDATE 2026-07-16 (earlier) — FS test failed, root-cause candidate found, BUILD #253 ready to flash:**
the #252 full-speed experiment ran (dmesg read live over SSH): Naxiang
enumerated at full speed on the right port, then bulk still died —
TX watchdog (zero completions), TX2 FIFO stuck `csr: 2003` (TXPKTRDY
never clears), `ep2 RX three-strikes`. HS-signal-integrity theory
FALSIFIED → MAC/glue layer. Root-cause candidate from vendor source:
mainline mediatek.c uses the MT8516 OTG config (`num_eps=8`,
`multipoint=true`, EP1–7 FIFO) but MT6797 usb11 is the musbfsh IP —
vendor `musbfsh_config_mt65xx` = **num_eps=6, multipoint=false, EP1–5
512B single-buffered**. multipoint=true addresses bulk via per-EP
TXFUNCADDR/busctl registers this hardware lacks (EP0 works via FADDR,
bulk dies — exact symptom match). **Build #253** (usb/0002 extended:
`mediatek,mt6797-musb` compatible → musbfsh config via match data;
dts/0014 compatible switched; FS cap + PIO kept, single variable) is
packed and banner-verified — flash `boot2` from
`logs/2026-07-16-253-b22-right-port-musbfsh-config/`, then Naxiang in
RIGHT port; success = no watchdog/three-strikes + traffic on .146 (check
the right interface's own counters, ARP-flux warning below), then the
gate: charger LEFT + ethernet RIGHT simultaneously. Full analysis:
boot.md 2026-07-16. If #253 works, later single-variable retests: drop
FS cap (HS may have been this bug all along), then DMA.

**Goal:** host on the RIGHT port (vendor `usb1@11200000`, MUSB) so the
left port is free for charging — device currently runs on battery when
the left port carries the ethernet adapter. Charge-left + host-right is
proven vendor behaviour and right-port VBUS is independent of the
BQ25896 boost (GPIO94+GPIO72 only; live-proven, boot.md 2026-07-15).

**Works (builds #249–#252):**
- `patches/v6.6/usb/0002`: mtk-musb glue — clocks made optional (MT6797
  has only infra icusb as "main") + DT `maximum-speed` honored
  (musb_dsps pattern).
- `patches/v6.6/dts/0014`: second generic-tphy-v1 @0x11210000
  (u2port1@11210800, `mediatek,force-usb-host`, clk26m ref — vendor
  usb11 PHY is byte-for-byte tphy-v1 layout, no new driver needed);
  `usb1@11200000` on `mediatek,mtk-musb` (SPI 73 level-low,
  CLK_INFRA_ICUSB, dr_mode="host", maximum-speed="full-speed"); 4 hogs:
  GPIO94/72 (VBUS) + GPIO70 hi/71 lo (vendor USB-OTG mux position; 70
  low = HDMI alt-mode).
- phy/0001's `mediatek,force-usb-host` extended (#250) to the FULL
  vendor host state: IDDIG=0 + FORCE_SESS_MSK + RG vbusvalid/avalid/
  bvalid + SESSEND=0 + SUSPENDM — without this musb loops
  `VBUS_ERROR in a_idle (<SessEnd)` (vendor musbfsh forces the same).
- Devices ENUMERATE on the musb bus (Naxiang cdc_ether, RTL8156).
- **Vendor babble recovery proven live over devmem:** DTM1(u2port1)=
  0x1121086C: write 0x3E10 (sessend pulse) → ~200ms → 0x3E2C (session
  restore) flips DEVCTL 0x99(b_idle, wedged)→0x5D(host) and the device
  re-enumerates instantly. Candidate for a proper hook in
  musb babble recovery or the tphy driver.

**Broken:**
1. **Bulk data never flows at high speed**: cdc bulk-IN dies
   `ep2 RX three-strikes error` ×N → `Babble` → OTG FSM falls to b_idle
   (recoverable only via the devmem pulse above or reboot). TX counter
   stays 0 (urbs submitted, zero completions). MAC state is
   textbook-healthy (DEVCTL 0x5D, INTRTXE/RXE + DMA unmask all correct).
   Working theory: HS signal integrity through the external
   SW7226/FUSB301a mux chain — hence #252's full-speed cap.
2. **Inventra DMA (build #251) hard-crashes the SoC** — repeated
   green-screen panics/hangs within minutes, no pstore record (ramoops
   IS bound and mounted at 44410000 — crashes are bus lockups that never
   reach the panic path). Suspected rogue/unclocked DMA bus master (the
   glue's "mcu" clock has no MT6797 equivalent). DMA stays OFF
   (MUSB_PIO_ONLY=y) until understood.
3. Mainline glue **unbind oopses** (NULL deref in devm_usb_phy_release)
   — never unbind musb; upstream bug, not chased.

**RESUME HERE (build #252 is flashed, banner verified, FS cap active):**
plug a USB device (Naxiang adapter, .146 static) into the RIGHT port and
test whether bulk finally flows at full speed: expect dmesg
"new full-speed USB device number N using musb-hdrc" (NOT high-speed),
then ping/SSH via it with the left adapter unplugged or the route
pinned (beware Linux ARP-flux false positives — the left interface
answers ARP for the right one's IP; check the RIGHT interface's RX/TX
counters, not just ping success). If FS bulk works → right port is
SSH-grade usable; write it up, then optionally chase HS (PHY eye/slew
tuning vs mux) and DMA later. If FS bulk ALSO three-strikes → the
problem is not HS signal integrity; next suspects = musb PIO IRQ
handling on this glue / the missing "mcu" bus clock.

**Static IPs (rootfs, by MAC):** RTL8156 = 192.168.100.145, Naxiang =
192.168.100.146. No default route on either. RTL8156-on-left passed no
traffic once on #252 with the newly-installed rtl8156b-2.fw — if it
recurs, delete /lib/firmware/rtl_nic/rtl8156b-2.fw (was working
fw-less). /root/h.sh + /root/s.sh have the left-port recovery/status
pokes; the babble-recovery devmem pair above is NOT yet in h.sh.

**Related:** B-19 (left port, RESOLVED — including these left-port
follow-ups: bq25890 boost does not self-resume after charger removal;
xhci misses disconnect events, recovers on next connect; two-crash
"reboot panic" mystery from #248 remains unexplained). CLAUDE.md Phase 8
table row updated 2026-07-15.
