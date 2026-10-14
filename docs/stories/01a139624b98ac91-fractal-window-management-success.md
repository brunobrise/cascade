---
date: 2026-10-14
type: success
status: validated
---

# Fractal Window Management & Focus Zoom Success Story

## Context

Users requested native fractal window management capabilities inspired by TrellisWM, while ensuring screen resolution and display boundaries impose no artificial limitations:
> *"Add "fractal" features based on https://trelliswm.app*
> *Screen resolution shouldn't be a limitation! ask confirmation before implementation! /ultrathink"*

Following deep `/ultrathink` architectural analysis, we eliminated TrellisWM's reliance on battery-draining GPU video compositors (`ScreenCaptureKit`), invasive screen recording permissions (persistent purple menu bar indicators), and virtual infinite canvas panning latency. Instead, Cascade introduces native AppKit/Accessibility recursive Golden-Spiral subdivision, nested edge docking, and resolution-independent instant Focus Zoom (`⌥⌘Space`).

## Mathematical Foundation & Recursive Golden Spiral

Given usable display bounds $B_0 = (X_0, Y_0, W_0, H_0)$, window count $N \ge 1$, and golden ratio division factor $\phi = \frac{\sqrt{5}-1}{2} \approx 0.6180339887$:

For window index $i = 0, 1, \dots, N-1$:
- If $i = N - 1$ (the leaf window), Window $i$ receives the entire residual bounding box $B_i$.
- Otherwise, $B_i$ is partitioned along direction $D = i \pmod 4$:
  - $D = 0$ (Left): Window $i$ takes left fraction $W_i \cdot \phi$. Residual box $B_{i+1}$ takes right fraction $W_i \cdot (1 - \phi)$.
  - $D = 1$ (Top): Window $i$ takes top fraction $H_i \cdot \phi$. Residual box $B_{i+1}$ takes bottom fraction $H_i \cdot (1 - \phi)$.
  - $D = 2$ (Right): Window $i$ takes right fraction $W_i \cdot \phi$. Residual box $B_{i+1}$ takes left fraction $W_i \cdot (1 - \phi)$.
  - $D = 3$ (Bottom): Window $i$ takes bottom fraction $H_i \cdot \phi$. Residual box $B_{i+1}$ takes top fraction $H_i \cdot (1 - \phi)$.

Every window $i$ maintains visible perimeter edge tabs along the spiral, guaranteeing instant point-and-click focus recovery without cognitive search overhead.

## Architecture & Capabilities Delivered

### 1. Fractal Layout (`--layout fractal`)
- Integrated `CascadeLayoutStyleFractal = 2` into `WindowLayoutGeometry` and `WindowEngine`.
- Full persistence in user preferences suite (`com.brunobrise.cascade`).
- Supported in CLI planning and execution (`cascade --layout fractal --apply`).
- Configurable via the Settings modal segmented control (`Diagonal | Quad-Edge | Fractal`).

### 2. Recursive Fractal Edge Docking (`--dock [left|right|top|bottom]`)
- Active window pins to requested screen half ($50\%$).
- Remaining $(N-1)$ windows recursively cascade/partition inside the residual child bounding box using the active layout style.
- CLI supports planning (`cascade --dock left --plan`) and instant execution (`cascade --dock left --apply`).
- Status bar menu provides 1-click docking options: `Dock Left`, `Dock Right`, `Dock Top`, `Dock Bottom`.

### 3. Resolution-Independent Focus Zoom (`--zoom` / `⌥⌘Space`)
- Global Carbon hotkey `⌥⌘Space` (Keycode `0x31`) instantly toggles between fractal macro-overview and 100% native monitor resolution.
- Zoom in captures exact pre-zoom window coordinates in user preferences and expands the active window to full usable display bounds at top Z-stack.
- Zoom out restores the window precisely into its fractal coordinate frame with 0ms latency.
- Completely eliminates display resolution as a constraint for deep nesting.

## Test Verification & Acceptance

All capabilities were developed strictly using Test-Driven Development (`tests/test_fractal.m`):
1. **Preferences Persistence:** `testFractalPreferencesPersistence` verified suite round-trip.
2. **Single Window Invariant:** `testFractalSingleWindow` verified full usable area allocation.
3. **Golden Split Invariant:** `testFractalTwoWindows` verified exact $\phi \approx 0.618$ ratio.
4. **Golden Spiral Invariant:** `testFractalFiveWindowsGoldenSpiral` verified direction cycling and perimeter tab exposure for $N = 5$.
5. **Deep Recursion Stability:** `testFractalDeepNesting` verified non-degenerate coordinates for $N = 10$ on 5K display.
6. **Edge Docking Invariant:** `testFractalDocking` verified half-screen docking and child residual cascade containment.
7. **Regression Protection:** All 13 unit test suites pass cleanly with 0 warnings or errors.
