CC = clang
CFLAGS = -O2 -Wall -Wextra -fobjc-arc
LDFLAGS = -framework Cocoa -framework ApplicationServices -framework Carbon
BUILD_DIR = build
INSTALL_BIN = $(HOME)/.local/bin
INSTALL_APP = $(HOME)/Applications

.PHONY: all build clean test run run-cli apply stop restart status install uninstall help

all: build

help:
	@echo "Cascade - Window Management Build System"
	@echo ""
	@echo "Available commands:"
	@echo "  make build       Build CLI binary and Status Bar application bundle"
	@echo "  make test        Compile and run the test suite"
	@echo "  make install     Install CLI to $(INSTALL_BIN) and App to $(INSTALL_APP)"
	@echo "  make uninstall   Remove installed binaries and app bundle"
	@echo "  make run         Launch the Status Bar app (Cascade.app)"
	@echo "  make run-cli     Run the CLI in preview mode (--plan)"
	@echo "  make apply       Run the CLI to cascade windows immediately (--apply)"
	@echo "  make stop        Terminate any running Cascade instance"
	@echo "  make restart     Stop and re-launch Cascade.app"
	@echo "  make status      Check whether Cascade.app is currently running"
	@echo "  make clean       Remove build artifacts"
	@echo ""

build: $(BUILD_DIR)/cascade $(BUILD_DIR)/Cascade.app

$(BUILD_DIR)/.dir:
	mkdir -p $(BUILD_DIR)
	@touch $@

# Core engine object
$(BUILD_DIR)/WindowEngine.o: src/WindowEngine.m src/WindowEngine.h | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) -c src/WindowEngine.m -o $@

# CLI binary
$(BUILD_DIR)/cascade: src/main_cli.m $(BUILD_DIR)/WindowEngine.o | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) src/main_cli.m $(BUILD_DIR)/WindowEngine.o -o $@

# Test binary
$(BUILD_DIR)/test_engine: tests/test_engine.m $(BUILD_DIR)/WindowEngine.o | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_engine.m $(BUILD_DIR)/WindowEngine.o -o $@

test: $(BUILD_DIR)/test_engine
	./$(BUILD_DIR)/test_engine

# Status Bar App Bundle
$(BUILD_DIR)/Cascade.app: src/main_bar.m $(BUILD_DIR)/WindowEngine.o resources/Info.plist | $(BUILD_DIR)/.dir
	mkdir -p $(BUILD_DIR)/Cascade.app/Contents/MacOS
	mkdir -p $(BUILD_DIR)/Cascade.app/Contents/Resources
	$(CC) $(CFLAGS) $(LDFLAGS) src/main_bar.m $(BUILD_DIR)/WindowEngine.o -o $(BUILD_DIR)/Cascade.app/Contents/MacOS/Cascade
	cp resources/Info.plist $(BUILD_DIR)/Cascade.app/Contents/Info.plist

install: build
	mkdir -p $(INSTALL_BIN)
	cp $(BUILD_DIR)/cascade $(INSTALL_BIN)/cascade
	mkdir -p $(INSTALL_APP)
	rm -rf $(INSTALL_APP)/Cascade.app
	cp -R $(BUILD_DIR)/Cascade.app $(INSTALL_APP)/Cascade.app
	@echo "Installed cascade to $(INSTALL_BIN)/cascade"
	@echo "Installed Cascade.app to $(INSTALL_APP)/Cascade.app"

uninstall:
	rm -f $(INSTALL_BIN)/cascade
	rm -rf $(INSTALL_APP)/Cascade.app
	@echo "Uninstalled cascade and Cascade.app"

run: build
	@pkill -x Cascade 2>/dev/null || true
	open $(BUILD_DIR)/Cascade.app
	@echo "Cascade.app launched in status bar."

run-cli: $(BUILD_DIR)/cascade
	./$(BUILD_DIR)/cascade --plan

apply: $(BUILD_DIR)/cascade
	./$(BUILD_DIR)/cascade --apply

stop:
	@pkill -x Cascade 2>/dev/null && echo "Cascade stopped." || echo "Cascade was not running."

restart: stop run

status:
	@pgrep -x Cascade >/dev/null && echo "Cascade is running." || echo "Cascade is not running."

clean:
	rm -rf $(BUILD_DIR)
