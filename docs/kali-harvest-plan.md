# Kali Harvest Plan — instrumented vendor kernel + full-stack capture

**Created 2026-07-20.** One flash session on the vendor Kali 3.18 stack to
harvest golden-reference evidence for every parked/open subsystem at once:
Bluetooth/CONSYS (B-21), loudspeaker (B-23), audio capture, camera, LTE,
WiFi. Batched per user decision because the p29 rootfs swap is slow.

## Partition strategy (user decision 2026-07-20)

- `boot` ← **instrumented** `kali_boot.img` (replaces Android; Android can
  be reflashed from `Gemini_x25_x27_06052019/` any time).
- `boot2` ← **untouched** (mainline #269 stays resident).
- `linux` (p29) ← `planet/linux.img` for the session, then **restored** to
  `~/gemini-build/OUTPUT/debian13-rootfs.img` (sha256 `f53da1c5…`, built
  2026-07-20) + `resize2fs /dev/mmcblk0p29` on first boot.

Note: the rootfs does NOT follow the boot slot — both ramdisks mount p29,
and the harvest needs the full Kali userspace (Android LXC runs
`wmt_launcher`, HALs, `rild`), so Debian must vacate p29 for the session.

```bash
# Flash session (device in preloader mode):
~/gemini-build/mtk-venv/bin/python3 ~/mtkclient/mtk.py w boot <instrumented_kali_boot.img>
~/gemini-build/mtk-venv/bin/python3 ~/mtkclient/mtk.py w linux planet/linux.img
# Restore afterwards:
~/gemini-build/mtk-venv/bin/python3 ~/mtkclient/mtk.py w linux ~/gemini-build/OUTPUT/debian13-rootfs.img
```

Serial capture for the entire session: `scripts/ftdi-monitor.py --interactive
--log logs/YYYY-MM-DD-NN-kali-harvest.log` (vendor console is the same
UART0 @ 921600).

## Part 1 — Instrumented vendor kernel (B-21, the priority)

**Why:** #262 proved our BTIF spike never gets the ROM to consume a single
RX byte (TX jams, `LSR=0x20`), while the identical ROM accepts the vendor
firmware push every boot. A pre-firmware shell capture is impossible
(`wmt_launcher` wins the race at ~11.7s, blockers.md B-21 Hypothesis 1) —
but **kernel-side printk instrumentation has no race**: it rides inside the
working transaction. Source tree:
`/Volumes/extdata/github/gemini-android-kernel-3.18` (buildable, banner-
matched to the shipped kernel).

### Instrumentation points

All in `kernel-3.18/drivers/misc/mediatek/`; log with a common prefix
(e.g. `HARVEST:`) + `ktime` timestamps so the serial log diffs cleanly
against our #262 trace.

1. **CONSYS power-on sequence** —
   `connectivity/common/common_main/mt6797/mtk_wcn_consys_hw.c`
   - `mtk_wcn_consys_hw_reg_ctrl()` (line ~279): log every register
     write/read it performs, and sample **CPUPCR** and **`0x10001f00`**
     before/after each step (bit-11 of 0x10001f00 is the standing suspect;
     golden value `0x6D403A00`, ours `0x11403200`).
   - `mtk_wcn_consys_hw_pwr_on()` (line ~797): entry/exit + `co_clock_type`.
   - Log `gConEmiPhyBase` and the EMI MPU region setup (lines ~1024/1104).
2. **ROM handshake + firmware push** —
   `connectivity/common/common_main/core/wmt_ic_soc.c`
   - `mtk_wcn_soc_sw_init()` (line ~975): full step-by-step; hexdump every
     CMD/EVT (the `WMT_QUERY_STP_CMD` `01 04 01 00 04` at line 122 is
     byte-identical to what our spike sends — capture the exact reply and
     *when* in the sequence it is first accepted).
   - `mtk_wcn_soc_patch_dwn()` (lines ~2042/2312): per-fragment offsets,
     sizes, timing.
3. **BTIF wire level** — `btif/common/mtk_btif.c` + `btif_plat.c`
   - `_btif_send_data()` (line ~135): hexdump TX bytes + LSR before/after.
   - `btif_pio_rx_data_receiver()` / `btif_dma_rx_data_receiver()`:
     hexdump RX bytes with timestamps.
   - **Log which mode is active (PIO vs DMA) for TX and RX** — the vendor
     driver has both paths (`btif_tx_dma_mode_set`); our spike is PIO-only.
     If vendor runs DMA, that is a first-class behavioral delta.
   - In `btif_plat.c`: log the full register init (LCR/FAKELCR/FIFO/IER
     setup, clock ungating) at open — diff against our spike's init.
4. **WiFi function-on** (free ride, same WMT core): the trace above will
   also capture `WIFI_RAM_CODE_6797` push and the WMT function-control
   command that powers WiFi — log it identically.

**Build:** sync the vendor tree into the build VM, `make ARCH=arm64
kali_gemini_defconfig` + build with GCC 14. Known risk: some MTK vendor
drivers needed Android-injected include paths in the 2026-06-07 test build;
the connectivity/btif directories are exactly that class of code. If the
full build fights back, fall back strategy: build the *shipped* config
unmodified first to prove buildability, and keep instrumentation
printk-only (no structural changes) to avoid new breakage. Pack with the
vendor ramdisk from `planet/kali_boot.img` (same tooling as our
build-pack unpack/repack path).

**Fallback if the instrumented kernel won't build/boot:** flash stock
`planet/kali_boot.img` to `boot` instead and rely on dynamic debug
(`/sys/kernel/debug/dynamic_debug/control`, patterns `wmt_*`, `stp_*`,
`btif*`) enabled from a persistent init hook in the Kali rootfs (Kali gives
root, and its rootfs is writable — unlike the Android LXC ramdisk). Lower
fidelity (no hexdumps at wire level unless present as pr_debug) but no
build risk.

### Status 2026-07-20 — INSTRUMENTED KERNEL BUILT AND PACKED

- Baseline + instrumentation both build clean in the VM with GCC 14:
  patches `patches/vendor-3.18/0001` (build fixes; see its README for the
  exact make invocation) and `0002-harvest-instrumentation.patch` (forced
  WMT/STP/BTIF debug log levels, WMT TX/RX + BTIF TX/RX hexdumps,
  `harvest_snap()` register snapshots of 0x10001f00 / CPUPCR /
  TOP1_PWR_CTRL / ACK regs at power-on steps).
- Flashable image: `logs/2026-07-20-H1-kali-harvest-kernel/harvest_kali_boot.img`
  (sha256 `6a6b4885…`, banner `3.18.41-kali #3 … Jul 20 2026`), packed with
  the vendor DTB (`docs/vendor-dtb/gemini_kali_boot.dtb`) and the unchanged
  vendor ramdisk, reference header addrs (kernel_addr 0x40080000).
  Config/System.map alongside. Image is untested on hardware.
- **First flash attempt (H2, 2026-07-20):** image `6a6b4885…` boot-looped.
  Serial (`logs/2026-07-20-H2-kali-harvest-boot.log`): LK jumps to kernel at
  0x40080000, ~10 s of silence, then WDT reset with ATF dump — PC
  `ffffffc000086998` = inside `machine_restart` (System.map), i.e. the
  kernel panicked and spun waiting for a restart that needed the WDT to
  fire. Panic reason invisible: LK passes `printk.disable_uart=1` and the
  vendor kernel mutes the UART console — the **stock** Kali kernel is
  equally silent on serial (confirmed in the 2026-07-16-261 capture), so
  kernel serial output was never going to work unpatched.
- **Fix:** `patches/vendor-3.18/0003-harvest-never-mute-uart-console.patch`
  defeats the mute in `kernel/printk/printk.c` (console loop skip → `if (0
  && …)`), so panics and the whole HARVEST trace stream to UART0. Rebuilt
  image: `logs/2026-07-20-H3-kali-harvest-uart/harvest_kali_boot.img`
  (sha256 `214e3ebe…`, banner `#4 … Jul 20 06:49 2026`), System.map
  alongside. Untested on hardware.
- **Pre-flash finding:** vendor BTIF hard-enables **DMA for both TX and
  RX** (`ENABLE_BTIF_TX/RX_DMA` in `btif/common/inc/mtk_btif.h`); our #262
  spike is PIO-only — a first-class delta the trace will now log per
  transfer (`HARVEST-BTIF-TX: … mode=DMA|PIO`).
- **H4/H5/H6 iteration:** H3 (`#4`, UART-unmuted) panicked with a real
  alignment fault in `ram_console_early_init()` — `ioremap()` on the SRAM
  log buffer produces Device memory, and GCC14 merges adjacent struct-field
  stores into unaligned accesses that Device memory forbids. Fixed by
  `patches/vendor-3.18/0004-harvest-ram-console-ioremap-wc.patch`
  (switch to `ioremap_wc()`, Normal Non-cacheable). Rebuilt as H5 (`#5`),
  which then hit a display-pipeline NULL-pointer dereference: the vendor
  `.config` selects both NT36672 and SSD2092 LCM drivers, and LK's
  compiled-in panel identity is SSD2092, but the checked-in (non-DrvGen-
  regenerated, since `DRVGEN_FILE_LIST=` is used) `mt65xx_lcm_list.c` only
  registered NT36672 — `disp_lcm_probe()` returned NULL and later
  `dpmgr_get_input_address`/`dpmgr_path_get_last_config` dereferenced it.
  Fixed by `patches/vendor-3.18/0005-harvest-wire-ssd2092-into-lcm-list.patch`
  (manually wire the already-compiled SSD2092 driver into the dispatch
  arrays).
- **H7/H8/H9 iteration:** H7 (`#6`, LCM fix) got much further — SSD2092
  correctly identified and selected (`lcm_compare_id,ssd2092 id =
  0x01572098`) — before hitting a new defect at `t=1.76s`: the
  `reserve-memory-scp_share` DT node (16 MiB dynamic allocation, range
  `0x40000000`–`0x90000000`) failed to fit (`Reserved memory: not enough
  space all defined regions.`, 5 of 8 reserved-memory regions failed),
  leaving `scp_mem_base_phys = 0x0`. `scp_helper.c`'s
  `scp_reserve_memory_ioremap()` hit its `BUG()` guard — non-fatal in this
  vendor tree, so execution continued straight into `set_scp_mpu()`, which
  then programmed an EMI MPU protection region from the bogus zero base,
  corrupting region 22 (aliasing the display SMI larb0 range) and flooding
  the console with continuous `smi_larb0_m_97` MPU violations for the rest
  of the H8 capture (never reached login). Fixed by
  `patches/vendor-3.18/0006-harvest-scp-reserve-mem-failure-non-fatal.patch`
  (return early instead of `BUG()`, and skip `set_scp_mpu()` entirely when
  the reservation didn't succeed). Rebuilt as H9 (`#7`); untested on
  hardware. The underlying "not enough space" reservation-layout issue is
  otherwise unaddressed (SCP itself is out of scope for this harvest) —
  if it resurfaces against other reserved-memory consumers, revisit the DT
  memory map in `docs/vendor-dtb/gemini_kali_boot.dts`.
- **H10/H15 iteration:** H9 (`#7`) booted clean through userspace —
  `systemd`, `Welcome to Kali GNU/Linux Rolling!`, then Android init
  (`init: init first stage started!`) — much further than any prior
  attempt, but hard-hung at `t=44.4s` in `spm_vcorefs_screen_on_setting()`
  (`mt_spm_vcorefs_mt6797.c:310`): the SPM co-processor's screen-on Vcore
  DVFS handshake timed out waiting for `SPM_SCREEN_SETTING_DONE`, hit
  `BUG()`, and this time the board genuinely wedged — no WDT auto-reset,
  required a manual power cycle (unlike the SCP `BUG()` which just logs and
  continues in this tree). Fixed by
  `patches/vendor-3.18/0007-harvest-spm-screen-on-timeout-non-fatal.patch`
  (log + clear `SPM_CPU_WAKEUP_EVENT` so the request line isn't left stuck
  asserted, then return instead of hanging). Rebuilt as H15 (`#8`);
  untested on hardware. Root cause is still probably the same underlying
  "Reserved memory: not enough space" issue from the H7→H9 fix — not
  chased further since Vcore DVFS is out of scope for the harvest goal.
- **H16/H17 iteration — first real BTIF/WMT trace captured.** H15 (`#8`)
  cleared the SPM hang and progressed into Android init
  (`init: init first stage started!` at t=42s), then the CONSYS power-on
  sequence ran for real: `HARVEST-SNAP`/`HARVEST-WMT-TX`/`HARVEST-WMT-RX`/
  `HARVEST-BTIF-TX`/`HARVEST-BTIF-RX` all fired from t=44.7s to t=45.06s,
  capturing `WMT_SOC.cfg` firmware load, WMT command frames, and BTIF DMA
  wire-level hex dumps of what looks like the STP init handshake — the
  first golden-reference B-21 data this project has captured. It then
  hard-reset with **no panic/WDT text** (straight back to
  `Preloader Start`), preceded by 17 `[DEVAPC] Violation(R)` faults on
  `CONN_PERIPHERALS`. Root cause: **our own instrumentation.**
  `harvest_snap()` (`patches/vendor-3.18/0002`) unconditionally reads
  `conn_reg.mcu_base + CPUPCR`, including at the `"reg_ctrl-on-entry"` call
  site in `mtk_wcn_consys_hw_reg_ctrl()` — which fires *before* the
  VCN18/VCN28 regulator, MTCMOS and clock-enable steps that actually power
  the CONSYS block. `mcu_base` lives in the `CONN_PERIPHERALS` DEVAPC
  domain and only accepts AP-side reads once those steps have run, so our
  own diagnostic snapshot was hitting an unpowered peripheral. The
  underlying vendor CONSYS bring-up sequence itself looks fine — this was
  purely instrumentation getting in its own way. Fixed by
  `patches/vendor-3.18/0008-harvest-fix-devapc-violation-in-own-instrumentation.patch`
  (added an `mcu_powered` flag to `harvest_snap()`, `0` only at the
  on-entry call; the other three call sites, all post-power-on, stay `1`).
  Rebuilt as H17 (`#9`); untested on hardware.
- **H18/H19 iteration.** H17 (`#9`) confirmed the DEVAPC fix worked (no
  more instrumentation-caused violation storm) and progressed much
  further — 4642 `HARVEST-` trace lines captured, well past the earlier
  crash point — before hitting a new but familiar defect at `t=34.69s`:
  `Internal error: 96000061` (the same alignment-fault code as the earlier
  ram_console bug) in `ccci_create_ringbuf()` (`ccci_ringbuf.c`), crashing
  the `ccci_fsm3` (CCCI/modem bring-up) thread while setting up the CCIF
  shared-memory ring buffer. Same root cause class as before: the function
  writes ccif header/footer magic values via raw `*(unsigned int *)buf =
  ...` pointer stores into an `ioremap()`'d Device-memory region (confirmed
  by the adjacent `memset_io()` call in the same function) — GCC14 merges
  these into unaligned accesses, which Device memory forbids. Fixed by
  `patches/vendor-3.18/0009-harvest-ccci-ringbuf-iowrite32-alignment-fix.patch`
  (converted the four header/footer stores and their log readback to
  `iowrite32`/`ioread32`, matching the existing `memset_io()` convention).
  Rebuilt as H19 (`#10`); untested on hardware.
- **H20/H21 iteration — new failure mode, no diagnostic text.** H19
  (`#10`) confirmed the ccci_ringbuf fix (no more `Internal error:
  96000061`), but hard-reset again at t≈44.6s with **zero panic/BUG/WDT
  text** — log just cuts off mid-`btif_rx_dma_irq_handler` (last line
  `MTK-BTIF[D]btif_log_buf_dmp_in:++` with no matching `--`) and jumps
  straight back to `Preloader Start`. This is the same signature seen in
  H16 (also mid-BTIF-DMA-IRQ, also no diagnostic text), now on two
  different builds — unlike the SCP/SPM/ccci_ringbuf bugs, there's nothing
  to grep for here, consistent with either a genuine hardware watchdog
  bite (interrupts masked, CPU wedged) or a bus-level SError that isn't
  printed before reset. Also worth noting: any kernel ring-buffer content
  not yet drained to the (slow, 921600 baud) UART at the moment of a hard
  reset is lost, so the true failure point may be later than the last
  visible line. Added `patches/vendor-3.18/0010-harvest-btif-dma-irq-sequence-instrumentation.patch`:
  an atomic sequence counter bracketing both `btif_tx_dma_irq_handler` and
  `btif_rx_dma_irq_handler` (`HARVEST-IRQ:` markers at entry, before/after
  the `hal_*_dma_irq_handler` call, before/after `_btif_rx_btm_sched`, and
  exit) to narrow down which IRQ instance and which phase within it never
  completes. Rebuilt as H21 (`#11`); untested on hardware.
- **H22/H23 iteration — narrowed to a specific intermittent window.** H21
  (`#11`) hard-reset again at the same point, but this time the
  `HARVEST-IRQ:` markers pinned it down: `RX-ENTER seq=48` fires, then
  `btif_rx_dma_irq_handler:++`, then **nothing** — not even
  `RX-PRE-HAL`, which normally follows within ~5-10μs. The previous 47 RX
  IRQs all completed cleanly (seq=47 finished its whole handler in ~85μs
  just 550μs earlier), so this is intermittent, not a deterministic logic
  bug — consistent with a race or a wait on a hardware ack that
  occasionally doesn't arrive. Added finer bracketing in
  `patches/vendor-3.18/0010` (now also covers `_btif_irq_ctrl(..., false)`
  and both `hal_btif_clk_ctrl`/`hal_btif_dma_clk_ctrl` calls individually:
  `RX-PRE-IRQCTRL`/`RX-POST-IRQCTRL`/`RX-PRE-CLK1`/`RX-PRE-CLK2`/
  `RX-POST-CLK2` markers) to identify which of the three calls is the one
  that occasionally doesn't return. Rebuilt as H23 (`#12`); untested on
  hardware.
- **H24/H25 iteration — same signature on the TX path too.** H23 (`#12`)
  reproduced the hang again, but this time in `btif_tx_dma_irq_handler`:
  `TX-ENTER seq=24` fires, then nothing (no `TX-PRE-HAL`) — the RX-side
  fine markers added in H23 weren't reached since this occurrence hit TX.
  Seeing the identical "entry, then silence before PRE-HAL" signature on
  *both* handlers strongly points to the shared code in that window —
  `_btif_irq_ctrl()` (IRQ mask) or the `hal_btif_clk_ctrl`/
  `hal_btif_dma_clk_ctrl` clock-enable calls, used near-identically by
  both paths — rather than anything DMA/RX/TX-specific. Extended
  `patches/vendor-3.18/0010` with matching fine markers on the TX side
  (`TX-PRE-IRQCTRL`/`TX-POST-IRQCTRL`/`TX-PRE-CLK`/`TX-POST-CLK`) so
  whichever path reproduces next, the exact stuck call is identified.
  Rebuilt as H25 (`#13`); untested on hardware.
- **H26/H27 iteration — pinned to a single call, ruled out one theory.**
  H25 (`#13`) reproduced again and the fine markers nailed it exactly:
  `RX-PRE-CLK1 seq=58` fires, then nothing — the hang is inside
  `hal_btif_clk_ctrl(p_btif->p_btif_info, CLK_OUT_ENABLE)`
  (`btif_plat.c:321`). Checked the clock definition: `clk_btif`
  (DT clock-name `"btifc"`, `INFRA_BTIF`) is a plain `GATE()` in
  `clk-mt6797.c:1190` — the generic MTK gate-clock ops, a bare CG-bit
  register write with **no hardware ack polling** — which rules out a
  hardware-ack race inside `clk_enable()` itself. That leaves the
  function's `spin_lock_irqsave(&g_clk_cg_spinlock, ...)` as the more
  likely culprit: this global spinlock serializes many call sites across
  `mtk_btif.c` (both IRQ handlers plus several open/close/ioctl paths), so
  on this 8-core SMP part the realistic failure mode is cross-CPU
  contention or an already-wedged holder (e.g. from the DEVAPC-domain
  issues seen earlier this session) rather than a hardware wait. Added
  `patches/vendor-3.18/0011-harvest-btif-clk-lock-holder-instrumentation.patch`:
  brackets the spinlock acquire/release inside `hal_btif_clk_ctrl()` with
  `HARVEST-LOCK: ATTEMPT/ACQUIRE/RELEASE cpu=... flag=... seq=...` markers
  (`raw_smp_processor_id()`), so a hang shows which CPU is stuck waiting,
  and scanning backward for the last `ACQUIRE` with no matching `RELEASE`
  identifies the actual lock holder. Rebuilt as H27 (`#14`); untested on
  hardware.
- **H28 iteration — ruled out the lock theory too, found the real
  explanation: our own instrumentation.** H27 (`#14`) reproduced again,
  but every `HARVEST-LOCK` cycle up to and including the last one before
  the crash completed cleanly (ATTEMPT→ACQUIRE→RELEASE in ~5μs, spread
  cleanly across CPUs 0/1/2/5, zero contention) — ruling out lock
  contention. The actual hang this time was in `hal_dma_send_data()`
  (line `<810>`), reached via the *direct* blocking write path
  (`mtk_wcn_btif_write()`), not even inside an IRQ handler. Across four
  captures the hang had now appeared in four different functions
  (`btif_rx_dma_irq_handler` entry, `btif_tx_dma_irq_handler` entry,
  `hal_btif_clk_ctrl`, `hal_dma_send_data`) — a pattern of relocating
  hangs rather than one fixable spot. The real clue: every hard reset's
  `kedump` recovery data shows `wdt_status 0x2` / `fiq_step 0x20` — these
  are **genuine hardware-watchdog-timeout resets**, not silent bus/ECC
  faults, so there was nothing to find by looking at EMI/bus-error
  facilities. And the last `[WDK]: kick Ex WDT` line in H28 was at
  t=23.2s, ~19s before the t=42.5s crash — landing exactly in the window
  where the next scheduled kick would be due, and exactly overlapping the
  single densest printk burst in the whole boot (the CONSYS/WMT/BTIF
  firmware-push window, now carrying `HARVEST-SNAP` +
  `HARVEST-WMT-TX/RX` + `HARVEST-BTIF-TX/RX` + 10 `HARVEST-IRQ` markers
  per IRQ + 3 `HARVEST-LOCK` markers per clock call, all synchronous UART
  writes). Conclusion: our own diagnostic instrumentation volume was
  plausibly starving the watchdog-kick thread during that burst and
  causing the very hangs being chased — an observer-effect bug, not a
  vendor defect. **Reverted** the `mtk_btif.c`/`btif_plat.c` fine-grained
  IRQ/lock markers (patches 0010 and 0011 retracted/deleted — both files
  were clean at git HEAD otherwise, `git checkout --` was sufficient) and
  rebuilt as H29 (`#15`) with only the original harvest payload
  instrumentation (0002) and the seven real fixes (0003-0009) intact.
  Untested on hardware — this run is the test of the observer-effect
  theory: if the hangs stop, it's confirmed; if they persist, a genuine
  (if hard to localize) hardware/timing issue remains.
- **H30/H32 — theory confirmed, session paused here (2026-07-20).** H29
  (`#15`, trimmed instrumentation) booted clean twice: once all the way to
  `kali login:` (t=77.9s) with systemd startup finished and zero panics —
  the deepest and most stable boot this entire harvest session — and once
  to t=155s of steady-state background activity before capture was
  stopped mid-session (that specific capture ended before Android's LXC
  init/BT trigger ran, so it doesn't confirm or deny recurrence past that
  point). No further DEVAPC storms, no ram_console/LCM/SCP/SPM/ccci_ringbuf
  regressions — all seven real fixes hold. Session paused here per user
  decision; the observer-effect theory (H28 finding, see above) is
  considered confirmed but not exhaustively proven, since a fully clean
  capture through the BT/CONSYS trigger to a shell was not obtained.

### Status summary for next session

- **Kernel is bootable and stable** on hardware as of H29 (`#15`) —
  reaches a login prompt. Flash and capture commands are unchanged (see
  Partition strategy above); use `boot-log-triage` skill
  (`.claude/skills/boot-log-triage/`) to read captures efficiently.
- **Seven real defects found and fixed**, each with its own patch under
  `patches/vendor-3.18/`: `0003` (UART console muted by `printk.disable_uart`),
  `0004` (ram_console alignment fault, `ioremap`→`ioremap_wc`), `0005`
  (SSD2092 LCM missing from dispatch table), `0006` (SCP reserved-memory
  failure was fatal, made non-fatal), `0007` (SPM screen-on DVFS timeout
  hard-hung the board, made non-fatal), `0008` (our own `harvest_snap()`
  instrumentation tripped a DEVAPC violation by reading an unpowered
  peripheral), `0009` (ccci_ringbuf alignment fault, same class as `0004`,
  fixed via `iowrite32`/`ioread32`).
- **One likely-self-inflicted issue characterized but not fully proven
  fixed**: intermittent (~1-in-50) hard resets with no panic/WDT text,
  traced via `kedump` evidence to genuine watchdog timeouts, most likely
  caused by our own `HARVEST-IRQ`/`HARVEST-LOCK` diagnostic printk volume
  starving the WDT-kick thread during the densest logging burst in the
  boot (the CONSYS/BTIF firmware-push window) — not a vendor defect. Those
  markers were reverted; H29 booted clean in the runs captured so far.
- **B-21 (Bluetooth/CONSYS) golden-reference trace**: best captured so far
  is H18's ~4642-line `HARVEST-*` trace (CONSYS power-on through WMT
  command exchange through BTIF DMA wire-level hex dumps of the firmware
  push handshake) — real data, but that run predates the ccci_ringbuf fix
  and ended in a (now-fixed) crash rather than a clean shell. **Not yet
  obtained**: a single capture that reaches a stable shell *and* passes
  through the BT/CONSYS trigger with the harvest payload instrumentation
  (0002) active and logging. Next session: repeat H29-style captures
  (trimmed instrumentation, only 0002 + fixes) until one both logs
  `HARVEST-WMT-*`/`HARVEST-BTIF-*` lines *and* reaches `kali login:`
  cleanly, then proceed to Part 2 below.
