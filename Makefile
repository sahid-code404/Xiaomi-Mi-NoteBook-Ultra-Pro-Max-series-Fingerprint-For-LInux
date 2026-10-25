SHELL := /bin/bash

LIBFPRINT_DIR ?= src/libfprint
BUILD_DIR ?= $(LIBFPRINT_DIR)/build
MESON_OPTIONS ?= -Ddrivers=all -Ddoc=false -Dintrospection=false -Dinstalled-tests=false -Dudev_hwdb=enabled

.PHONY: help check syntax smoke lint configure build unit-test clean

help:
	@printf '%s\n' \
	  'Targets:' \
	  '  make check       Shell syntax, safety smoke tests, and ShellCheck' \
	  '  make syntax      Check Bash/POSIX shell syntax' \
	  '  make smoke       Run installer/uninstaller safety smoke tests' \
	  '  make lint        Run ShellCheck (install shellcheck first)' \
	  '  make configure   Configure the vendored libfprint Meson build' \
	  '  make build       Compile libfprint and the FPC1022 driver' \
	  '  make unit-test   Run libfprint tests (requires a configured build)' \
	  '  make clean       Remove the local Meson build directory'

check: syntax smoke lint

syntax:
	bash -n install.sh uninstall.sh tests/smoke.sh
	sh -n configs/fpc1022-sleep-wake

smoke:
	bash tests/smoke.sh

lint:
	shellcheck --severity=error install.sh uninstall.sh tests/smoke.sh

configure:
	@if [[ -f "$(BUILD_DIR)/meson-private/coredata.dat" ]]; then \
	  meson setup --reconfigure "$(BUILD_DIR)" --prefix=/usr $(MESON_OPTIONS); \
	else \
	  meson setup "$(BUILD_DIR)" "$(LIBFPRINT_DIR)" --prefix=/usr $(MESON_OPTIONS); \
	fi

build: configure
	meson compile -C "$(BUILD_DIR)"

unit-test: build
	meson test -C "$(BUILD_DIR)" --print-errorlogs

clean:
	rm -rf -- "$(BUILD_DIR)"
