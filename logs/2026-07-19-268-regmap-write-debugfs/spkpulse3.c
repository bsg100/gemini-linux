/* spkpulse3 — exact vendor Ext_Speaker_Amp_Change ON sequence (mt6797):
 * both amp pins low -> 5ms -> 3 pulses on 243 -> 3 pulses on 244 -> both high.
 * Direct DOUT MMIO (bank7 @0x10005170, bits 19/20). */
#include <stdio.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <time.h>
static uint64_t now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC_RAW,&t);return t.tv_sec*1000000000ULL+t.tv_nsec;}
static void spin(uint64_t ns){uint64_t t0=now();while(now()-t0<ns);}
int main(void)
{
	int fd=open("/dev/mem",O_RDWR|O_SYNC);
	volatile uint32_t *b=mmap(0,0x1000,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0x10005000UL);
	if(b==MAP_FAILED){perror("mmap");return 1;}
	volatile uint32_t *dir=b+0x070/4, *dout=b+0x170/4;
	uint32_t p1=1u<<19, p2=1u<<20;
	*dir|=p1|p2;
	*dout&=~(p1|p2);            /* both low */
	usleep(5000);
	for(int i=0;i<3;i++){*dout&=~p1;spin(2000);*dout|=p1;spin(2000);}
	for(int i=0;i<3;i++){*dout&=~p2;spin(2000);*dout|=p2;spin(2000);}
	*dout|=p1|p2;
	printf("vendor-exact: both low 5ms, 3 pulses gpio243, 3 pulses gpio244, both high\n");
	return 0;
}
