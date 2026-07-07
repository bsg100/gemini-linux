/*
 * Entry point. LK/ATF branch here (physical address 0x40080000, same
 * address our Linux Image.gz is loaded at -- see pack-boot-img.py) with
 * MMU off, caches in an unknown state, and (per every boot capture so far)
 * all cores landing at this address, distinguished only by MPIDR_EL1.
 *
 * Only cpu0 runs the test; every other core parks in WFI immediately, since
 * B-13's hang is specific to cpu0 and we don't want secondary cores
 * generating GIC/SGI traffic that could mask the result.
 *
 * First 6 attempts (logs/2026-07-06-114 through -125) all hung identically
 * inside ATF/BL31 (same PC ~0x46026020, same ~12.3s watchdog window)
 * regardless of gzip vs raw, image size, DTB presence, or boot.img header
 * kernel_addr -- a control reflash of the known-good mainline build in
 * between (log -126) booted clean, ruling out an environment/device
 * regression. A `text_offset=0x80000` "fix" was tried and is WRONG per
 * boot.md's own prior finding ("Aligned kernel_addr Retested" /
 * "text_offset=0x0 red herring"): (a) LK always jumps to the fixed
 * 0x40080000 regardless of what's in the boot.img header's kernel_addr
 * field -- the earlier "staged address" attempt (log -124/-125) was
 * therefore a no-op from the start; (b) text_offset=0 is what every real
 * mainline arm64 kernel already ships (hardcoded in head.S), and the real
 * mechanism for surviving a misaligned load address is CONFIG_RELOCATABLE
 * self-relocation *inside* the kernel's own head.S -- which only matters
 * once code is executing. We never get that far; ATF hangs before
 * `el3_exit` every time. So text_offset isn't the bug either. Reverted to
 * 0. Root cause still open -- see README.md "Known issue" for the current
 * state and next diagnostic ideas.
 */
.section .text.boot
.global _start
_start:
	b	real_start		/* code0 */
	.word	0			/* code1 (unused) */
	.quad	0			/* text_offset -- see comment above, 0 is correct */
	.quad	_image_size		/* image_size */
	.quad	0			/* flags: LE, page size unspecified, non-relocatable */
	.quad	0			/* res2 */
	.quad	0			/* res3 */
	.quad	0			/* res4 */
	.word	0x644d5241		/* magic: "ARM\x64" (must land at offset 56 per booting.rst) */
	.word	0			/* res5 */

real_start:
	mrs	x0, mpidr_el1
	and	x0, x0, #0xff
	cbnz	x0, park_secondary

	/* SP_EL1 (SPSel=1) so the vector table's "current EL, SPx" bank applies */
	msr	spsel, #1
	ldr	x0, =_stack_top
	mov	sp, x0

	ldr	x0, =vectors
	msr	vbar_el1, x0
	isb

	bl	c_main
	/* c_main never returns; if it somehow does, fall through to park */

park_secondary:
1:	wfi
	b	1b

.section .bss
.align	4
_stack_bottom:
	.space	0x4000
_stack_top:
