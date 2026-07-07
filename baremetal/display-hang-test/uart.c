/*
 * Direct MMIO console for UART0 @ 0x11002000 (mediatek,mt6797-uart).
 * No init here on purpose: LK has already configured baud/LCR for its own
 * boot log (921600n1, confirmed in every capture so far), and every serial
 * capture to date shows the vendor 3.18 kernel's earlycon and our own
 * mainline earlycon both working without any re-init beyond what LK leaves
 * behind. Re-touching LCR/divisor risked introducing a second variable into
 * a diagnostic that's supposed to have as few moving parts as possible.
 *
 * Register layout: drivers/tty/serial/8250/8250_mtk.c hardcodes
 * iotype = UPIO_MEM32, regshift = 2 (32-bit accesses, 4-byte register
 * stride) for this UART -- not the DT reg-shift default of 0.
 */
#include "uart.h"

#define UART0_BASE	0x11002000UL
#define UART_THR	(UART0_BASE + (0x0 << 2))
#define UART_LSR	(UART0_BASE + (0x5 << 2))
#define UART_LSR_THRE	(1u << 5)

static inline void mmio_write32(uint64_t addr, uint32_t val)
{
	*(volatile uint32_t *)addr = val;
}

static inline uint32_t mmio_read32(uint64_t addr)
{
	return *(volatile uint32_t *)addr;
}

void uart_putc(char c)
{
	if (c == '\n')
		uart_putc('\r');
	while (!(mmio_read32(UART_LSR) & UART_LSR_THRE))
		;
	mmio_write32(UART_THR, (uint32_t)(unsigned char)c);
}

void uart_puts(const char *s)
{
	while (*s)
		uart_putc(*s++);
}

void uart_puthex(uint64_t v)
{
	static const char digits[] = "0123456789abcdef";
	uart_puts("0x");
	for (int shift = 60; shift >= 0; shift -= 4)
		uart_putc(digits[(v >> shift) & 0xf]);
}

void uart_putdec(uint64_t v)
{
	char buf[20];
	int i = 0;

	if (v == 0) {
		uart_putc('0');
		return;
	}
	while (v > 0 && i < (int)sizeof(buf)) {
		buf[i++] = '0' + (v % 10);
		v /= 10;
	}
	while (i > 0)
		uart_putc(buf[--i]);
}
