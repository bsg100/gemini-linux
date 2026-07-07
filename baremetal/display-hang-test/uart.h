#ifndef UART_H
#define UART_H

#include <stdint.h>

void uart_putc(char c);
void uart_puts(const char *s);
void uart_puthex(uint64_t v);
void uart_putdec(uint64_t v);

#endif
