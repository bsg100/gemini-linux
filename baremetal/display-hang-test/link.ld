/*
 * Load address matches where LK/ATF jump for the Linux kernel today
 * (see pack-boot-img.py, kernel_addr=0x40200000 header field --
 * ATF prints "[LK]jump to K64 0x40080000" then hands off to whatever's
 * decompressed there). This payload is packed the same way our Linux
 * Image.gz is (gzip'd, wrapped by pack-boot-img.py), so it lands at the
 * same physical address Linux normally starts at.
 */
ENTRY(_start)

SECTIONS
{
	. = 0x40080000;
	_image_start = .;

	.text.boot : { *(.text.boot) }
	.text : { *(.text*) }
	.rodata : { *(.rodata*) }
	.data : { *(.data*) }

	.bss (NOLOAD) : ALIGN(16) {
		*(.bss*)
		*(COMMON)
	}

	. = ALIGN(16);
	_image_end = .;
	_image_size = _image_end - _image_start;

	/DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
