---
date: 2026-10-16
type: success
status: validated
---

# Manual Fractal Layout & Independent Edge Docking Success Story

## Context

User requested a fundamental shift in the Fractal window management paradigm:
> *"Fractal: no order! User manually set windows. ultrathink twice, don't hesitate to challenge yourself, if needed! /ultrathink"*

Following deep `/ultrathink` analysis, we identified that TrellisWM's true paradigm differs significantly from automated window managers:
1. **Exponential Area Decay ($\phi^k$):** In a recursive golden-ratio subdivision, window area decays exponentially ($61.8\% \to 23.6\% \to 9.0\% \to 3.4\%$). Auto-sorting by MRU causes disruptive slot jumping upon every window focus.
2. **Manual Construction:** TrellisWM has no automated sorting; the layout is established intentionally by the user.
3. **Independent Edge Docking:** Previous `--dock` forced all desktop windows into an unwanted cascade inside the residual screen half.

## Architectural Changes & Capabilities Delivered

### 1. Manual Window Ordering for Fractal Layout
- In `CascadeLayoutStyleFractal`, automated sorting modes (`MRU`, `Spatial`, `Alphabetical`) are bypassed.
- Window order is strictly determined by user manual configuration (`preferredOrder`).
- Focus changes no longer trigger slot reshuffling or demote the primary window.

### 2. Maximum Depth Clamping ($K \le 4$)
- Only participating windows (up to 4) are partitioned in the fractal golden spiral (Primary 61.8%, Secondary 23.6%, Tertiary 9.0%, Quaternary residual).
- Excess windows ($N > 4$) retain their existing desktop coordinates (`targetFrame = currentFrame`), preventing window shrinkage into unusable micro-slivers.

### 3. Clean Independent Edge Docking
- `--dock [left|right|top|bottom]` moves and tiles only the focused window to the target screen half ($50\%$).
- Other desktop windows remain untouched in their current frames.
- New geometry API `+ (CGRect)dockedFrameForEdge:onUsableFrame:` provides clean, deterministic docking bounds.

### 4. Settings UI Alignment
- When `Fractal` layout style is selected, Window Order displays `Manual (User Set)` and disables auto-sorting while keeping `Configure...` accessible for manual ordering.

## Verification & Test Results

All capabilities were verified with strict TDD across unit test suites (`tests/test_fractal.m` and `tests/test_settings.m`):
- `testFractalBypassesAutoOrderAndPreservesManual`: Verified MRU bypass and strict manual order preservation.
- `testFractalMaxDepthClamping`: Verified $K \le 4$ partition clamping and preservation of excess window frames.
- `testIndependentDockingPreservesOtherWindows`: Verified clean edge docking without side effects on other windows.
- All 13 test suites pass cleanly with zero failures.
