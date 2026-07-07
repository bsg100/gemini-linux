/*
 * B-13 bare-metal diagnostic: does cpu0 hard-lock (as it does under Linux,
 * ~2.4s after cacheinfo_sysfs_init, killing every interrupt source
 * including its own local timer -- boot.md "BUILD #104/#105") when driven
 * by a completely independent heartbeat with no Linux scheduler, RCU,
 * cpuhp or GIC driver involved at all?
 *
 * Scope of this first cut: only the scpsys MM-domain power-on sequence is
 * replicated (drivers/pmdomain/mediatek/mtk-scpsys.c scpsys_power_on(),
 * MT6797 MM domain: SPM base 0x10006000, ctl_offs 0x30C -- exact bits used
 * below). This step was already independently proven NOT to be the trigger
 * under Linux (boot.md "per-step power-on trace": every domain reaches
 * "done", and LK leaves MM already powered so the kernel's own power-on is
 * a no-op ride). It's included here anyway as a first-cut control: if this
 * payload's heartbeat cannot even survive touching an already-proven-safe
 * register sequence, that points at a bug in *this* harness (GIC/timer
 * setup), not at B-13 itself.
 *
 * Deliberately NOT yet replicated: SMI larb/common enable and DSI/MIPI
 * controller init. Those need register-level detail pulled from the vendor
 * ddp_drv.c sequence that wasn't carried into this harness in this first
 * pass -- see baremetal/display-hang-test/README.md for the follow-up plan.
 * Every one of those steps was *also* individually proven not to hang
 * immediately under Linux; the actual B-13 trigger remains unidentified,
 * so this payload cannot yet prove or disprove a hardware lock -- it can
 * only establish whether the harness itself (GIC + arch timer, no Linux)
 * is sound as a base to build the fuller replication on.
 */
#include <stdint.h>
#include "uart.h"
#include "gic.h"

#define SPM_BASE		0x10006000UL
#define SPM_MM_PWR_CON		(SPM_BASE + 0x30C)

#define PWR_RST_B_BIT		(1u << 0)
#define PWR_ISO_BIT		(1u << 1)
#define PWR_ON_BIT		(1u << 2)
#define PWR_ON_2ND_BIT		(1u << 3)
#define PWR_CLK_DIS_BIT		(1u << 4)

static inline void mmio_write32(uint64_t addr, uint32_t val)
{
	*(volatile uint32_t *)addr = val;
}

static inline uint32_t mmio_read32(uint64_t addr)
{
	return *(volatile uint32_t *)addr;
}

static inline uint64_t read_cntfrq(void)
{
	uint64_t v;
	__asm__ volatile("mrs %0, cntfrq_el0" : "=r"(v));
	return v;
}

static inline uint64_t read_cntpct(void)
{
	uint64_t v;
	__asm__ volatile("mrs %0, cntpct_el0" : "=r"(v));
	return v;
}

static inline void write_icc_eoir1_el1(uint64_t v)
{
	__asm__ volatile("msr S3_0_C12_C12_1, %0" :: "r"(v));
}

static inline uint64_t read_icc_iar1_el1(void)
{
	uint64_t v;
	__asm__ volatile("mrs %0, S3_0_C12_C12_0" : "=r"(v));
	return v;
}

static uint64_t g_period_ticks;

/* Called from vectors.S on every "Current EL, SPx" IRQ. */
void c_irq_handler(void)
{
	uint64_t iar = read_icc_iar1_el1();
	uint32_t intid = (uint32_t)(iar & 0xffffff);

	if (intid == 30) {
		g_heartbeat++;
		timer_arm(g_period_ticks);
	} else {
		uart_puts("[irq] unexpected INTID ");
		uart_putdec(intid);
		uart_puts("\n");
	}

	write_icc_eoir1_el1(iar);
}

void c_unexpected_exception(uint64_t vector_index)
{
	uart_puts("\n[EXC] unexpected exception, vector index ");
	uart_putdec(vector_index);
	uart_puts(" -- halting\n");
}

static void scpsys_mm_power_on(void)
{
	uint32_t val;

	uart_puts("[scpsys] MM ctl before: ");
	uart_puthex(mmio_read32(SPM_MM_PWR_CON));
	uart_puts("\n");

	val = mmio_read32(SPM_MM_PWR_CON);
	val |= PWR_ON_BIT;
	mmio_write32(SPM_MM_PWR_CON, val);
	val |= PWR_ON_2ND_BIT;
	mmio_write32(SPM_MM_PWR_CON, val);

	/* MT6797 PWR_STATUS/PWR_STATUS_2ND ack poll (SPM+0x180/0x184, MM = BIT(3)) */
	{
		int tries;
		for (tries = 0; tries < 100000; tries++) {
			uint32_t sta = mmio_read32(SPM_BASE + 0x180);
			uint32_t sta2 = mmio_read32(SPM_BASE + 0x184);
			if ((sta & (1u << 3)) && (sta2 & (1u << 3)))
				break;
		}
	}

	val &= ~PWR_CLK_DIS_BIT;
	mmio_write32(SPM_MM_PWR_CON, val);
	val &= ~PWR_ISO_BIT;
	mmio_write32(SPM_MM_PWR_CON, val);
	val |= PWR_RST_B_BIT;
	mmio_write32(SPM_MM_PWR_CON, val);

	uart_puts("[scpsys] MM ctl after:  ");
	uart_puthex(mmio_read32(SPM_MM_PWR_CON));
	uart_puts("\n");
}

void c_main(void)
{
	uint64_t cntfrq;
	uint64_t last_reported = 0;

	uart_puts("\n[b13-baremetal] cpu0 entry, MMU off, no Linux\n");

	gic_cpu0_init();

	cntfrq = read_cntfrq();
	uart_puts("[timer] CNTFRQ_EL0 = ");
	uart_puthex(cntfrq);
	uart_puts("\n");

	/* ~100ms period heartbeat -- fast enough to pinpoint the death window
	 * as precisely as Linux's own IPI heartbeat did (boot.md build #98/#99
	 * used 60ms, tightened to 10ms in #100/#101). */
	g_period_ticks = cntfrq / 10;

	__asm__ volatile("msr daifclr, #2"); /* unmask IRQs */
	timer_arm(g_period_ticks);

	uart_puts("[b13-baremetal] heartbeat armed, running scpsys MM power-on\n");
	scpsys_mm_power_on();

	uart_puts("[b13-baremetal] entering heartbeat loop (no further register writes)\n");

	for (;;) {
		uint64_t hb = g_heartbeat;
		if (hb != last_reported) {
			uart_puts("[hb] ");
			uart_putdec(hb);
			uart_puts(" cntpct=");
			uart_puthex(read_cntpct());
			uart_puts("\n");
			last_reported = hb;
		}
	}
}
