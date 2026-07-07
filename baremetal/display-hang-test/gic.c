/*
 * Minimal GICv3 bring-up for cpu0's redistributor + CPU interface, and the
 * EL1 physical timer PPI. Addresses from docs/vendor-dtb/gemini_kali_boot.dts
 * ("interrupt-controller@19000000", compatible "arm,gic-v3"):
 *   GICD  base 0x19000000
 *   GICR  base 0x19200000 (first frame == cpu0, RD_base + SGI_base,
 *                           0x10000 bytes each per GICv3 spec)
 *
 * This exists so the diagnostic payload has a heartbeat mechanism that is
 * completely independent of anything Linux does (no GIC driver, no irqchip
 * probe, no cpuhp) -- see boot.md B-13 history: Linux's own cross-CPU IPI
 * and cpu0-local hrtimer heartbeats both die at the same ~2.4s mark, and the
 * open question is whether that is a genuine hardware/bus lock or something
 * specific to Linux's own interrupt/scheduler plumbing. If this bare-metal
 * heartbeat (arch timer PPI, raw GICv3 registers, nothing else running)
 * survives indefinitely after the same register sequence, that is strong
 * evidence the lock is Linux-software-specific, not hardware.
 */
#include "gic.h"
#include "uart.h"

#define GICD_BASE	0x19000000UL
#define GICD_CTLR	(GICD_BASE + 0x0)
#define GICD_CTLR_ENABLE_G1NS	(1u << 1)
#define GICR_BASE	0x19200000UL	/* cpu0's frame; RD_base */
#define GICR_SGI_OFF	0x10000UL	/* SGI_base = RD_base + 0x10000 */

#define GICR_WAKER	(GICR_BASE + 0x14)
#define GICR_WAKER_PROCESSOR_SLEEP	(1u << 1)
#define GICR_WAKER_CHILDREN_ASLEEP	(1u << 2)

#define GICR_IGROUPR0	(GICR_BASE + GICR_SGI_OFF + 0x080)
#define GICR_ISENABLER0	(GICR_BASE + GICR_SGI_OFF + 0x100)
#define GICR_IPRIORITYR	(GICR_BASE + GICR_SGI_OFF + 0x400)

#define PPI_PHYS_TIMER_NS	30

volatile uint64_t g_heartbeat;

static inline void mmio_write32(uint64_t addr, uint32_t val)
{
	*(volatile uint32_t *)addr = val;
}

static inline uint32_t mmio_read32(uint64_t addr)
{
	return *(volatile uint32_t *)addr;
}

static inline uint64_t read_icc_sre_el1(void)
{
	uint64_t v;
	__asm__ volatile("mrs %0, S3_0_C12_C12_5" : "=r"(v));
	return v;
}

static inline void write_icc_sre_el1(uint64_t v)
{
	__asm__ volatile("msr S3_0_C12_C12_5, %0" :: "r"(v));
	__asm__ volatile("isb");
}

static inline void write_icc_pmr_el1(uint64_t v)
{
	__asm__ volatile("msr S3_0_C4_C6_0, %0" :: "r"(v));
}

static inline void write_icc_igrpen1_el1(uint64_t v)
{
	__asm__ volatile("msr S3_0_C12_C12_7, %0" :: "r"(v));
	__asm__ volatile("isb");
}

void gic_cpu0_init(void)
{
	uint32_t waker;

	/*
	 * Enable Group-1 NS at the distributor. Normally the OS's own GIC
	 * driver does this (ATF/EL3 firmware typically only sets up
	 * affinity routing, not per-group enables) -- since we bypass Linux
	 * entirely, we own this too. OR-only: doesn't disturb ARE/routing
	 * bits ATF may have already configured.
	 */
	mmio_write32(GICD_CTLR, mmio_read32(GICD_CTLR) | GICD_CTLR_ENABLE_G1NS);

	/* Wake cpu0's redistributor. */
	waker = mmio_read32(GICR_WAKER);
	waker &= ~GICR_WAKER_PROCESSOR_SLEEP;
	mmio_write32(GICR_WAKER, waker);
	while (mmio_read32(GICR_WAKER) & GICR_WAKER_CHILDREN_ASLEEP)
		;

	/* PPI 30 (EL1 non-secure phys timer): group 1 (NS), enabled, mid priority. */
	mmio_write32(GICR_IGROUPR0, mmio_read32(GICR_IGROUPR0) | (1u << PPI_PHYS_TIMER_NS));
	mmio_write32(GICR_ISENABLER0, (1u << PPI_PHYS_TIMER_NS));
	{
		uint32_t reg = mmio_read32(GICR_IPRIORITYR + (PPI_PHYS_TIMER_NS & ~0x3u));
		uint32_t shift = (PPI_PHYS_TIMER_NS & 0x3u) * 8;
		reg &= ~(0xffu << shift);
		reg |= (0xa0u << shift);
		mmio_write32(GICR_IPRIORITYR + (PPI_PHYS_TIMER_NS & ~0x3u), reg);
	}

	/* CPU interface via system registers (ICC_SRE_EL1.SRE). */
	write_icc_sre_el1(read_icc_sre_el1() | 1);
	write_icc_pmr_el1(0xff);	/* accept all priorities */
	write_icc_igrpen1_el1(1);	/* enable group 1 (NS) interrupts */

	uart_puts("[gic] cpu0 redistributor + CPU interface up, PPI30 enabled\n");
}

void timer_arm(uint64_t period_ticks)
{
	__asm__ volatile("msr cntp_tval_el0, %0" :: "r"(period_ticks));
	__asm__ volatile("msr cntp_ctl_el0, %0" :: "r"((uint64_t)1)); /* ENABLE, !IMASK */
}
