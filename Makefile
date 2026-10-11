VERSION ?= $(shell python3 tools/semver.py current 2>/dev/null || cat VERSION 2>/dev/null || echo "0.17.0")
CC = clang
CFLAGS = -O2 -Wall -Wextra -fobjc-arc -DCASCADE_VERSION=\"$(VERSION)\"
LDFLAGS = -framework Cocoa -framework ApplicationServices -framework Carbon -framework ServiceManagement
BUILD_DIR = build
INSTALL_BIN = $(HOME)/.local/bin
INSTALL_APP = $(HOME)/Applications

# Persistent code signing identity detection (Cascade Code Signing or Apple Development)
SIGNING_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -E "Cascade Code Signing|Apple Development" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
ifeq ($(SIGNING_IDENTITY),)
    # Auto-provision local persistent certificate if missing
    _INIT_CERT := $(shell ./tools/setup_signing_cert.sh >/dev/null 2>&1)
    SIGNING_IDENTITY := $(shell security find-identity -v -p codesigning 2>/dev/null | grep -E "Cascade Code Signing|Apple Development" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
    ifeq ($(SIGNING_IDENTITY),)
        SIGNING_IDENTITY := -
    endif
endif

.PHONY: all build clean dist package test run run-cli apply watch stop restart status install uninstall login-enable login-disable login-status check-permissions open-permissions cert reset-permissions version hooks push-tags help

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
	@echo "  make version           Display current SemVer version"
	@echo "  make hooks             Install Lefthook git commit hooks"
	@echo "  make push-tags         Push all version tags to remote"
	@echo "  make stop              Terminate any running Cascade instance"
	@echo "  make restart           Stop and re-launch Cascade.app"
	@echo "  make status            Check whether Cascade.app is currently running"
	@echo "  make clean             Remove build artifacts"
	@echo ""

version:
	@echo $(VERSION)

hooks:
	@if command -v lefthook >/dev/null 2>&1; then \
		lefthook install; \
	else \
		mkdir -p .git/hooks; \
		printf '#!/bin/sh\nexec python3 tools/semver.py check-msg "$$1"\n' > .git/hooks/commit-msg; \
		chmod +x .git/hooks/commit-msg; \
		printf '#!/bin/sh\nexec python3 tools/semver.py post-commit\n' > .git/hooks/post-commit; \
		chmod +x .git/hooks/post-commit; \
		echo "Installed native zero-dependency git hooks into .git/hooks/"; \
	fi

push-tags:
	git push origin --tags

build: $(BUILD_DIR)/cascade $(BUILD_DIR)/Cascade.app

$(BUILD_DIR)/.dir:
	mkdir -p $(BUILD_DIR)
	@touch $@

# Objects
$(BUILD_DIR)/WindowEngine.o: src/WindowEngine.m src/WindowEngine.h | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) -c src/WindowEngine.m -o $@

$(BUILD_DIR)/ScreenManager.o: src/ScreenManager.m src/ScreenManager.h | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) -c src/ScreenManager.m -o $@

$(BUILD_DIR)/LoginItemManager.o: src/LoginItemManager.m src/LoginItemManager.h | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) -c src/LoginItemManager.m -o $@

$(BUILD_DIR)/WindowWatcher.o: src/WindowWatcher.m src/WindowWatcher.h | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) -c src/WindowWatcher.m -o $@

$(BUILD_DIR)/AppOrderWindowController.o: src/AppOrderWindowController.m src/AppOrderWindowController.h src/WindowEngine.h | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) -c src/AppOrderWindowController.m -o $@

$(BUILD_DIR)/IgnoreListWindowController.o: src/IgnoreListWindowController.m src/IgnoreListWindowController.h src/WindowEngine.h | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) -c src/IgnoreListWindowController.m -o $@

$(BUILD_DIR)/SettingsWindowController.o: src/SettingsWindowController.m src/SettingsWindowController.h src/WindowEngine.h src/ScreenManager.h src/LoginItemManager.h src/AppOrderWindowController.h src/IgnoreListWindowController.h src/UpdateChecker.h | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) -c src/SettingsWindowController.m -o $@

$(BUILD_DIR)/WindowLayoutGeometry.o: src/WindowLayoutGeometry.m src/WindowLayoutGeometry.h src/WindowEngine.h | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) -c src/WindowLayoutGeometry.m -o $@

