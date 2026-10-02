CC = clang
CFLAGS = -O2 -Wall -Wextra -fobjc-arc
LDFLAGS = -framework Cocoa -framework ApplicationServices -framework Carbon -framework ServiceManagement
BUILD_DIR = build
INSTALL_BIN = $(HOME)/.local/bin
INSTALL_APP = $(HOME)/Applications

.PHONY: all build clean test run run-cli apply watch stop restart status install uninstall login-enable login-disable login-status check-permissions open-permissions help

all: build

help:
	@echo "Cascade - Window Management Build System"
	@echo ""
	@echo "Available commands:"
	@echo "  make build             Build CLI binary and Status Bar application bundle"
	@echo "  make icon              Generate multi-resolution macOS AppIcon.icns"
	@echo "  make test              Compile and run all test suites"
	@echo "  make install           Install CLI to $(INSTALL_BIN) and App to $(INSTALL_APP)"
	@echo "  make uninstall         Remove installed binaries and app bundle"
	@echo "  make run               Launch the Status Bar app (Cascade.app)"
	@echo "  make run-cli           Run the CLI in preview mode (--plan)"
	@echo "  make apply             Run the CLI to cascade windows immediately (--apply)"
	@echo "  make watch             Run the CLI in continuous watcher mode (--watch)"
	@echo "  make check-permissions Check macOS Accessibility permissions and diagnostic probe"
	@echo "  make open-permissions  Open macOS Accessibility settings pane"
	@echo "  make login-enable      Register Cascade to start automatically at login"
	@echo "  make login-disable     Unregister Cascade from starting at login"
	@echo "  make login-status      Check start-at-login status"
	@echo "  make stop              Terminate any running Cascade instance"
	@echo "  make restart           Stop and re-launch Cascade.app"
	@echo "  make status            Check whether Cascade.app is currently running"
	@echo "  make clean             Remove build artifacts"
	@echo ""

build: $(BUILD_DIR)/cascade $(BUILD_DIR)/Cascade.app

$(BUILD_DIR)/.dir:
	mkdir -p $(BUILD_DIR)
	@touch $@

# Objects
$(BUILD_DIR)/WindowEngine.o: src/WindowEngine.m src/WindowEngine.h | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) -c src/WindowEngine.m -o $@

$(BUILD_DIR)/LoginItemManager.o: src/LoginItemManager.m src/LoginItemManager.h | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) -c src/LoginItemManager.m -o $@

$(BUILD_DIR)/WindowWatcher.o: src/WindowWatcher.m src/WindowWatcher.h | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) -c src/WindowWatcher.m -o $@

$(BUILD_DIR)/AppOrderWindowController.o: src/AppOrderWindowController.m src/AppOrderWindowController.h src/WindowEngine.h | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) -c src/AppOrderWindowController.m -o $@

# CLI binary
$(BUILD_DIR)/cascade: src/main_cli.m $(BUILD_DIR)/WindowEngine.o $(BUILD_DIR)/LoginItemManager.o $(BUILD_DIR)/WindowWatcher.o | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) src/main_cli.m $(BUILD_DIR)/WindowEngine.o $(BUILD_DIR)/LoginItemManager.o $(BUILD_DIR)/WindowWatcher.o -o $@
	codesign --force -s - $@

# Test binaries
$(BUILD_DIR)/test_engine: tests/test_engine.m $(BUILD_DIR)/WindowEngine.o | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_engine.m $(BUILD_DIR)/WindowEngine.o -o $@

$(BUILD_DIR)/test_login: tests/test_login.m $(BUILD_DIR)/LoginItemManager.o | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_login.m $(BUILD_DIR)/LoginItemManager.o -o $@

$(BUILD_DIR)/test_watcher: tests/test_watcher.m $(BUILD_DIR)/WindowWatcher.o | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_watcher.m $(BUILD_DIR)/WindowWatcher.o -o $@

$(BUILD_DIR)/test_app_order: tests/test_app_order.m $(BUILD_DIR)/AppOrderWindowController.o $(BUILD_DIR)/WindowEngine.o | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_app_order.m $(BUILD_DIR)/AppOrderWindowController.o $(BUILD_DIR)/WindowEngine.o -o $@

