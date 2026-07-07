#ifndef GIC_H
#define GIC_H

#include <stdint.h>

/* Bring up cpu0's GICv3 redistributor + CPU interface and unmask the
 * non-secure EL1 physical timer PPI (INTID 30). Must run before IRQs are
 * unmasked at PSTATE level. */
void gic_cpu0_init(void);

/* Arm the EL1 physical timer for periodic ticks, `period_ticks` apart
 * (units: CNTFRQ_EL0 ticks). */
void timer_arm(uint64_t period_ticks);

/* Heartbeat counter, incremented once per timer IRQ. Read from the main
 * loop to detect whether ticks have stopped arriving. */
extern volatile uint64_t g_heartbeat;

#endif