$(BUILD_DIR)/UpdateChecker.o: src/UpdateChecker.m src/UpdateChecker.h | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) -c src/UpdateChecker.m -o $@

# CLI binary
$(BUILD_DIR)/cascade: src/main_cli.m $(BUILD_DIR)/WindowLayoutGeometry.o $(BUILD_DIR)/WindowEngine.o $(BUILD_DIR)/ScreenManager.o $(BUILD_DIR)/LoginItemManager.o $(BUILD_DIR)/WindowWatcher.o $(BUILD_DIR)/UpdateChecker.o $(wildcard VERSION) | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) src/main_cli.m $(BUILD_DIR)/WindowLayoutGeometry.o $(BUILD_DIR)/WindowEngine.o $(BUILD_DIR)/ScreenManager.o $(BUILD_DIR)/LoginItemManager.o $(BUILD_DIR)/WindowWatcher.o $(BUILD_DIR)/UpdateChecker.o -o $@
	codesign --force -s "$(SIGNING_IDENTITY)" $@

# Test binaries
$(BUILD_DIR)/test_engine: tests/test_engine.m $(BUILD_DIR)/WindowLayoutGeometry.o $(BUILD_DIR)/WindowEngine.o $(BUILD_DIR)/ScreenManager.o | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_engine.m $(BUILD_DIR)/WindowLayoutGeometry.o $(BUILD_DIR)/WindowEngine.o $(BUILD_DIR)/ScreenManager.o -o $@

$(BUILD_DIR)/test_quad_edge: tests/test_quad_edge.m $(BUILD_DIR)/WindowLayoutGeometry.o $(BUILD_DIR)/WindowEngine.o $(BUILD_DIR)/ScreenManager.o | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_quad_edge.m $(BUILD_DIR)/WindowLayoutGeometry.o $(BUILD_DIR)/WindowEngine.o $(BUILD_DIR)/ScreenManager.o -o $@

$(BUILD_DIR)/test_login: tests/test_login.m $(BUILD_DIR)/LoginItemManager.o | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_login.m $(BUILD_DIR)/LoginItemManager.o -o $@

$(BUILD_DIR)/test_watcher: tests/test_watcher.m $(BUILD_DIR)/WindowWatcher.o | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_watcher.m $(BUILD_DIR)/WindowWatcher.o -o $@

$(BUILD_DIR)/test_app_order: tests/test_app_order.m $(BUILD_DIR)/WindowLayoutGeometry.o $(BUILD_DIR)/AppOrderWindowController.o $(BUILD_DIR)/WindowEngine.o $(BUILD_DIR)/ScreenManager.o | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_app_order.m $(BUILD_DIR)/WindowLayoutGeometry.o $(BUILD_DIR)/AppOrderWindowController.o $(BUILD_DIR)/WindowEngine.o $(BUILD_DIR)/ScreenManager.o -o $@

$(BUILD_DIR)/test_screen_manager: tests/test_screen_manager.m $(BUILD_DIR)/WindowLayoutGeometry.o $(BUILD_DIR)/ScreenManager.o $(BUILD_DIR)/WindowEngine.o | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_screen_manager.m $(BUILD_DIR)/WindowLayoutGeometry.o $(BUILD_DIR)/ScreenManager.o $(BUILD_DIR)/WindowEngine.o -o $@

$(BUILD_DIR)/test_settings: tests/test_settings.m $(BUILD_DIR)/WindowLayoutGeometry.o $(BUILD_DIR)/SettingsWindowController.o $(BUILD_DIR)/AppOrderWindowController.o $(BUILD_DIR)/IgnoreListWindowController.o $(BUILD_DIR)/WindowEngine.o $(BUILD_DIR)/ScreenManager.o $(BUILD_DIR)/LoginItemManager.o $(BUILD_DIR)/UpdateChecker.o | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_settings.m $(BUILD_DIR)/WindowLayoutGeometry.o $(BUILD_DIR)/SettingsWindowController.o $(BUILD_DIR)/AppOrderWindowController.o $(BUILD_DIR)/IgnoreListWindowController.o $(BUILD_DIR)/WindowEngine.o $(BUILD_DIR)/ScreenManager.o $(BUILD_DIR)/LoginItemManager.o $(BUILD_DIR)/UpdateChecker.o -o $@

