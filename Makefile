# Baloo makefile

SRC := $(wildcard src/*.asm)
INC := $(wildcard include/*.inc)
OBJ := $(patsubst src/%.asm,build/%.o,$(SRC))
BIN := $(patsubst src/%.asm,bin/%,$(SRC))

FMT_FILES := $(SRC) $(INC)
FMT_SCRIPT := scripts/asmfmt.py
README_SCRIPT := scripts/update_readme.py
TEST_FLAGS ?= --timing
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
INSTALL ?= install
INSTALL_PROGRAM ?= $(INSTALL) -m 755

.PHONY: all setup install uninstall clean test format lint-format update-readme check-readme check-readme-links

.SECONDARY: $(OBJ)

all: setup $(BIN)

setup:
	mkdir -p build bin

build/%.o: src/%.asm
	nasm -f elf64 $< -o $@

bin/%: build/%.o
	ld -o $@ $<

format:
	python3 $(FMT_SCRIPT) $(FMT_FILES)

update-readme:
	python3 $(README_SCRIPT)

check-readme: update-readme
	git diff --exit-code README.md

lint-format:
	python3 $(FMT_SCRIPT) --check $(FMT_FILES)
	python3 -m compileall -q scripts/asmfmt.py $(README_SCRIPT)

test: all
	bats $(TEST_FLAGS) tests/test_all.bats

install: all
	$(INSTALL) -d $(DESTDIR)$(BINDIR)
	$(INSTALL_PROGRAM) $(BIN) $(DESTDIR)$(BINDIR)/

uninstall:
	rm -f $(addprefix $(DESTDIR)$(BINDIR)/,$(notdir $(BIN)))

check-readme-links:
	python3 scripts/check_readme_links.py

clean:
	rm -f build/*.o bin/*
