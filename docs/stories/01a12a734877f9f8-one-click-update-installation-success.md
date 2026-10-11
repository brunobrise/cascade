---
date: 2026-10-11
type: success
status: validated
related_specs:
  - ../specs/06aff35245874c5d-update-check-and-notification.md
---

# In-App 1-Click Update Installation & Atomic Swap Success Story

## Context and Problem

When a new version was published, Cascade displayed an alert prompt ("Update Available!") that only offered `[View Release]` and `[Later]`. Clicking `[View Release]` redirected the user to the GitHub release page in a web browser, leaving the user to manually download the disk image or execute command-line curl scripts to apply the update.

Users expected a direct `[Update Now]` option that downloads, installs, and restarts the application seamlessly without losing macOS Accessibility (TCC) permissions.

## Root Cause Analysis

1. **Missing In-App Update Engine:** `UpdateChecker` previously only performed version discovery and state caching, delegating upgrade execution entirely to external shell scripts or browser links.
2. **Execution Locking of Running Mach-O Binary:** A running macOS application cannot have its binary overwritten in-place while executing.
3. **Cryptographic Trust Preservation:** Simply downloading and unpacking an ad-hoc pre-built release would revoke macOS Accessibility authorization if the bundle was not re-signed with the user's persistent local root certificate (`Cascade Code Signing`).

## Solution

We implemented a zero-dependency, atomic 1-click update installation pipeline:

1. **Pre-Flight Download & Integrity Verification (`UpdateChecker`):**
   - Resolves target release download URL: `https://github.com/brunobrise/cascade/releases/download/v<version>/Cascade-v<version>-Universal.dmg`.
   - Downloads the Universal DMG via `NSURLSessionDownloadTask` to a private temporary directory (`/tmp/cascade-update-XXXXXX/`).
   - Verifies installer integrity by mounting with `hdiutil attach -nobrowse -readonly` and validating the existence of `Cascade.app/Contents/MacOS/Cascade`.

2. **Atomic Swap & Rollback Helper (`finish_update.sh`):**
   - Generates and launches a detached bash helper script passing the current app PID, target installation path, mount point, and local signing identity.
   - The script waits for the old PID to cleanly exit (`kill -0 "$OLD_PID"`).
   - Backs up the running bundle to `${TARGET}.old` before replacement to ensure zero-downtime rollback if file copying fails.
   - Copies the new bundle to `/Applications/Cascade.app`.
   - Re-signs with `Cascade Code Signing` (`codesign --force -s "Cascade Code Signing"`), preserving the exact Designated Requirement hash and keeping macOS TCC permissions intact.
   - Clears quarantine flags (`xattr -cr`) to prevent Gatekeeper App Translocation.
   - If CLI binary is installed in `~/.local/bin/cascade`, updates and re-signs the CLI binary in sync.
   - Detaches the disk image, cleans `/tmp/`, and relaunches the new version via `open "$TARGET"`.

3. **User Interface Integration (`CascadeBarApp` & `SettingsWindowController`):**
   - Both the Status Bar update alert and the Settings window "Check for Updates" prompt now present three clear choices:
     - `[Update Now]` (Primary / Default) -> Launches updater HUD with progress indicator and initiates in-app swap.
     - `[View Release]` -> Opens release notes on GitHub.
     - `[Later]` -> Dismisses prompt.
   - The menu bar item `✨ Update Available: vX.Y.Z...` now directly opens this update dialog instead of opening a web browser.

## Verification & Results

- **Unit Tests:**
  - Added `testUpdateAssetURLs` in `tests/test_update_checker.m` verifying Universal DMG and CLI tarball URL generation.
  - Added `testUpdateSwapScript` verifying PID wait loop, atomic backup, codesign invocation, and launch commands.
  - Ran `rtk make test`: All 12 test suites passed cleanly.
- **Compilation:**
  - Rebuilt `build/cascade` and `build/Cascade.app` with zero compiler warnings.
