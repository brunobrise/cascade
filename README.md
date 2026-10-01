# Cascade

[![macOS](https://img.shields.io/badge/platform-macOS%2011.0%2B-blue.svg)](https://apple.com/macos)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)]()

Cascade is a native macOS window management engine that maximizes the display size of all active windows while mathematically guaranteeing that every window remains clickable with the mouse pointer at all times.

## Overview

Traditional window tiling partitions the screen into rigid slices, severely restricting usable application area (e.g. 25% of the display for four windows). Conversely, standard floating windows overlap randomly, completely occluding background tasks.

Cascade solves this conflict through an invariant staggered cascade geometry:
- **Maximum usable size:** Each window occupies between 73% and 98% of the display.
- **Permanent click targets:** Every window exposes an unoccluded tab (at top-right and bottom-left edges) that no other window can cover, regardless of the active stacking order.
- **Multiple ordering strategies:** Order windows by Most Recently Used (front-to-back), Spatial Position (left-to-right), or Alphabetical application name.
- **Status Bar Integration:** Lives in the macOS menu bar with configurable hotkey support (`Option + Command + C`).

## Mathematical Foundation

For $N \ge 3$ windows on a screen of width $W$ and height $H$ with clickable margin $\delta$:
- Window dimensions: $w = W - (N-1)\delta, \quad h = H - (N-1)\delta$.
- Origin for window $i$: $X_i = (i-1)\delta, \quad Y_i = (i-1)\delta$.
- The top-right tab of window $i$, defined as $P_i = [X_i + w - \delta, X_i + w] \times [Y_i, Y_i + \delta]$, is mathematically disjoint from all other windows $j \ne i$.

For $N = 2$, Cascade anchors Window 1 to the left bezel and Window 2 to the right bezel, giving each window 98% of the screen area with full-height vertical click targets.

For detailed proofs and architecture, see the [Window Cascade Engine Spec](docs/specs/01a0f7ec7c122619-window-cascade-engine.md).

## Requirements

- macOS 11.0 (Big Sur) or higher.
- Clang / Xcode Command Line Tools (`xcode-select --install`).
- Accessibility permissions granted in **System Settings > Privacy & Security > Accessibility**.

## Building and Installation

### Build from Source

```bash
git clone https://github.com/brunobrise/cascade.git
cd cascade
make all
```

This compiles:
- `build/cascade`: Command-line interface.
- `build/Cascade.app`: Native status bar application bundle.

### Run Tests

```bash
make test
```

### Install to System

```bash
make install
```

This installs `cascade` into `~/.local/bin/cascade` and `Cascade.app` into `~/Applications/Cascade.app`.

## Usage

### Menu Bar Application

Launch `Cascade.app`:

```bash
open -a ~/Applications/Cascade.app
```

The menu bar icon appears in the macOS status bar:
- **Trigger Cascade:** Press `Option + Command + C` or click **Cascade Windows**.
- **Window Order:** Switch between **Most Recently Used**, **Spatial Order**, and **Alphabetical**.
- **Tab Size (Delta):** Adjust margin between 30 px, 40 px, 50 px, and 60 px.
- **Restack Z-Order:** Re-raise windows in order to match spatial layout.

### Command-Line Interface

```bash
# Preview layout calculation without moving windows
cascade --plan

# Apply layout to active windows
cascade --apply

# Order by application name (alphabetical)
cascade --order alpha --apply

# Custom margin size
cascade --delta 50 --apply

# Arrange only specific applications
cascade --only "Cursor,Google Chrome" --apply
```

## Documentation

- [Documentation Index](docs/index.md)
- [Architecture & Engine Specification](docs/specs/01a0f7ec7c122619-window-cascade-engine.md)
- [Success Story](docs/stories/01a0f7ec7c122619-invariant-cascade-success.md)

## License

MIT License. See LICENSE for details.
