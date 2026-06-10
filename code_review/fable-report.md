# fable-report.md — Independent Project Assessment

**Date:** 2026-06-10
**Scope:** All project markdown (CLAUDE.md, hardware.md, research.md, driver_ports.md, boot.md, patches/, code_review/, archive/)
**Requested by:** Ben — "Is this project likely to be successful? Are we on the right track? What can be improved?"

---

## 1. Verdict in One Paragraph

Measured against the project's own Definition of Success — *boot a modern Linux kernel on the Gemini PDA using primarily upstream components, maintainably* — this project is **likely to succeed**. The boot-critical hardware is almost entirely covered by mainline drivers, the one gap (RT5735) has a safe fixed-voltage workaround, and a prior community project (Jasu buildroot) already proved mainline-to-serial-console is achievable on this device. The methodology is genuinely strong — better than most hobbyist bring-up efforts and comparable to professional hardware-enablement practice. However, the *usable-device* milestones are much less certain: display is the long pole (dual-DSI CMD-mode panel on an SoC that has never had a mainline DRM path), and Wi-Fi is correctly assessed as out of practical reach. The main process risk right now is **building too far ahead of hardware verification** — six subsystems are "code complete" while the device has never booted anything newer than 3.18 and the FTDI cable hasn't arrived.

---

## 2. Probability Assessment by Milestone

| Phase | Milestone | Likelihood | Reasoning |
|-------|-----------|-----------|-----------|
| 3 | Kernel boots to serial output | **Good** | CPU/GIC/timer/clk/pinctrl/pwrap/UART all mainline; `mt6797.dtsi` exists upstream; Jasu buildroot precedent. Contingent on the LK handoff unknowns (§4.1). |
| 4 | eMMC root + userspace | **Good** | `mtk-sd.c` is mature with an MT6797 binding. Rootfs rebuild is a known, previously-executed procedure (archive). |
| 6 | Keyboard | **Good** | Simple I2C expander + `matrix_keypad`; Gemian validated the keymap on real hardware; full keymap already extracted. |
| 7 | Charging | **Good** | `rt9467-charger.c` explicitly supports RT9466 — the easiest win in the usability tier. Fuel gauge correctly deferred. |
| 5 | Display | **Uncertain — the long pole** | Never-mainlined DDP path, unverified MIPITX PLL maths, and a panel that *requires dual-DSI* for native resolution while the port is single-DSI only. Expect the most hardware iteration here. |
| 8 | Networking (USB-Ethernet) | **Good** | Correct decision; no porting needed. One open risk: MT6797 absent from the `xhci-mtk` device table — flagged honestly in hardware.md. |
| 9 | Wi-Fi/BT | **Poor (correctly deferred)** | ~75–103 KLOC vendor stack, broken upstream since 5.7/6.0, requires a userspace daemon. The Phase 9 deferral and USB-Ethernet fallback is exactly the right call. |

**Net:** the project as *defined* (boot + maintainability) is likely to succeed. The project as a *daily-usable Gemini* hinges on display, which is genuinely hard and cannot be de-risked without hardware in the loop.

---

## 3. What Is Being Done Right

These are not faint praise — they are the specific practices that make success probable:

1. **Upstream-first discipline, properly applied.** Every "Use Upstream" call in hardware.md is backed by a named mainline file, and the inventory repeatedly resists the temptation to port vendor code where a clean rewrite exists (clk, pinctrl, MSDC, thermal, watchdog, ASoC, IIO sensors). The "do not port from 3.18" notes are exactly right.

2. **Honest self-correction is recorded, not buried.** Three examples stand out:
   - The AW9523B "mainlined ~6.0" claim was retracted with evidence (`no aw9523 entries in drivers/gpio/`).
   - The GCC ≤ 4.9 requirement was *empirically tested* and debunked (archive/progress2.md session 2 is a model of hypothesis elimination).
   - The `last_kmsg`/SRAM diagnostic was invalidated, and the conclusions that depended on it were explicitly marked superseded.
   This habit is the single best predictor of bring-up success, because bring-up is mostly error-correction.

3. **The adversarial review → STANDARDS.md loop.** Commissioning a hostile maintainer-style review of your own patches, recording BLOCK/WARN findings, fixing what's fixable, flagging what's verification-blocked, and *then distilling the findings into mandatory rules for future patches* is rare discipline. The serial-observability rule (silent error return = BLOCK) is precisely the right first-class constraint for a UART-only debug environment.

4. **Lessons from the archive were actually absorbed.** The 3.18-era failures map directly onto current safeguards: sensor crash loops → STK3x1x flagged as the known crash root-cause and excluded; `mtk wl` GPT corruption → hard ban codified in three places; "validate before building big" → 2 GB test image lesson; flash-cycle cost → patches kept isolated and DTS nodes disabled.

5. **Risk framing per patch.** Every findings.md entry ends with a worst-case-failure-mode and recoverability statement ("BROM-recoverable, no brick path"). That is exactly the right question to ask before flashing anything.

