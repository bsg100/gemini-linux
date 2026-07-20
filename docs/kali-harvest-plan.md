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
