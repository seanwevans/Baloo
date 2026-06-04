# Baloo makefile

SRC := $(wildcard src/*.asm)
INC := $(wildcard include/*.inc)
OBJ := $(patsubst src/%.asm,build/%.o,$(SRC))
BIN := $(patsubst src/%.asm,bin/%,$(SRC))

FMT_FILES := $(SRC) $(INC)
FMT_SCRIPT := scripts/asmfmt.py
TEST_FLAGS ?= --timing

.PHONY: all setup clean test format lint-format check-readme-links

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
	bats $(TEST_FLAGS) tests/test_all.bats

check-readme-links:
	python3 scripts/check_readme_links.py

clean:
	rm -f build/*.o bin/*
