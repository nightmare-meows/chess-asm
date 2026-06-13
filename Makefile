AS      = nasm
ASFLAGS = -f elf64 -w-implicit-abs
LD      = ld

all: chess chesswatch chessmove

chess: chess.o
	$(LD) $< -o $@

chess.o: chess.asm
	$(AS) $(ASFLAGS) $< -o $@

chesswatch: chesswatch.o
	$(LD) $< -o $@

chesswatch.o: chesswatch.asm
	$(AS) $(ASFLAGS) $< -o $@

chessmove: chessmove.o
	$(LD) $< -o $@

chessmove.o: chessmove.asm
	$(AS) $(ASFLAGS) $< -o $@

run: chess
	./chess

test: all
	python3 -m pytest -q tests

clean:
	rm -f chess chess.o chesswatch chesswatch.o chessmove chessmove.o

.PHONY: all run test clean
