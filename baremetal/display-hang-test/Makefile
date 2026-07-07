# Build in the VM (native aarch64 gcc, Debian 13) -- same reasoning as
# scripts/build.sh: no cross-compiler needed there, and this stays
# consistent with CLAUDE.md's "all kernel-adjacent builds happen in the VM"
# practice even though this is a tiny freestanding binary, not a kernel
# module.
#
# Usage (inside VM):
#   cd ~/gemini_linux/baremetal/display-hang-test
#   make
#   -> produces payload.img (gzip'd raw binary, ready for pack-boot-img.py)

CC      ?= gcc
OBJCOPY ?= objcopy

# -ffreestanding implies no hosted libc/libm assumptions, but we still want
# gcc's own freestanding headers (stdint.h etc, which declare only typedefs
# and are safe with no libc present) -- so no -nostdinc.
CFLAGS  := -ffreestanding -fno-builtin -fno-stack-protector -fno-pic \
           -mgeneral-regs-only -O2 -Wall -Wextra \
           -Wno-unused-parameter -std=gnu11
LDFLAGS := -nostdlib -static -Wl,-T,link.ld -Wl,--build-id=none

OBJS := start.o vectors.o main.o uart.o gic.o

all: payload.img

%.o: %.S
	$(CC) $(CFLAGS) -c -o $@ $<

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

payload.elf: $(OBJS) link.ld
	$(CC) $(LDFLAGS) -o $@ $(OBJS)

payload.bin: payload.elf
	$(OBJCOPY) -O binary $< $@

payload.img: payload.bin
	gzip -n -f -9 -c $< > $@
	@echo "wrote $@ ($$(stat -c%s $@ 2>/dev/null || stat -f%z $@) bytes, gzip of $$(stat -c%s $< 2>/dev/null || stat -f%z $<) byte raw payload)"

clean:
	rm -f *.o payload.elf payload.bin payload.img

.PHONY: all clean
