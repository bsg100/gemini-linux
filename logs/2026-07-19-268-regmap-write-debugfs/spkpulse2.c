/* spkpulse2 <npulses> [gpio] [low_ns] — register-speed amp mode-select pulses.
 * Writes the MT6797 pinctrl DOUT register directly via /dev/mem so each
 * edge is a single MMIO store (ns), unlike the gpiod ioctl path (tens of us).
 * DOUT: 0x10005100 + (pin/32)*0x10, 1 bit per pin. Ensures DIR=out first
 * (0x10005000 + (pin/32)*0x10). Leaves the line high on exit.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <time.h>

#define GPIO_BASE 0x10005000UL

static inline uint64_t now_ns(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
	return (uint64_t)ts.tv_sec * 1000000000ULL + ts.tv_nsec;
}

static inline void spin_ns(uint64_t ns)
{
	uint64_t t0 = now_ns();
	while (now_ns() - t0 < ns)
		;
}

int main(int argc, char **argv)
{
	int n = argc > 1 ? atoi(argv[1]) : 3;
	int pin = argc > 2 ? atoi(argv[2]) : 243;
	long low_ns = argc > 3 ? atol(argv[3]) : 2000;
	int bank = pin / 32, bit = pin % 32;

	int fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) { perror("open /dev/mem"); return 1; }
	volatile uint32_t *base = mmap(NULL, 0x1000, PROT_READ | PROT_WRITE,
				       MAP_SHARED, fd, GPIO_BASE);
	if (base == MAP_FAILED) { perror("mmap"); return 1; }

	volatile uint32_t *dir = base + (0x000 + bank * 0x10) / 4;
	volatile uint32_t *dout = base + (0x100 + bank * 0x10) / 4;

	*dir |= 1u << bit;              /* force output */
	uint32_t hi = *dout | (1u << bit), lo = *dout & ~(1u << bit);

	*dout = lo;                     /* start from low (amp off) */
	usleep(20000);                  /* let amp fully power down */

	for (int i = 0; i < n; i++) {
		*dout = lo;
		spin_ns(low_ns);
		*dout = hi;
		spin_ns(low_ns);
	}
	*dout = hi;                     /* leave enabled */
	printf("done: %d pulses on gpio %d (DOUT %#lx bit %d, low %ldns), left high\n",
	       n, pin, GPIO_BASE + 0x100 + bank * 0x10, bit, low_ns);
	return 0;
}
