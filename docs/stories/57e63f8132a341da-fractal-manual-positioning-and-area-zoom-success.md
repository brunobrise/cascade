---
date: 2026-10-17
type: success
status: validated
---

# Fractal Manual Window Positioning & Area Selection Zoom Success Story

## Context

User requested:
> *"Fractal mode let user manually set window position! Cascade just need to remember it. Also user should be able to zoom on a part of the fractal by selecting the area (which selects the windows to zoom in on). ultrathink twice, don't hesitate to challenge yourself, if needed! /ultrathink"*

Following deliberate `/ultrathink` analysis:
1. **Window Placement Memory:** In Fractal mode, window positions are manually established by the user. Hardcoded automatic layouts disrupt this. Cascade now remembers each window's manually positioned coordinates.
2. **Resolution-Independence:** Window positions are normalized $(rx, ry, rw, rh)$ against the screen's usable frame, ensuring layouts scale seamlessly across display resolution changes (e.g. 1080p, 1440p, 4K, Retina).
3. **Area Selection Zoom:** Users can drag a marquee selection box across the screen (`⌥⌘Z` or menu item). Intersecting windows are selected, and their union bounding box $R_{\text{union}}$ is scaled proportionally to fill the screen workspace, with instant 1-key toggle restoration.

## Architectural Changes & Capabilities Delivered

### 1. Normalized Manual Position Memory
- Added `saveFractalPositionForWindow:onUsableFrame:`, `savedFractalPositionForWindow:onUsableFrame:`, and `clearSavedFractalPositions` in `CascadeEngine`.
- Resolution-independent normalized coordinates scale cleanly to any target display.
- Integrated into `calculateLayoutForWindows:`, applying saved manual positions over default algorithmic spiral frames.
- Automatic capture: `WindowWatcher` listens to `kAXWindowMovedNotification` & `kAXWindowResizedNotification` (debounced 0.35s). Moving a window in Fractal mode automatically updates its memory.
- Explicit commands: Status menu items "Remember Window Positions" / "Reset Window Positions" and CLI flags `--save-positions` / `--reset-positions`.

### 2. Interactive Area Selection Overlay
- Built `SelectionOverlayController`:
  - Fullscreen transparent borderless `NSPanel` at `NSScreenSaverWindowLevel`.
  - Crosshair cursor, interactive click-and-drag marquee with live window count indicator.
  - Converts Cocoa coordinates to Quartz coordinates via `ScreenManager`.
  - Escape key cancels cleanly.

### 3. Fractal Area Zoom and Restore
- `windowsIntersectingQuartzRect:inWindows:` identifies all windows intersecting the selection rectangle.
- `zoomFractalWindows:onUsableFrame:` snapshots all open windows into `fractalZoomState` and expands selected windows proportionally to fill the screen's `usableFrame`.
- `resetFractalZoom` restores all windows back to their exact pre-zoom coordinates.
- Bound to global hotkey `⌥⌘Z` and menu item "Select Area to Zoom..." / "Exit Zoom (Restore Windows)".
- Scriptable CLI commands: `cascade --zoom-area <x,y,w,h>` and `cascade --zoom-reset`.

## Verification & Test Results
- `testFractalManualWindowPositionPersistence`: Verified normalized position persistence across different screen resolutions (1440p vs 4K).
- `testFractalAreaIntersection`: Verified accurate window selection via marquee rectangle intersection.
- `testFractalAreaZoomAndRestore`: Verified proportional window magnification to full workspace and pre-zoom state restoration.
- All 13 unit test suites pass cleanly (`rtk make test`).
