/* mempeek <physaddr> [count32] — dump 32-bit words via /dev/mem mmap */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <sys/mman.h>
int main(int argc, char **argv)
{
	unsigned long addr = strtoul(argv[1], 0, 0);
	int n = argc > 2 ? atoi(argv[2]) : 1;
	int fd = open("/dev/mem", O_RDONLY | O_SYNC);
	if (fd < 0) { perror("open"); return 1; }
	unsigned long pg = addr & ~0xfffUL, off = addr - pg;
	volatile uint32_t *m = mmap(0, 0x2000, PROT_READ, MAP_SHARED, fd, pg);
	if (m == MAP_FAILED) { perror("mmap"); return 1; }
	for (int i = 0; i < n; i++)
		printf("%08lx: %08x\n", addr + 4*i, m[off/4 + i]);
	return 0;
}
