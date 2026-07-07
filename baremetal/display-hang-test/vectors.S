/*
 * Minimal AArch64 exception vector table. Only "Current EL with SPx" IRQ
 * (offset 0x280) does anything real; every other entry prints which vector
 * fired and spins, since seeing *that* on serial (rather than silence) is
 * itself diagnostic information (e.g. our own register pokes causing a
 * synchronous abort would show up here instead of just vanishing).
 */
.section .text
.align 11	/* VBAR_EL1 must be 2KB (0x800) aligned */
.global vectors
vectors:
	/* Current EL with SP0 */
	.align 7
	b	dump_sync_sp0
	.align 7
	b	dump_irq_sp0
	.align 7
	b	dump_fiq_sp0
	.align 7
	b	dump_serror_sp0

	/* Current EL with SPx */
	.align 7
	b	dump_sync_spx
	.align 7
	b	irq_handler
	.align 7
	b	dump_fiq_spx
	.align 7
	b	dump_serror_spx

	/* Lower EL, AArch64 */
	.align 7
	b	dump_sync_l64
	.align 7
	b	dump_irq_l64
	.align 7
	b	dump_fiq_l64
	.align 7
	b	dump_serror_l64

	/* Lower EL, AArch32 */
	.align 7
	b	dump_sync_l32
	.align 7
	b	dump_irq_l32
	.align 7
	b	dump_fiq_l32
	.align 7
	b	dump_serror_l32

/*
 * c_irq_handler is an ordinary C function and may clobber any caller-saved
 * register (x0-x18, x30); those belong to the foreground code we just
 * interrupted, not to us, so all of them must be saved/restored around the
 * call. x19-x29 are callee-saved and c_irq_handler will preserve them
 * itself per AAPCS64, but saving them too costs nothing and removes any
 * doubt.
 */
.macro save_regs
	sub	sp, sp, #256
	stp	x0, x1, [sp, #0]
	stp	x2, x3, [sp, #16]
	stp	x4, x5, [sp, #32]
	stp	x6, x7, [sp, #48]
	stp	x8, x9, [sp, #64]
	stp	x10, x11, [sp, #80]
	stp	x12, x13, [sp, #96]
	stp	x14, x15, [sp, #112]
	stp	x16, x17, [sp, #128]
	stp	x18, x19, [sp, #144]
	stp	x20, x21, [sp, #160]
	stp	x22, x23, [sp, #176]
	stp	x24, x25, [sp, #192]
	stp	x26, x27, [sp, #208]
	stp	x28, x29, [sp, #224]
	str	x30, [sp, #240]
.endm

.macro restore_regs
	ldp	x0, x1, [sp, #0]
	ldp	x2, x3, [sp, #16]
	ldp	x4, x5, [sp, #32]
	ldp	x6, x7, [sp, #48]
	ldp	x8, x9, [sp, #64]
	ldp	x10, x11, [sp, #80]
	ldp	x12, x13, [sp, #96]
	ldp	x14, x15, [sp, #112]
	ldp	x16, x17, [sp, #128]
	ldp	x18, x19, [sp, #144]
	ldp	x20, x21, [sp, #160]
	ldp	x22, x23, [sp, #176]
	ldp	x24, x25, [sp, #192]
	ldp	x26, x27, [sp, #208]
	ldp	x28, x29, [sp, #224]
	ldr	x30, [sp, #240]
	add	sp, sp, #256
.endm

irq_handler:
	save_regs
	bl	c_irq_handler
	restore_regs
	eret

/* Anything else this payload isn't meant to hit: print which vector and
 * spin forever (visible on serial, distinct from a silent hard lock). */
dump_sync_sp0:
	mov	x0, #0
	b	unexpected
dump_irq_sp0:
	mov	x0, #1
	b	unexpected
dump_fiq_sp0:
	mov	x0, #2
	b	unexpected
dump_serror_sp0:
	mov	x0, #3
	b	unexpected
dump_sync_spx:
	mov	x0, #4
	b	unexpected
dump_fiq_spx:
	mov	x0, #6
	b	unexpected
dump_serror_spx:
	mov	x0, #7
	b	unexpected
dump_sync_l64:
	mov	x0, #8
	b	unexpected
dump_irq_l64:
	mov	x0, #9
	b	unexpected
dump_fiq_l64:
	mov	x0, #10
	b	unexpected
dump_serror_l64:
	mov	x0, #11
	b	unexpected
dump_sync_l32:
	mov	x0, #12
	b	unexpected
dump_irq_l32:
	mov	x0, #13
	b	unexpected
dump_fiq_l32:
	mov	x0, #14
	b	unexpected
dump_serror_l32:
	mov	x0, #15
	b	unexpected

unexpected:
	bl	c_unexpected_exception
1:	wfi
	b	1b