test: $(BUILD_DIR)/test_engine $(BUILD_DIR)/test_login $(BUILD_DIR)/test_watcher $(BUILD_DIR)/test_app_order
	./$(BUILD_DIR)/test_engine
	./$(BUILD_DIR)/test_login
	./$(BUILD_DIR)/test_watcher
	./$(BUILD_DIR)/test_app_order

# App Icon
resources/AppIcon.icns: tools/generate_icon.m
	$(CC) -O2 -Wall -Wextra -fobjc-arc -framework Cocoa tools/generate_icon.m -o tools/generate_icon
	./tools/generate_icon resources/AppIcon.iconset
	iconutil -c icns resources/AppIcon.iconset -o $@

icon: resources/AppIcon.icns

# Status Bar App Bundle
$(BUILD_DIR)/Cascade.app: src/main_bar.m $(BUILD_DIR)/WindowEngine.o $(BUILD_DIR)/LoginItemManager.o $(BUILD_DIR)/WindowWatcher.o $(BUILD_DIR)/AppOrderWindowController.o resources/Info.plist resources/AppIcon.icns | $(BUILD_DIR)/.dir
	mkdir -p $(BUILD_DIR)/Cascade.app/Contents/MacOS
	mkdir -p $(BUILD_DIR)/Cascade.app/Contents/Resources
	$(CC) $(CFLAGS) $(LDFLAGS) src/main_bar.m $(BUILD_DIR)/WindowEngine.o $(BUILD_DIR)/LoginItemManager.o $(BUILD_DIR)/WindowWatcher.o $(BUILD_DIR)/AppOrderWindowController.o -o $(BUILD_DIR)/Cascade.app/Contents/MacOS/Cascade
	cp resources/Info.plist $(BUILD_DIR)/Cascade.app/Contents/Info.plist
	cp resources/AppIcon.icns $(BUILD_DIR)/Cascade.app/Contents/Resources/AppIcon.icns
	codesign --force --deep -s - $@

install: build
	mkdir -p $(INSTALL_BIN)
	cp $(BUILD_DIR)/cascade $(INSTALL_BIN)/cascade
	mkdir -p $(INSTALL_APP)
	rm -rf $(INSTALL_APP)/Cascade.app
	cp -R $(BUILD_DIR)/Cascade.app $(INSTALL_APP)/Cascade.app
	codesign --force --deep -s - $(INSTALL_APP)/Cascade.app
	@echo "Installed cascade to $(INSTALL_BIN)/cascade"
	@echo "Installed Cascade.app to $(INSTALL_APP)/Cascade.app"

uninstall:
	rm -f $(INSTALL_BIN)/cascade
	rm -rf $(INSTALL_APP)/Cascade.app
	@echo "Uninstalled cascade and Cascade.app"

login-enable: $(BUILD_DIR)/cascade
	./$(BUILD_DIR)/cascade --start-at-login enable

login-disable: $(BUILD_DIR)/cascade
	./$(BUILD_DIR)/cascade --start-at-login disable

login-status: $(BUILD_DIR)/cascade
	./$(BUILD_DIR)/cascade --start-at-login status

run: build
	@pkill -x Cascade 2>/dev/null || true
	@pkill -x CascadeBar 2>/dev/null || true
	open $(BUILD_DIR)/Cascade.app
	@echo "Cascade.app launched in status bar."

run-cli: $(BUILD_DIR)/cascade
	./$(BUILD_DIR)/cascade --plan

apply: $(BUILD_DIR)/cascade
	./$(BUILD_DIR)/cascade --apply

watch: $(BUILD_DIR)/cascade
	./$(BUILD_DIR)/cascade --watch

check-permissions: $(BUILD_DIR)/cascade
	@./$(BUILD_DIR)/cascade --check-permissions || true

open-permissions: $(BUILD_DIR)/cascade
	./$(BUILD_DIR)/cascade --open-permissions

stop:
	@pkill -x Cascade 2>/dev/null || true
	@pkill -x CascadeBar 2>/dev/null || true
	@echo "Cascade stopped."

restart: stop run

status:
	@pgrep -x Cascade >/dev/null && echo "Cascade is running." || echo "Cascade is not running."

clean:
	rm -rf $(BUILD_DIR) tools/generate_icon
