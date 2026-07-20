# Vendor 3.18 kernel patches (Kali harvest builds)

Patches against a clean shallow clone of
`https://github.com/dguidipc/gemini-android-kernel-3.18.git` (apply inside
`kernel-3.18/`). Used to build the **instrumented harvest kernel** described
in [docs/kali-harvest-plan.md](../../docs/kali-harvest-plan.md) — not part of
the mainline 6.6 port.

## Build (in the build VM, native arm64, GCC 14)

```bash
cd ~/gemini-android-kernel-3.18/kernel-3.18
# .config = docs/vendor-dtb/kali_known_good_kernel.config, then:
sed -i 's/^CONFIG_CROSS_COMPILE=.*/CONFIG_CROSS_COMPILE=""/' .config
make ARCH=arm64 olddefconfig
make ARCH=arm64 CROSS_COMPILE= DRVGEN_FILE_LIST= \
     HOSTCFLAGS="-O2 -fcommon" KCFLAGS="-Wno-error" -j8 Image.gz
```

Flag rationale:
- `DRVGEN_FILE_LIST=` — bypasses MTK DrvGen/DWS codegen (its `tools/%`
  FORCE rule is broken outside the Android build). Only blocks `dtbs`,
  which we don't need: the DTB is reused unchanged from
  `planet/kali_boot.img` (instrumentation is C-only).
- `HOSTCFLAGS=-fcommon` — GCC≥10 `yylloc` duplicate in shipped dtc lexer.
- `KCFLAGS=-Wno-error` — demote the top-Makefile warnings; per-directory
  bare `-Werror`s are stripped by patch 0001 (Makefile-level `-Werror`
  wins over KCFLAGS, so a flag alone is not enough).

## Patches

- `0001-build-with-modern-gcc-and-add-ssd2092-lcm.patch` — everything
  needed for a clean GCC 14 build of the known-good Kali config:
  - strip bare `-Werror` from all Makefiles (keeps `-Werror=specific`)
  - `log2.h`: drop `noreturn` from `____ilog2_NaN` (const/noreturn
    attribute conflict, same as the historical upstream fix)
  - `proc.S`: old ARM `#alloc, #execinstr` section syntax → `"ax"`
  - add missing per-directory `-I` paths the Android build normally
    injects (mmc host, base/power, ppm_v1, cmdq, ext_disp, m4u, mu3phy,
    usb11, uart, video videox/dispsys)
  - add `lcm/aeon_ssd2092_fhd_dsi_solomon/` (our real panel's LCM driver)
    and `gpio/lp3101.c` (its power IC), both copied from the
    `gemini-android-kernel-3.18-android8` sibling tree — the dguidipc
    repo targets the aeon board's nt36672 panel and never shipped them,
    but the known-good config selects them.

Baseline verified 2026-07-20: `Linux version 3.18.41-kali
(root@gemini-build) (gcc 14.2.0)`, Image.gz 9.5 MB, zero errors.
