---
date: 2026-10-01
type: success
status: validated
related_specs:
  - ../specs/01a0f7ec7c122619-window-cascade-engine.md
---

# Invariant Window Cascade Success Story

## 1. Context

On macOS, power users and developers often keep 4 to 10 application windows open simultaneously (editors, browsers, communication apps, database tools). Traditional tiling managers partition the screen into small boxes (e.g. 25% of the screen for 4 windows), significantly restricting workspace size. Conversely, traditional floating windows overlap haphazardly, completely occluding background windows and forcing friction-heavy switching (Mission Control, Cmd+Tab, or Dock hunting).

## 2. Intended Outcome (The Bet)

We hypothesized that an **Invariant Staggered Cascade** layout could provide:
1. Near-fullscreen dimensions ($73\%$ to $98\%$ of screen area per window).
2. Mathematically guaranteed clickability: every window exposes an unoccluded $\delta \times \delta$ click target regardless of the active stacking order.
3. Multiple ordering paradigms (Most Recently Used, Spatial, and Alphabetical).

## 3. What Worked and Why

1. **Two-Window Opposed Edge Optimization:** For $N = 2$, placing Window 1 left-aligned and Window 2 right-aligned with offset $\delta$ provides $98\%$ screen area to each window, with full-height $\delta \times H$ vertical edge click targets.
2. **N-Window Diagonal Cascade Disjointness:** By staggering origins diagonally by $\delta$ and sizing all windows to $(W - (N-1)\delta, H - (N-1)\delta)$, every window $i$ possesses a top-right corner patch $P_i = [X_i + w - \delta, X_i + w] \times [Y_i, Y_i + \delta]$ that is mathematically disjoint from all other windows $j \neq i$.
3. **Accessibility API Authorization:** Direct Objective-C implementation using `ApplicationServices` and `Carbon` runs with native accessibility trust, bypassing `osascript` AppleEvents security restrictions.

## 4. Empirical Evidence

- **Unit Test Suite:** `tests/test_engine.m` asserts mutual disjointness across arbitrary window sets ($N=5$) and confirms zero intersection across all tab bounding boxes.
- **Screen Metrics:** Verified on an $1800 \times 1169$ Retina screen with $39\text{ px}$ menu bar inset; 6 windows each received $1600 \times 930\text{ px}$ ($73.2\%$ area) with $40 \times 40\text{ px}$ unoccluded tabs.
- **Status Bar Integration:** Built `Cascade.app` running as a background menu bar agent (`LSUIElement`) with global hotkey `⌥⌘C`.

## 5. Reusable Engineering Pattern

When maximizing overlapping 2D rectangles under an all-accessible invariant:
- Define the exclusive footprint $E_i = R_i \setminus \bigcup_{j \neq i} R_j$.
- Diagonal translation with uniform dimensions ensures $E_i$ is non-empty at the extreme opposing corners (top-right and bottom-left).
- Restack Z-order in reverse order ($N-1 \to 0$) to align physical depth with visual layout.

## 6. Known Limits

- Fixed-size dialogs (e.g., Apple System Settings panels with hardcoded maximum widths) will match vertical bounds and position but may not stretch to full target width.
- Very large window counts ($N > 15$) will require smaller delta values ($\delta \approx 20\text{ px}$) to prevent window dimensions from collapsing below usable thresholds ($400 \times 300\text{ px}$).

## 7. Related Artifacts

- Spec: [Window Cascade Engine Spec](../specs/01a0f7ec7c122619-window-cascade-engine.md)
- Tests: `tests/test_engine.m`
- Core Engine: `src/WindowEngine.m`
- Status Bar App: `src/main_bar.m`
