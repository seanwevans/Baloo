# Baloo makefile

SRC=$(wildcard src/*.asm)
OBJ=$(patsubst src/%.asm,build/%.o,$(SRC))
BIN=$(patsubst src/%.asm,bin/%,$(SRC))

all: setup $(BIN)

setup:
	mkdir -p build bin

build/%.o: src/%.asm
	nasm -f elf64 $< -o $@
    
bin/%: build/%.o
	ld -o $@ $<

clean:
	rm -f build/*.o bin/*

test: all
	bats --timing tests/test_all.bats
