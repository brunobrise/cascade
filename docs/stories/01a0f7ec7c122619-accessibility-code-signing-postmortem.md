---
date: 2026-10-01
type: failure
status: resolved
related_specs:
  - ../specs/01a0f7ec7c122619-window-cascade-engine.md
---

# Accessibility Authorization and Code Signing Failure Postmortem

## 1. Context

Following the initial development of the Cascade menu bar app and CLI, the application ceased functioning ("bug: cascade not working anymore"). Hotkeys produced no action, menu items did not move windows, and the CLI returned zero windows.

## 2. Root Cause Analysis

Thorough investigation revealed three compounded failure modes:

1. **Duplicate Stale Process with Carbon HotKey Conflict:**
   - An early prototype binary (`CascadeBar`) was still running in the background while the newer bundle executable (`Cascade`) was launched.
   - When registering the global hotkey `⌥⌘C` via `RegisterEventHotKey`, Carbon returned `eventHotKeyExistsErr (-9878)`, preventing the active app from intercepting the shortcut.
   - The Makefile target `make stop` only targeted `pkill -x Cascade`, leaving rogue prototype processes running unnoticed.

2. **TCC Accessibility Revocation (`kAXErrorAPIDisabled -25211`):**
   - In macOS security architecture, Accessibility permissions granted under Transparency, Consent, and Control (TCC) are tied to cryptographic code signatures and bundle identifiers.
   - The binary was compiled without an explicit code signature (`Info.plist=not bound`, `adhoc,linker-signed`). Recompiling altered Mach-O hashes without a stable identity, leading macOS to invalidate previously granted trust.
   - `AXIsProcessTrusted()` returned `NO`, causing all subsequent Accessibility calls (`AXUIElementCopyAttributeValues`) to fail with error `-25211`.

3. **Silent Failure and Missing User Prompting:**
   - In the initial implementation, when `AXIsProcessTrusted()` failed, `performCascade:` silently exited without notifying the user or requesting permission.
   - Users were left with no visual feedback as to why clicking menu items or pressing shortcuts produced no visible effect.

## 3. Resolution and Architectural Changes

1. **Ad-Hoc Bundle Code Signing:**
   - Integrated `codesign --force --deep -s -` directly into the Makefile build and install targets for both `cascade` and `Cascade.app`. This binds the bundle identifier `com.brunobrise.cascade` stably into macOS security services.

2. **Self-Healing Accessibility Flow:**
   - Added `+ (BOOL)isAccessibilityTrustedWithPrompt:(BOOL)prompt` and `+ (void)openAccessibilitySettings` to `CascadeEngine`.
   - On launch and on cascade attempts, `Cascade.app` evaluates accessibility status. If untrusted, it opens an `NSAlert` modal offering direct navigation to System Settings (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`).
   - The status bar menu dynamically displays a `⚠️ Grant Accessibility Permission...` warning item whenever permission is revoked or missing.
   - `menuWillOpen:` monitors permission changes dynamically: once granted in System Settings, observers are immediately reattached via `[watcher refreshObservers]`.
   - The CLI outputs a high-visibility diagnostic banner detailing the exact steps to enable permissions.

3. **Process Hygiene:**
   - Updated Makefile `run` and `stop` targets to terminate both `Cascade` and `CascadeBar` cleanly using exact process matching (`pkill -x`).

## 4. Key Lessons

- Always seal macOS `.app` bundles with `codesign --force --deep -s -` even in local ad-hoc environments to maintain TCC permission continuity across rebuilds.
- Never fail silently on macOS Accessibility API calls; always check `AXIsProcessTrusted()` and guide users with direct deep-links to System Settings.
- Clean up process lifecycles and ensure Makefile management targets account for legacy or prototype executable names.
