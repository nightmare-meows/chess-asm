AS      = nasm
ASFLAGS = -f elf64 -w-implicit-abs
LD      = ld

chess: chess.o
	$(LD) $< -o $@

chess.o: chess.asm
	$(AS) $(ASFLAGS) $< -o $@

run: chess
	./chess

clean:
	rm -f chess chess.o

.PHONY: run clean
