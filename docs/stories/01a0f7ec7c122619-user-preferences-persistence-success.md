---
date: 2026-10-01
type: success
status: validated
related_specs:
  - ../specs/01a0f7ec7c122619-window-cascade-engine.md
---

# User Preferences Persistence Across App and CLI Success Story

## 1. Context

Cascade is delivered both as a macOS menu bar application (`Cascade.app`) and as a scriptable terminal command-line tool (`cascade`). Users customize multiple layout preferences:
- Window order mode (MRU, Spatial, Alphabetical, Preferred App Order).
- Tab size margin (`delta`: 30px, 40px, 50px, 60px).
- Stacking behavior (`restackZOrder`: whether to re-raise windows to match spatial cascade order).
- Lifecycle watcher (`autoRearrange`: whether to continuously monitor and adjust window sizes on open/minimize/close).
- Application priority list (`preferredAppOrder`: prioritized app names).

Previously, user preferences suffered from two critical shortcomings:
1. **Missing Setters:** `delta` and `restackZOrder` modifications in the menu bar were stored only in transient in-memory properties and were never saved to disk, resetting to defaults on every restart.
2. **Domain Isolation:** Because the CLI binary is an unbundled Unix executable, `[NSUserDefaults standardUserDefaults]` defaulted to the process-name domain (`cascade`), while the packaged menu bar application wrote to its bundle identifier domain (`com.brunobrise.cascade`). Changes made via CLI commands did not affect `Cascade.app`, and vice versa.

## 2. Intended Outcome

1. **Complete Preference Persistence:** All five configuration options (`orderMode`, `delta`, `restackZOrder`, `autoRearrange`, `preferredAppOrder`) must persist reliably across application restarts and system reboots.
2. **Unified Shared Domain:** Both `Cascade.app` and the `cascade` CLI tool must read and write to the same shared suite domain (`com.brunobrise.cascade`), ensuring immediate synchronization between GUI and terminal workflows.
3. **Scriptable CLI Preference Control:** Provide full inspection and modification via CLI (`--get-preferences`, `--set-order`, `--set-delta`, `--set-restack`, `--set-auto-rearrange`, `--set-app-order`).
4. **Immediate Disk Synchronization:** Configuration changes must synchronize directly to disk (`[defaults synchronize]`) to guard against process termination or system sleep.

## 3. What Worked and Why

1. **Centralized Preference Accessors in `CascadeEngine`:**
   - Abstracted persistence into `userDefaults`, `getPref`, and `setPref` static helpers.
   - `userDefaults` loads `[[NSUserDefaults alloc] initWithSuiteName:@"com.brunobrise.cascade"]`, falling back to `[NSUserDefaults standardUserDefaults]` if unavailable.
   - `setPref` writes to both the shared suite domain and standard defaults with immediate `synchronize` calls, guaranteeing complete interoperability across GUI and CLI runtimes.
2. **Status Bar Menu Synchronization:**
   - Refactored `src/main_bar.m` order mode setters (`setOrderMRU:`, `setOrderSpatial:`, `setOrderAlpha:`, `setOrderCustom:`) through a consolidated `setOrderModeValue:` helper.
   - Updated `setDeltaValue:`, `toggleRestack:`, and `toggleAutoRearrange:` to persist selections immediately upon user interaction.
   - Restored all saved preferences on `applicationDidFinishLaunching:`.
3. **Full-Featured CLI Interface:**
   - CLI defaults now load directly from saved user preferences, so running `cascade --apply` respects whatever settings were configured in the GUI.
   - Added `--get-preferences` displaying an organized summary table of all stored values.
   - Added dedicated `--set-*` commands for all options.

## 4. Empirical Evidence

- **Unit Test Suite (`tests/test_engine.m`):**
  - Added `testPreferencesPersistence()` testing round-trip mutations across `orderMode`, `delta`, `restackZOrder`, `autoRearrange`, and `preferredAppOrder`.
  - All test suites (`test_engine`, `test_login`, `test_watcher`) pass with 100% success.
- **Domain Verification:**
  - Ran `cascade --set-order preferred --set-delta 50 --set-restack disable --set-auto-rearrange enable --set-app-order "..."` and verified via `defaults read com.brunobrise.cascade` that all keys are accurately written to the bundle domain.
- **Line Budget Verification:**
  - `src/WindowEngine.m`: 396 LOC (under 420 limit).
  - `src/main_bar.m`: 376 LOC (under 420 limit).
  - `src/main_cli.m`: 295 LOC (under 420 limit).
  - `tests/test_engine.m`: 294 LOC (under 420 limit).

## 5. Reusable Engineering Pattern

When building dual-interface macOS applications (packaged GUI App + companion CLI binary):
- Never rely on `[NSUserDefaults standardUserDefaults]` alone for shared settings; macOS isolates unbundled CLI tools to their executable name.
- Always use `[[NSUserDefaults alloc] initWithSuiteName:bundleId]` to bind all entry points to the application's canonical bundle domain.
- Provide a dual-write and fallback strategy to seamlessly upgrade legacy process-bound preferences without data loss.
