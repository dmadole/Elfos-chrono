
chrono.bin: chrono.asm include/bios.inc include/kernel.inc
	asm02 -b -L chrono.asm

clean:
	-rm -f *.bin *.lst

