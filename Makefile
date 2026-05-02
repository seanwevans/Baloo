# Baloo makefile

SRC := $(wildcard src/*.asm)
INC := $(wildcard include/*.inc)
OBJ := $(patsubst src/%.asm,build/%.o,$(SRC))
BIN := $(patsubst src/%.asm,bin/%,$(SRC))

FMT_FILES := $(SRC) $(INC)
FMT_SCRIPT := scripts/asmfmt.py

.PHONY: all setup clean test format lint-format

all: setup $(BIN)

setup:
	mkdir -p build bin

build/%.o: src/%.asm
	nasm -f elf64 $< -o $@

bin/%: build/%.o
	ld -o $@ $<

format:
	python3 $(FMT_SCRIPT) $(FMT_FILES)

lint-format:
	python3 $(FMT_SCRIPT) --check $(FMT_FILES)
	python3 -m compileall -q scripts/asmfmt.py

test: all
	bats --timing tests/test_all.bats

clean:
	rm -f build/*.o bin/*
