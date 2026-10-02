CC = clang
CFLAGS = -O2 -Wall -Wextra -fobjc-arc
LDFLAGS = -framework Cocoa -framework ApplicationServices -framework Carbon -framework ServiceManagement
BUILD_DIR = build
INSTALL_BIN = $(HOME)/.local/bin
INSTALL_APP = $(HOME)/Applications

# Persistent code signing identity detection (Cascade Code Signing or Apple Development)
SIGNING_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -E "Cascade Code Signing|Apple Development" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
ifeq ($(SIGNING_IDENTITY),)
    SIGNING_IDENTITY := -
endif

.PHONY: all build clean test run run-cli apply watch stop restart status install uninstall login-enable login-disable login-status check-permissions open-permissions cert reset-permissions help

all: build

help:
	@echo "Cascade - Window Management Build System"
	@echo ""
	@echo "Available commands:"
	@echo "  make build             Build CLI binary and Status Bar application bundle"
	@echo "  make icon              Generate multi-resolution macOS AppIcon.icns"
	@echo "  make cert              Setup local persistent code-signing certificate (preserves TCC)"
	@echo "  make reset-permissions Reset macOS Accessibility TCC record for Cascade"
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
	codesign --force -s "$(SIGNING_IDENTITY)" $@

# Test binaries
$(BUILD_DIR)/test_engine: tests/test_engine.m $(BUILD_DIR)/WindowEngine.o | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_engine.m $(BUILD_DIR)/WindowEngine.o -o $@

$(BUILD_DIR)/test_login: tests/test_login.m $(BUILD_DIR)/LoginItemManager.o | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_login.m $(BUILD_DIR)/LoginItemManager.o -o $@

$(BUILD_DIR)/test_watcher: tests/test_watcher.m $(BUILD_DIR)/WindowWatcher.o | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_watcher.m $(BUILD_DIR)/WindowWatcher.o -o $@

$(BUILD_DIR)/test_app_order: tests/test_app_order.m $(BUILD_DIR)/AppOrderWindowController.o $(BUILD_DIR)/WindowEngine.o | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_app_order.m $(BUILD_DIR)/AppOrderWindowController.o $(BUILD_DIR)/WindowEngine.o -o $@

$(BUILD_DIR)/test_icon_generator: tests/test_icon_generator.m | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_icon_generator.m -o $@

$(BUILD_DIR)/test_signing: tests/test_signing.m | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_signing.m -o $@

test: $(BUILD_DIR)/test_engine $(BUILD_DIR)/test_login $(BUILD_DIR)/test_watcher $(BUILD_DIR)/test_app_order $(BUILD_DIR)/test_icon_generator $(BUILD_DIR)/test_signing
	./$(BUILD_DIR)/test_engine
	./$(BUILD_DIR)/test_login
	./$(BUILD_DIR)/test_watcher
	./$(BUILD_DIR)/test_app_order
	./$(BUILD_DIR)/test_icon_generator
	./$(BUILD_DIR)/test_signing

# App Icon
resources/AppIcon.icns: tools/generate_icon.m
	$(CC) -O2 -Wall -Wextra -fobjc-arc -framework Cocoa tools/generate_icon.m -o tools/generate_icon
	./tools/generate_icon resources/AppIcon.iconset
	iconutil -c icns resources/AppIcon.iconset -o $@

icon: resources/AppIcon.icns

# Code Signing Certificate Helper
cert:
	@./tools/setup_signing_cert.sh

reset-permissions:
	tccutil reset Accessibility com.brunobrise.cascade
	@echo "Reset Accessibility permissions for com.brunobrise.cascade in TCC database."

# Status Bar App Bundle
$(BUILD_DIR)/Cascade.app: src/main_bar.m $(BUILD_DIR)/WindowEngine.o $(BUILD_DIR)/LoginItemManager.o $(BUILD_DIR)/WindowWatcher.o $(BUILD_DIR)/AppOrderWindowController.o resources/Info.plist resources/AppIcon.icns | $(BUILD_DIR)/.dir
	mkdir -p $(BUILD_DIR)/Cascade.app/Contents/MacOS
	mkdir -p $(BUILD_DIR)/Cascade.app/Contents/Resources
	$(CC) $(CFLAGS) $(LDFLAGS) src/main_bar.m $(BUILD_DIR)/WindowEngine.o $(BUILD_DIR)/LoginItemManager.o $(BUILD_DIR)/WindowWatcher.o $(BUILD_DIR)/AppOrderWindowController.o -o $(BUILD_DIR)/Cascade.app/Contents/MacOS/Cascade
	cp resources/Info.plist $(BUILD_DIR)/Cascade.app/Contents/Info.plist
	cp resources/AppIcon.icns $(BUILD_DIR)/Cascade.app/Contents/Resources/AppIcon.icns
	codesign --force --deep -s "$(SIGNING_IDENTITY)" $@

install: build
	mkdir -p $(INSTALL_BIN)
	cp $(BUILD_DIR)/cascade $(INSTALL_BIN)/cascade
	codesign --force -s "$(SIGNING_IDENTITY)" $(INSTALL_BIN)/cascade
	mkdir -p $(INSTALL_APP)
	rm -rf $(INSTALL_APP)/Cascade.app
	cp -R $(BUILD_DIR)/Cascade.app $(INSTALL_APP)/Cascade.app
	codesign --force --deep -s "$(SIGNING_IDENTITY)" $(INSTALL_APP)/Cascade.app
	touch $(INSTALL_APP)/Cascade.app
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -r $(INSTALL_APP)/Cascade.app 2>/dev/null || true
	@echo "Installed cascade to $(INSTALL_BIN)/cascade"
	@echo "Installed Cascade.app to $(INSTALL_APP)/Cascade.app"
	@echo "Signed with identity: $(SIGNING_IDENTITY)"

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
