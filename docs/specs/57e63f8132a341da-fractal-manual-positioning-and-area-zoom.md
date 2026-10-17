---
date: 2026-10-17
title: Fractal Manual Window Positioning and Area Selection Zoom Specification
---

# Fractal Manual Window Positioning and Area Selection Zoom Specification

## Problem and Goal

While Fractal mode previously established a non-shuffling golden ratio arrangement for up to 4 windows, users require:
1. **Manual Window Positioning Memory:** In Fractal mode, the user can manually set window positions. Cascade must remember these positions, persisted across layouts and resolution changes.
2. **Area Selection Zooming:** The user can select an area of the fractal screen (via an interactive marquee selection overlay or CLI area parameter), which selects intersecting windows and zooms in on them proportionally to fill the screen workspace, with toggle-restore capability.

## Technical Architecture

### 1. Resolution-Independent Position Memory
- Store relative normalized coordinates $(rx, ry, rw, rh) \in [0, 1]$ relative to `usableFrame`:
  $$rx = \frac{x - usable.origin.x}{usable.size.width}, \quad ry = \frac{y - usable.origin.y}{usable.size.height}$$
  $$rw = \frac{w}{usable.size.width}, \quad rh = \frac{h}{usable.size.height}$$
- Stored under `userDefaults` key `"fractalManualPositions"`.
- When calculating Fractal layout in `calculateLayoutForWindows:`, any window with a saved position overrides the default algorithmic slot and scales to current display bounds.
- Dual-capture:
  - Automatic: `WindowWatcher` listens to `kAXWindowMovedNotification` & `kAXWindowResizedNotification` (debounced 0.35s). When moved in Fractal mode, new frame is saved.
  - Explicit: `saveFractalPositionsForWindows:onUsableFrame:` via status menu and CLI.

### 2. Area Selection & Fractal Zoom
- `SelectionOverlayController`:
  - Fullscreen transparent borderless `NSPanel` at `NSScreenSaverWindowLevel`.
  - Crosshair cursor, interactive click-and-drag marquee with live window count indicator.
  - Escape key cancels.
  - Converts Cocoa selection rectangle to Quartz coordinates via `ScreenManager`.
- Zoom execution:
  - `windowsIntersectingQuartzRect:inWindows:` finds intersecting windows.
  - Pre-zoom snapshot stored in `userDefaults` key `"fractalZoomState"`.
  - Union bounding box $R_{\text{union}} = \bigcup W_i.\text{frame}$ calculated.
  - Selected windows scaled proportionally from $R_{\text{union}}$ to fill `usableFrame`.
  - Zoom reset: `resetFractalZoom` restores exact pre-zoom frames and clears state.

## Acceptance Criteria
- [ ] User can manually position windows in Fractal mode and Cascade remembers them.
- [ ] Layout scales properly across screen resolution changes without distortion.
- [ ] Drag-selection overlay accurately selects windows and triggers proportional zoom.
- [ ] Zoom toggle (`⌘ ⌥ Z` or menu) restores pre-zoom layout cleanly.
- [ ] All unit tests pass cleanly.