6. **Phased milestones with explicit non-goals.** "The target is not a usable system" in Phase 3 is the correct framing and protects against scope creep.

---

## 4. Risks and Gaps (Ordered by Severity)

### 4.1 The decisive unknown is untested: will LK boot a 6.6 image at all? — **highest risk**

Everything in this repo assumes the LK bootloader will load and jump into a mainline `Image.gz` + appended/passed DTB the same way it boots the 3.18 image. The archive contains a *sobering unresolved mystery*: a rebuilt 3.18 kernel — byte-identical DTB, identical packaging, identical load addresses, eventually even the identical GCC 4.9 toolchain — **still failed to boot, and the root cause was never found** (archive/progress2.md). If an external factor (LK image verification, kernel size limit, DTB handling quirk, header field) was silently killing that build, it will kill the 6.6 build too. Nothing in the current docs addresses this.

**Implication:** the very first Phase 3 flash may produce a silent dead boot for reasons unrelated to the 6.6 kernel itself. Plan for that outcome in advance (see §5.2, §5.3).

### 4.2 Console identity contradiction — boot-critical, unresolved

- hardware.md and CLAUDE.md: console is **ttyMT0** at 921600.
- archive/progress2.md: the known-good 2019 kernel's embedded `CONFIG_CMDLINE` says **ttyMT3,921600**.
- The fixed dts/0001 sets `console=ttyS0,921600n8` (correct *naming* for mainline 8250_mtk, but which physical UART does `serial0` alias point to?).

If the DTS aliases route the console to the wrong UART, Phase 3 produces zero output and is indistinguishable from a dead kernel. **This is the single most important value in the project right now and the documentation actively disagrees with itself.** Resolve before the first flash: extract `chosen/bootargs` and the UART that LK itself logs on from the vendor DTB, and reconcile hardware.md vs the archive finding. (Possibility to rule out: ttyMT3 may have been the *engineering board* console while the FTDI pads route to a different UART.)

### 4.3 Building ahead of hardware — process drift

Phases 5 and 6 driver code is "complete" while Phase 3 has never run. Eight patches exist; per findings.md, several carry **verification-blocked BLOCKs** (RT5735 slew/VSEL provenance, FUSB301A role decode "likely inverted", MIPITX PCW maths "self-contradictory", DDP topology uncited). The archive lesson — *"validate the kernel can reach userspace before building a full rootfs"* — is being repeated in driver form. The mitigations are real (nodes disabled, patches isolated, honesty in flagging), so this is wasted-work risk rather than safety risk, but writing more unverifiable code now has negative expected value. The right move is to stop net-new driver work until first serial output.

### 4.4 Required project documents are missing

CLAUDE.md mandates **kernel.md** (config decisions) and **blockers.md** (known blockers/risks); neither exists. There is also no root README.md (git history says one was added; it is no longer present — likely lost in the docs reorganisation commit). Blockers are currently scattered across hardware.md notes, driver_ports.md open questions, and memory. A contributor (or a future session) cannot currently answer "what is blocked and on what" from one place — which CLAUDE.md explicitly requires.

### 4.5 Reserved-memory carve-outs still unknown

dts/0001 ships a flat memory node with a TODO. If the 6.6 kernel stomps the ATF/TEE/SCP carve-outs, the result is exactly the silent-death failure mode Phase 3 cannot afford. **The data to fix this is already in the project's possession:** the decompiled vendor DTB (6098 lines) almost certainly contains the `reserved-memory` nodes. This is a cheap, high-value extraction that should happen before first flash — and note the vendor DTS is referenced as `/tmp/gemini_kernel.dts`, a path that evaporates on reboot (§4.7).

### 4.6 dts/0006 display nodes default to enabled

Findings.md flagged that the MM/display nodes in the shared `mt6797.dtsi` patch default `status="okay"`, pulling MM clocks and power domains into a boot-only phase — violating the project's own STANDARDS.md rule 7 ("leave display/MM blocks disabled until their milestone"). Flagged but not yet fixed. Fix before any Phase 3 build that applies all patches, otherwise the display patches can hang the minimal boot they were supposed to stay out of.

### 4.7 Fragile references and stale facts

- The vendor decompiled DTS — cited throughout hardware.md and driver_ports.md as the source of truth for register addresses — lives in `/tmp/`. It should be committed (or regenerated into `docs/`) before it silently disappears.
- findings.md states "no datasheets … are in this repo," but `docs/MT6797_Functional_Specification_V1_0.pdf` has since been added. Several "verification-blocked" findings (MIPITX register layout, UART bases, possibly reserved-memory map) may now be resolvable *from the repo* without hardware. Nobody has re-run that pass.
- hardware.md "Recommended minimum kernel version: 6.1 LTS" while citing the MT6351 regulator as mainlined in 6.2 — harmless now that the target is 6.6, but internally inconsistent.
- dts/0001 carries a `richtek,rt9467`-at-0x53 inconsistency with no charger patch behind it (dangling compatible, flagged in findings, unresolved).