$(BUILD_DIR)/test_ignore: tests/test_ignore.m $(BUILD_DIR)/WindowLayoutGeometry.o $(BUILD_DIR)/IgnoreListWindowController.o $(BUILD_DIR)/SettingsWindowController.o $(BUILD_DIR)/AppOrderWindowController.o $(BUILD_DIR)/WindowEngine.o $(BUILD_DIR)/ScreenManager.o $(BUILD_DIR)/LoginItemManager.o $(BUILD_DIR)/WindowWatcher.o $(BUILD_DIR)/UpdateChecker.o | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_ignore.m $(BUILD_DIR)/WindowLayoutGeometry.o $(BUILD_DIR)/IgnoreListWindowController.o $(BUILD_DIR)/SettingsWindowController.o $(BUILD_DIR)/AppOrderWindowController.o $(BUILD_DIR)/WindowEngine.o $(BUILD_DIR)/ScreenManager.o $(BUILD_DIR)/LoginItemManager.o $(BUILD_DIR)/WindowWatcher.o $(BUILD_DIR)/UpdateChecker.o -o $@

$(BUILD_DIR)/test_icon_generator: tests/test_icon_generator.m resources/AppIcon.iconset | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_icon_generator.m -o $@

$(BUILD_DIR)/test_signing: tests/test_signing.m $(BUILD_DIR)/Cascade.app | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_signing.m -o $@

$(BUILD_DIR)/test_update_checker: tests/test_update_checker.m $(BUILD_DIR)/UpdateChecker.o | $(BUILD_DIR)/.dir
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_update_checker.m $(BUILD_DIR)/UpdateChecker.o -o $@

test: build icon $(BUILD_DIR)/test_engine $(BUILD_DIR)/test_quad_edge $(BUILD_DIR)/test_login $(BUILD_DIR)/test_watcher $(BUILD_DIR)/test_app_order $(BUILD_DIR)/test_screen_manager $(BUILD_DIR)/test_settings $(BUILD_DIR)/test_ignore $(BUILD_DIR)/test_icon_generator $(BUILD_DIR)/test_signing $(BUILD_DIR)/test_update_checker
	./$(BUILD_DIR)/test_engine
	./$(BUILD_DIR)/test_quad_edge
	./$(BUILD_DIR)/test_login
	./$(BUILD_DIR)/test_watcher
	./$(BUILD_DIR)/test_app_order
	./$(BUILD_DIR)/test_screen_manager
	./$(BUILD_DIR)/test_settings
	./$(BUILD_DIR)/test_ignore
	./$(BUILD_DIR)/test_icon_generator
	./$(BUILD_DIR)/test_signing
	./$(BUILD_DIR)/test_update_checker
	python3 tests/test_semver.py

# App Icon
resources/AppIcon.iconset: tools/generate_icon.m
	@mkdir -p resources
	$(CC) -O2 -Wall -Wextra -fobjc-arc -framework Cocoa tools/generate_icon.m -o tools/generate_icon
	./tools/generate_icon resources/AppIcon.iconset

resources/AppIcon.icns: resources/AppIcon.iconset
	iconutil -c icns resources/AppIcon.iconset -o $@

icon: resources/AppIcon.iconset resources/AppIcon.icns

# Code Signing Certificate Helper
cert:
	@./tools/setup_signing_cert.sh

reset-permissions:
	tccutil reset Accessibility com.brunobrise.cascade
	@echo "Reset Accessibility permissions for com.brunobrise.cascade in TCC database."

