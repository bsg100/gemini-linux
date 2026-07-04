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
  4. SMP secondary-CPU (CPU1) PSCI bringup hangs — worked around with
     `maxcpus=1` (root cause not yet diagnosed; SMP is a separate future
     problem, not a Phase 3 blocker).
  5. Kernel hangs at `clk: Disabling unused clocks` (mainline mt6797 clk
     driver gates a clock the hardware needs, nothing in our DT claims it)
     — worked around with `clk_ignore_unused`.
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

## 🟡 B-7 — Rootfs / userspace compatibility (Phase 4)

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
