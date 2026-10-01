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
- **Multiple ordering strategies:** Order windows by Most Recently Used (front-to-back), Spatial Position (left-to-right), Alphabetical application name, or Preferred Application Order (by prioritized name).
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

### Quick Commands

The included `Makefile` provides commands to build, test, run, and install Cascade:

```bash
make help          # Display all available make commands
make build         # Compile CLI binary and Status Bar app bundle
make icon          # Generate multi-resolution AppIcon.icns
make test          # Run the unit test suite
make run           # Launch Cascade.app into the status bar
make run-cli       # Preview layout in terminal (--plan)
make apply         # Cascade windows immediately (--apply)
make watch         # Continuously watch and auto-rearrange on window lifecycle
make login-enable  # Register Cascade to start at login
make login-status  # Check login item registration status
make login-disable # Unregister Cascade from login items
make status        # Check if Cascade is running
make stop          # Terminate running Cascade instance
make restart       # Stop and re-launch Cascade.app
make install       # Install CLI to ~/.local/bin and App to ~/Applications
make uninstall     # Remove installed binaries
make clean         # Remove build directory
```

### Installation

To install `cascade` into `~/.local/bin` and `Cascade.app` into `~/Applications`:

```bash
make install
```

## Usage

### Menu Bar Application

Launch `Cascade.app`:

```bash
open -a ~/Applications/Cascade.app
```

The menu bar icon appears in the macOS status bar:
- **Trigger Cascade:** Press `Option + Command + C` or click **Cascade Windows**.
- **Window Order:** Switch between **Most Recently Used**, **Spatial Order**, **Alphabetical**, or **Preferred App Order** (configured via **Configure App Order...**).
- **Tab Size (Delta):** Adjust margin between 30 px, 40 px, 50 px, and 60 px.
- **Restack Z-Order:** Re-raise windows in order to match spatial layout.
- **Auto-Rearrange on Open / Minimize / Close:** Automatically re-cascade windows whenever a window opens, closes, or is minimized.
- **Start at Login:** Toggle whether Cascade launches automatically on login.

### Command-Line Interface

```bash
# Preview layout calculation without moving windows
cascade --plan

# Apply layout to active windows
cascade --apply

# Continuously watch and rearrange on window open/minimize/close
cascade --watch

# Order by application name (alphabetical)
cascade --order alpha --apply

# Order by user-configured preferred application order
cascade --order preferred --apply

# Set and persist preferred application order list
cascade --set-app-order "Cursor, Google Chrome, Terminal, Slack"

# Query currently persisted preferred application order
cascade --get-app-order

# One-off preferred order override
cascade --app-order "Cursor, Chrome" --apply

# Custom margin size
cascade --delta 50 --apply

# Manage start at login
cascade --start-at-login enable
cascade --start-at-login status
cascade --start-at-login disable

# Arrange only specific applications
cascade --only "Cursor,Google Chrome" --apply
```

## Documentation

- [Documentation Index](docs/index.md)
- [Architecture & Engine Specification](docs/specs/01a0f7ec7c122619-window-cascade-engine.md)
- [Success Story](docs/stories/01a0f7ec7c122619-invariant-cascade-success.md)
- [Order Preservation Story](docs/stories/01a0f7ec7c122619-order-preservation-success.md)
- [Preferred App Order Story](docs/stories/01a0f7ec7c122619-preferred-app-order-success.md)
- [Accessibility & Code Signing Postmortem](docs/stories/01a0f7ec7c122619-accessibility-code-signing-postmortem.md)

## License

MIT License. See LICENSE for details.