- Rootfs restore to Debian (`~/gemini-build/OUTPUT/debian13-rootfs.img`)
  and boot2 (#269/#270) verification remain outstanding once the harvest
  session concludes (see Partition strategy above).

### Session closed 2026-07-20 — evidence disposition

User ended the harvest session here rather than chasing the missing
clean+traced capture. Disposition of what was collected:

- **Kept and committed:** the 7 fix patches (`0003`-`0009`), plus
  `logs/2026-07-20-H18-kali-harvest-boot.log` (the BTIF/WMT trace — the
  primary B-21 evidence artifact, despite ending in the pre-0009
  ccci_ringbuf crash) and `logs/2026-07-20-H32-kali-harvest-boot.log`
  (clean boot with 0009 applied and harvest markers trimmed, banner
  `#15` — proves the fixes are stable, has no HARVEST-* trace).
- **Not obtained and not scheduled:** a single capture with both a
  clean shell and an active HARVEST-BTIF/WMT trace. Re-running Part 2
  (BT function-on proof, B-23 loudspeaker checklist, camera/LTE/mic/WiFi
  passive captures) requires reflashing the instrumented vendor kernel
  again — out of scope unless explicitly resumed.
- Rootfs restore + boot2 verification: **done** 2026-07-20 — see
  boot.md's msdc1/mmcblk0-renumbering incident and recovery to build
  #269, confirmed live over SSH.
- The remaining ~28 intermediate `H*` captures in this session were
  redundant diagnostic steps superseded by H18/H32 (each isolated one
  fix) and were removed rather than committed; the associated fix is
  documented above and in the patches themselves.

## Part 2 — Passive captures on the running Kali session

Run everything below in one session, saving outputs under
`logs/YYYY-MM-DD-NN-kali-harvest/`. **Never touch any vendor `*_access`
sysfs node — they crash/reboot the vendor kernel** (see memory).

### Bluetooth (B-21)
- Full instrumented boot trace (Part 1) — the primary artifact.
- Then prove function: `hciconfig hci0 up; hcitool scan` (or Android LXC
  BT on), capturing the BT function-on WMT command sequence too.

### Loudspeaker (B-23) — checklist verbatim from blockers.md B-23
1. All-262-pin GPIO dump while speaker audible
   (`/sys/devices/virtual/misc/mtgpio/pin`): speaker-on vs off vs
   headphone-on diffs.
2. MT6351 full register dump speaker-on vs off (debug/asound nodes only).
3. dmesg with `Ext_Speaker_Amp_Change`/`Speaker_Amp_Change` dynamic debug
   enabled — which functions run, which aud_gpios have `gpio_prepare`.
4. `/proc/asound` cards/pcm + full `tinymix` dump in speaker mode.
5. PMIC LDO/BUCK enable states (regulator sysfs, not *_access).

### Audio capture (mic — still open from Phase 9)
- `tinymix` dump while `tinycap`/`arecord` is actually recording from the
  builtin mic; note the PCM device used and any UL path controls; verify
  the capture file has signal. dmesg for AFE UL configuration.

### Camera
- Trigger the camera via the Android LXC camera app (Kali side has no
  camera stack); capture dmesg from cold camera open: `imgsensor` probe
  (identifies exact sensor models + I2C addresses), `cameraisp` power/clk
  sequence, M4U/SMI activity, flashlight driver.
- Copy out `/system` camera HAL libs list + any sensor tuning files
  referenced in logcat (`logcat -d` inside the LXC) for later reference.
- `cat /proc/driver/camsensor*` (if present) and lens/cam_cal EEPROM dumps.

### LTE / modem
- dmesg of modem boot: `eccci`/`ccci_util` bring-up, MD image load
  addresses and versions (`md1img`/`md1dsp`/`md3img` partition usage).
- `/proc/ccci*` nodes, `ip link` for `ccmni*` interfaces, and rild state
  (`logcat -b radio -d` in the LXC).
- Confirm a live data session if SIM present (which ccmni carries it, its
  MTU/addresses) — golden reference for a future mainline ccci/ccmni port.

### WiFi
- Covered at wire level by Part 1. Additionally: `wlan gen2` probe dmesg,
  `iwconfig`/`iw scan` working proof, `/proc/wmt_*` debug nodes, and the
  post-on CONSYS register golden re-captured with instrumented timestamps
  (aligns the old #240/#247 harvest with the new trace timeline).

### Cheap extras (same session, near-zero cost)
- GPS (also CONSYS): AT/`/dev/gps` node behavior + WMT GPS function-on in
  the instrumented trace.
- Sensors: dmesg probe lines for the sensorHub/accelerometer/alsps stack
  (identifies parts + addresses for later Phase 9 work).
- `dmesg` full, `/proc/interrupts`, `/proc/clk` (if present), full
  `/sys/kernel/debug` clk/regulator trees — one tarball.

## Exit criteria

Session is done when: (a) instrumented BTIF/WMT trace of a successful
firmware push + QUERY_STP reply is on disk, (b) B-23 checklist items 1–5
captured, (c) camera/LTE/mic/WiFi captures above saved, (d) Debian rootfs
restored and #269 boot via boot2 verified over SSH.
