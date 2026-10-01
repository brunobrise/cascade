---
date: 2026-10-01
type: success
status: validated
related_specs:
  - ../specs/01a0f7ec7c122619-window-cascade-engine.md
---

# Resilient Accessibility Permissions Checking and Self-Healing Success Story

## 1. Context

Window management on macOS requires Accessibility permissions under Transparency, Consent, and Control (TCC) to query and reposition windows via the Accessibility API (`AXUIElementCopyAttributeValue`, `AXUIElementSetAttributeValue`).

Previously, accessibility permissions checking suffered from critical failure modes:
1. **TCC Cache Latency and False Positives:** Relying solely on `AXIsProcessTrusted()` can return stale results. Specifically, when binaries are recompiled or code-signed with ad-hoc certificates, `AXIsProcessTrusted()` may report `true` based on bundle identifier cache, while active AX API calls immediately fail with `kAXErrorAPIDisabled` (-25211). Conversely, after granting permissions in System Settings, `AXIsProcessTrusted()` can lag until process relaunch.
2. **Brittle Settings URL Schemes:** macOS 13+ (Ventura, Sonoma, Sequoia) deprecated the legacy `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` pane scheme in favor of extension URLs (`x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility`), causing settings openers to silently fail on newer OS versions.
3. **Status Bar Menu Deadlock:** When `Cascade.app` was launched without permissions, it presented a disabled alert once and remained unfunctional even after the user enabled permissions in System Settings. Users were forced to manually kill and restart the app.
4. **Host Terminal Attribution Confusion in CLI:** In macOS, command-line executables executed inside terminal emulators (Terminal.app, iTerm2, Alacritty, VSCode, Cursor) inherit the accessibility trust context of the **host parent application**. CLI users were often confused about whether to grant permissions to the binary `cascade` or their terminal emulator.

## 2. Intended Outcome

1. **Two-Layer Resilient Verification:** Combine the static TCC check with an active live functional probe (`AXUIElementCreateSystemWide()` + `kAXFocusedApplicationAttribute`) to confirm genuine API operability and detect `kAXErrorAPIDisabled` (-25211).
2. **Self-Healing Menu Bar Application:** Enable `Cascade.app` to automatically detect permission grants in the background (via application switch notifications and a lightweight 2.0s heartbeat timer), seamlessly initializing window observers and clearing alert prompts without requiring an app restart.
3. **Multi-Path System Settings Navigation:** Provide a robust multi-URL fallback hierarchy ensuring the Accessibility settings pane opens reliably across macOS 11 through macOS 15+.
4. **Actionable CLI Diagnostics:** Introduce `--check-permissions` and `--open-permissions` commands that explicitly identify the host terminal application, probe status, and specific corrective steps.

## 3. What Worked and Why

1. **Active Functional Probe in `CascadeEngine`:**
   - Implemented `+ (NSDictionary<NSString *, id> *)accessibilityDiagnostics` and enhanced `isAccessibilityTrustedWithPrompt:`.
   - The engine checks `AXIsProcessTrustedWithOptions()`, followed immediately by a live query on `AXUIElementCreateSystemWide()`.
   - Distinguishes between `kAXErrorAPIDisabled` (-25211), `kAXErrorSuccess` (0), and `kAXErrorNoValue` (-25204). Even if `kAXErrorNoValue` occurs (e.g. no application is focused), the API is confirmed operational rather than disabled.
2. **Multi-Scheme Settings Opener:**
   - Implemented `+ (void)openAccessibilitySettings` which attempts:
     - `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility` (modern macOS 13+)
     - `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` (macOS 11-12)
     - `NSWorkspace openURL:` with file path `/System/Applications/System Settings.app` as direct fallback.
3. **Self-Healing Background Heartbeat in `Cascade.app`:**
   - In `src/main_bar.m`, observed `NSWorkspaceDidActivateApplicationNotification` and established a 2.0s interval timer (`checkPermissionsChange`).
   - When the user returns from System Settings having enabled Accessibility, `Cascade.app` detects the transition from untrusted to trusted, starts the `WindowWatcher` (if auto-rearrange is configured), and invalidates the heartbeat timer to eliminate idle CPU overhead.
   - Updated `performCascade:` to attempt an immediate re-probe before popping modal alerts, handling race conditions when permissions are granted mid-session.
4. **Host Application Detection in CLI:**
   - In `src/main_cli.m`, detected the frontmost or parent application name (`[[[NSWorkspace sharedWorkspace] frontmostApplication] localizedName]`).
   - When permissions are missing, CLI prints clear instructions identifying the exact host application to enable.

## 4. Empirical Evidence

- **Unit Test Suite (`tests/test_engine.m`):**
  - Added `testAccessibilityDiagnostics()` verifying that `accessibilityDiagnostics` returns valid values for `trusted`, `probeFunctional`, `probeError`, and `hostApp`.
  - All test suites (`test_engine`, `test_login`, `test_watcher`) pass with 100% success rate.
- **CLI Diagnostics Execution:**
  - Ran `cascade --check-permissions` in testing environment: accurately identified `Host Application: Antigravity`, detected probe error `-25204` (functional API), and returned actionable remediation output.
  - Ran `make check-permissions` verifying target integration.
- **Line Count Discipline:**
  - `src/WindowEngine.h`: 55 LOC
  - `src/WindowEngine.m`: 407 LOC (refactored to remain under 420 limit)
  - `src/main_bar.m`: 389 LOC (under 420 limit)
  - `src/main_cli.m`: 323 LOC (under 420 limit)
  - `tests/test_engine.m`: 311 LOC (under 420 limit)

## 5. Reusable Engineering Pattern

When interacting with macOS TCC-controlled subsystems (Accessibility, Screen Recording, Automation), never rely solely on boolean trust flags (`AXIsProcessTrusted()`). Always implement:
1. **A live functional probe** to detect API-disabled states (-25211) caused by TCC cache staleness or signature mismatches.
2. **Context-aware host identification** for CLI tools to prevent user confusion regarding which binary requires authorization.
3. **A self-healing event/heartbeat listener** in persistent GUI processes to recover seamlessly the instant permissions are granted, avoiding forced user restarts.
