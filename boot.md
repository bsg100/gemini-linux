# Boot Log and Observations

## Milestone: Baseline Kali Boot Confirmed

**Date:** 2026-06-07

**State:** Original Planet Computers Kali Linux image, flashed via the official Gemini Flash Tool (SP Flash Tool, x86 Linux) using the scatter file `Scatter_Gemini_x25_x27_A30GB_L26GB_Multi_Boot.txt`.

**Result:** Device boots and user can log in to Kali Linux.

**Kernel:** 3.18.41-kali+ (vendor BSP kernel, built by Planet Computers)
- Built: Wed Apr 2019
- Builder: root@WOPR-Debian-II
- Compiler: gcc 4.9 20150123 (prerelease)
- Config: `#12 SMP PREEMPT`

**Significance:** This is the known-good baseline. Any regression during kernel bring-up can be recovered by reflashing this image. The partition layout on this device is the authoritative reference — do not modify it.

---

## Notes

- `mtk wl` (write-from-directory via mtkclient) corrupted the partition table during an earlier attempt. Recovery required a full reflash with the official Flash Tool. See CLAUDE.md Flashing section.
- The Kali userspace (`linux.img`) was built against kernel 3.18. Compatibility with Linux 6.6 is an open question — see CLAUDE.md Open Questions.
- The `boot2` partition holds the Kali kernel (`kali_boot.img`). This is the only partition that needs to be replaced when testing a new kernel for Kali.

---

## Future Entries

Boot logs from kernel bring-up attempts will be appended here as Phase 3 progresses.
