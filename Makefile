# Baloo makefile

ASM=nasm
LD=ld
TEST_FLAGS?=--timing --print-output-on-failure

SRC=$(wildcard src/*.asm)
OBJ=$(patsubst src/%.asm,build/%.o,$(SRC))
BIN=$(patsubst src/%.asm,bin/%,$(SRC))

all: setup $(BIN)

setup:
	mkdir -p build bin

build/%.o: src/%.asm
	$(ASM) -f elf64 $< -o $@
    
bin/%: build/%.o
	$(LD) -o $@ $<

clean:
	rm -f build/*.o bin/*

test: all
	bats $(TEST_FLAGS) tests/test_all.bats