# Status Bar App Bundle
$(BUILD_DIR)/Cascade.app: src/main_bar.m $(BUILD_DIR)/WindowLayoutGeometry.o $(BUILD_DIR)/WindowEngine.o $(BUILD_DIR)/ScreenManager.o $(BUILD_DIR)/LoginItemManager.o $(BUILD_DIR)/WindowWatcher.o $(BUILD_DIR)/AppOrderWindowController.o $(BUILD_DIR)/IgnoreListWindowController.o $(BUILD_DIR)/SettingsWindowController.o $(BUILD_DIR)/UpdateChecker.o resources/Info.plist resources/AppIcon.icns $(wildcard VERSION) | $(BUILD_DIR)/.dir
	mkdir -p $(BUILD_DIR)/Cascade.app/Contents/MacOS
	mkdir -p $(BUILD_DIR)/Cascade.app/Contents/Resources
	$(CC) $(CFLAGS) $(LDFLAGS) src/main_bar.m $(BUILD_DIR)/WindowLayoutGeometry.o $(BUILD_DIR)/WindowEngine.o $(BUILD_DIR)/ScreenManager.o $(BUILD_DIR)/LoginItemManager.o $(BUILD_DIR)/WindowWatcher.o $(BUILD_DIR)/AppOrderWindowController.o $(BUILD_DIR)/IgnoreListWindowController.o $(BUILD_DIR)/SettingsWindowController.o $(BUILD_DIR)/UpdateChecker.o -o $(BUILD_DIR)/Cascade.app/Contents/MacOS/Cascade
	cp resources/Info.plist $(BUILD_DIR)/Cascade.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" $(BUILD_DIR)/Cascade.app/Contents/Info.plist 2>/dev/null || true
	cp resources/AppIcon.icns $(BUILD_DIR)/Cascade.app/Contents/Resources/AppIcon.icns
	codesign --force --deep -s "$(SIGNING_IDENTITY)" $@

install: build
	mkdir -p $(INSTALL_BIN)
	cp $(BUILD_DIR)/cascade $(INSTALL_BIN)/cascade
	codesign --force -s "$(SIGNING_IDENTITY)" $(INSTALL_BIN)/cascade
	xattr -cr $(INSTALL_BIN)/cascade 2>/dev/null || true
	@pkill -x Cascade 2>/dev/null || true
	@pkill -f "Cascade.app/Contents/MacOS/Cascade" 2>/dev/null || true
	@sleep 0.2
	@if [ -w /Applications ]; then \
		echo "Installing to canonical system directory /Applications/Cascade.app..."; \
		rm -rf $(INSTALL_APP)/Cascade.app 2>/dev/null || true; \
		rm -rf /Applications/Cascade.app; \
		cp -R $(BUILD_DIR)/Cascade.app /Applications/Cascade.app; \
		codesign --force --deep -s "$(SIGNING_IDENTITY)" /Applications/Cascade.app; \
		xattr -cr /Applications/Cascade.app 2>/dev/null || true; \
		touch /Applications/Cascade.app; \
		/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -r /Applications/Cascade.app 2>/dev/null || true; \
		echo "Installed Cascade.app to /Applications/Cascade.app"; \
		echo "Installed cascade to $(INSTALL_BIN)/cascade"; \
		echo "Signed with identity: $(SIGNING_IDENTITY)"; \
		open /Applications/Cascade.app; \
	else \
		echo "Installing to user directory $(INSTALL_APP)/Cascade.app..."; \
		rm -rf /Applications/Cascade.app 2>/dev/null || true; \
		mkdir -p $(INSTALL_APP); \
		rm -rf $(INSTALL_APP)/Cascade.app; \
		cp -R $(BUILD_DIR)/Cascade.app $(INSTALL_APP)/Cascade.app; \
		codesign --force --deep -s "$(SIGNING_IDENTITY)" $(INSTALL_APP)/Cascade.app; \
		xattr -cr $(INSTALL_APP)/Cascade.app 2>/dev/null || true; \
		touch $(INSTALL_APP)/Cascade.app; \
		/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -r $(INSTALL_APP)/Cascade.app 2>/dev/null || true; \
		echo "Installed Cascade.app to $(INSTALL_APP)/Cascade.app"; \
		echo "Installed cascade to $(INSTALL_BIN)/cascade"; \
		echo "Signed with identity: $(SIGNING_IDENTITY)"; \
		open $(INSTALL_APP)/Cascade.app; \
	fi

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
	@pkill -f "Cascade.app/Contents/MacOS/Cascade" 2>/dev/null || true
	@sleep 0.2
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
	@pkill -f "Cascade.app/Contents/MacOS/Cascade" 2>/dev/null || true
	@sleep 0.2
	@echo "Cascade stopped."

restart: stop run

status:
	@pgrep -x Cascade >/dev/null && echo "Cascade is running." || echo "Cascade is not running."

dist: icon
	@./tools/package.sh $(VERSION)

package: dist

clean:
	rm -rf $(BUILD_DIR) tools/generate_icon