### 4.8 Userspace compatibility is acknowledged but unplanned

The 2019 `linux.img` rootfs ships systemd built against kernel-3.18-era expectations and was previously found incompatible *the other way* (systemd 260 needs ≥4.15). Running it under 6.6 is plausible but unproven, and the project already knows how to build a fresh rootfs (`mmdebstrap`, archive). This doesn't block Phase 3 but will land exactly when Phase 4 needs momentum. A decision (fresh rootfs vs. test existing) costs little to make now.

### 4.9 Display: dual-DSI may not be optional

driver_ports.md honestly notes single-DSI "will either reduce resolution, halve refresh rate, **or fail to display**". For a CMD-mode panel whose controller was initialised by vendor code only ever in dual-port mode, "fail to display" is a real possibility, and the mainline MTK DRM dual-DSI story is weak. Keep expectations calibrated: Phase 5's "simplest practical approach" may stall, and the project should be emotionally prepared to call a reduced display mode (or even long-term deferral) acceptable, per its own priority order.

---

## 5. Recommended Improvements (Concrete, Ordered)

1. **Freeze new driver work until first serial output.** Phase 3 is the only milestone that de-risks everything else. Every engineering hour before the cable arrives should go into items 2–6 below, all doable without hardware.

2. **Resolve the ttyMT0 / ttyMT3 / ttyS0 console contradiction** from the vendor DTB and known-good config, document the answer in boot.md, and make dts/0001's `stdout-path`/bootargs match. This is the highest-value pre-flash task in the project.

3. **Extract the reserved-memory map from the vendor DTB now**, add the carve-outs (and a ramoops/pstore region) to the board DTS, and commit the decompiled vendor DTS into the repo (e.g. `docs/vendor-dtb/`) so the project's primary evidence source isn't in `/tmp`.

4. **Run a re-verification pass against the MT6797 Functional Specification PDF** now in `docs/`. Re-open the verification-blocked findings (MIPITX PLL/PCW, DSI registers, UART, possibly the DDP topology) and either clear them with citations or confirm they truly need hardware. Update findings.md's "no datasheets in repo" statement.

5. **Define the minimal Phase 3 boot artifact explicitly** in kernel.md: `Image.gz` + minimal DTS (CPU, GIC, timer, UART, fixed regulators, *nothing else*) + small busybox initramfs with `earlycon`, applying *only* the patches that minimal boot needs (i.e., none of drm/panel/phy/gpio/usb). Don't let `build.sh patch` apply all eight patches to a Phase 3 build. Fix dts/0006 to `status="disabled"` regardless.

6. **Write the missing documents.** `blockers.md` (consolidate: FTDI cable, LK handoff unknowns, console identity, reserved-memory, dual-DSI, userspace compat, RT5735/FUSB301A datasheet gaps) and `kernel.md` (defconfig strategy, what's enabled for Phase 3 and why). Restore a root README.md. These are CLAUDE.md obligations, and blockers.md in particular would have surfaced §4.2 already.

7. **Pre-plan the "no UART output" branch.** Given the archive's unsolved 3.18 rebuild failure, assume a ≥30% chance the first 6.6 flash is silent. Decide *now* what the diagnostic ladder is: verify FTDI wiring against a known-good 3.18 boot first (cable test ≠ kernel test), then earlycon variants, then LK-level checks (does LK itself print? does it reject the image?), then minimal-DTS bisection. Capturing a known-good 3.18 boot log over FTDI as step zero both validates the cable and finally gives the project a baseline boot log — boot.md is waiting for one.

8. **Decide the Phase 4 rootfs strategy now** (recommend: fresh `mmdebstrap` arm64 rootfs, since the procedure is already proven in the archive and removes the 2019-userspace variable entirely).

9. **Minor hygiene:** reconcile the RT9466/0x53 dangling compatible in dts/0001; fix the 6.1-vs-6.2 inconsistency in hardware.md; date-stamp "code complete, compiles" claims so future readers know what kernel snapshot they were true against.

---

## 6. Bottom Line

- **Likely to succeed?** Yes, for the stated definition of success (modern kernel, serial-debuggable boot, upstream-first, maintainable). The boot-critical inventory is in unusually good shape, and the team behaviour — empirical testing of assumptions, recorded corrections, adversarial review — is the kind that gets bring-up projects across the line.
- **On the right track?** Yes on strategy and documentation; slightly off on sequencing — too much speculative driver work ahead of the first boot, and two boot-critical facts (console UART, reserved memory) still unresolved despite the evidence to resolve them being in hand.
- **Biggest single risk:** the LK → mainline-kernel handoff, compounded by the archive's never-explained rebuilt-3.18 boot failure. Treat the first 6.6 flash as an experiment about *LK*, not about Linux 6.6.
- **Biggest improvement available today, without the cable:** resolve the console contradiction, extract reserved-memory from the vendor DTB, and re-verify the blocked findings against the MT6797 spec PDF now sitting in `docs/`.
