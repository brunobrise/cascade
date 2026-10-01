CC = clang
CFLAGS = -O2 -Wall -Wextra -fobjc-arc
LDFLAGS = -framework Cocoa -framework ApplicationServices -framework Carbon
BUILD_DIR = build

.PHONY: all clean test run install

all: $(BUILD_DIR)/cascade $(BUILD_DIR)/Cascade.app

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Core engine object
$(BUILD_DIR)/WindowEngine.o: src/WindowEngine.m src/WindowEngine.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c src/WindowEngine.m -o $@

# CLI binary
$(BUILD_DIR)/cascade: src/main_cli.m $(BUILD_DIR)/WindowEngine.o | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) src/main_cli.m $(BUILD_DIR)/WindowEngine.o -o $@

# Test binary
$(BUILD_DIR)/test_engine: tests/test_engine.m $(BUILD_DIR)/WindowEngine.o | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) tests/test_engine.m $(BUILD_DIR)/WindowEngine.o -o $@

test: $(BUILD_DIR)/test_engine
	./$(BUILD_DIR)/test_engine

# Status Bar App Bundle
$(BUILD_DIR)/Cascade.app: src/main_bar.m $(BUILD_DIR)/WindowEngine.o resources/Info.plist | $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)/Cascade.app/Contents/MacOS
	mkdir -p $(BUILD_DIR)/Cascade.app/Contents/Resources
	$(CC) $(CFLAGS) $(LDFLAGS) src/main_bar.m $(BUILD_DIR)/WindowEngine.o -o $(BUILD_DIR)/Cascade.app/Contents/MacOS/Cascade
	cp resources/Info.plist $(BUILD_DIR)/Cascade.app/Contents/Info.plist

install: $(BUILD_DIR)/cascade $(BUILD_DIR)/Cascade.app
	mkdir -p $(HOME)/.local/bin
	cp $(BUILD_DIR)/cascade $(HOME)/.local/bin/cascade
	mkdir -p $(HOME)/Applications
	rm -rf $(HOME)/Applications/Cascade.app
	cp -R $(BUILD_DIR)/Cascade.app $(HOME)/Applications/Cascade.app

clean:
	rm -rf $(BUILD_DIR)
