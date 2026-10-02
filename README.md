# Cascade

<p align="center">
  <img src="resources/brand/brand-primary.svg" width="128" height="128" alt="Cascade Icon" />
</p>

[![macOS](https://img.shields.io/badge/platform-macOS%2011.0%2B-blue.svg)](https://apple.com/macos)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)]()

Cascade is a native macOS window management engine that maximizes the display size of all active windows while mathematically guaranteeing that every window remains clickable with the mouse pointer at all times.

## Overview

Traditional window tiling partitions the screen into rigid slices, severely restricting usable application area (e.g. 25% of the display for four windows). Conversely, standard floating windows overlap randomly, completely occluding background tasks.

Cascade solves this conflict through an invariant staggered cascade geometry:
- **Maximum usable size:** Each window occupies between 73% and 98% of the display.
- **Permanent click targets:** Every window exposes an unoccluded tab (at top-right and bottom-left edges) that no other window can cover, regardless of the active stacking order.
- **Multi-screen partitioning:** Partition windows across displays with pixel-perfect Cocoa-to-Quartz coordinate inversion, cascading each monitor independently or targeting a specific screen.
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
make help              # Display all available make commands
make cert              # Provision persistent local code-signing certificate
make build             # Compile CLI binary and Status Bar app bundle
make icon              # Generate multi-resolution AppIcon.icns
make test              # Run the unit test suite
make run               # Launch Cascade.app into the status bar
make run-cli           # Preview layout in terminal (--plan)
make apply             # Cascade windows immediately (--apply)
make watch             # Continuously watch and auto-rearrange on window lifecycle
make check-permissions # Check accessibility permissions and diagnostic probe
make open-permissions  # Open macOS Accessibility settings pane
make reset-permissions # Reset TCC accessibility permissions (clears stale hashes)
make login-enable      # Register Cascade to start at login
make login-status      # Check login item registration status
make login-disable     # Unregister Cascade from login items
make status            # Check if Cascade is running
make stop              # Terminate running Cascade instance
make restart           # Stop and re-launch Cascade.app
make install           # Install CLI to ~/.local/bin and App to ~/Applications
make uninstall         # Remove installed binaries
make clean             # Remove build directory
```

### Installation

To install `cascade` into `~/.local/bin` and `Cascade.app` into `~/Applications`:

```bash
make install
```

### Code Signing & Accessibility Permissions

On macOS, Accessibility privileges are tied by Transparency, Consent, and Control (TCC) to an application's code signing Designated Requirement. If an app uses ad-hoc signing (`codesign -s -`), every rebuild produces a new binary hash (`cdhash`), invalidating previous permissions and forcing the user to re-grant access.

Cascade provides an automated local code-signing workflow to anchor permissions permanently:

1. **Provision local certificate (one-time setup):**
   ```bash
   make cert
   ```
   This generates a 10-year self-signed root certificate (`Cascade Code Signing`) in your login keychain and registers it for code signing trust and automated tool access.

2. **Compile and Install:**
   ```bash
   make build
   make install
   ```
   The build system automatically detects `Cascade Code Signing` and signs both `Cascade.app` and `cascade` with this certificate.

3. **Reset stale ad-hoc records (if upgrading from ad-hoc build):**
   ```bash
   make reset-permissions
   ```
   After granting Accessibility permission once in System Settings, permissions remain permanently valid across all future recompilations and updates.

## Usage

### Menu Bar Application

Launch `Cascade.app`:

```bash
open -a ~/Applications/Cascade.app
```

The menu bar icon appears in the macOS status bar:
- **Trigger Cascade:** Press `Option + Command + C` or click **Cascade Windows**.
- **Target Screen:** Select **All Screens (Independent)** to cascade every monitor on its own, **Active Screen (Follows Focus)** to target only where you are working, or target a specific display (e.g. `C49RG9x` or built-in display).
- **Window Order:** Switch between **Most Recently Used**, **Spatial Order**, **Alphabetical**, or **Preferred App Order** (configured via interactive panel with running app picker, drag-and-drop, and window order capture via **Configure App Order...**).
- **Tab Size (Delta):** Adjust margin between 30 px, 40 px, 50 px, and 60 px.
- **Restack Z-Order:** Re-raise windows in order to match spatial layout.
- **Auto-Rearrange on Open / Minimize / Close:** Automatically re-cascade windows whenever a window opens, closes, or is minimized.
- **Start at Login:** Toggle whether Cascade launches automatically on login.

### Command-Line Interface

```bash
# Preview layout calculation without moving windows
cascade --plan

# List all connected displays and usable bounds
cascade --list-screens

# Target a specific screen or all displays
cascade --screen "all" --apply
cascade --screen "active" --apply
cascade --screen "C49RG9x" --apply

# Set and persist default screen target
cascade --set-screen "all"

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

# View all currently saved user preferences
cascade --get-preferences

# Persist preferences from the command line
cascade --set-order preferred
cascade --set-delta 50
cascade --set-restack enable
cascade --set-auto-rearrange enable
cascade --set-app-order "Cursor, Google Chrome, Terminal, Slack"

# One-off preferred order override
cascade --app-order "Cursor, Chrome" --apply

# Custom margin size for a single run
cascade --delta 50 --apply

# Manage start at login
cascade --start-at-login enable
cascade --start-at-login status
cascade --start-at-login disable

# Arrange only specific applications
cascade --only "Cursor,Google Chrome" --apply

# Check accessibility permissions and probe diagnostics
cascade --check-permissions

# Open Accessibility settings pane in System Settings
cascade --open-permissions
```

## Documentation

- [Documentation Index](docs/index.md)
- [Architecture & Engine Specification](docs/specs/01a0f7ec7c122619-window-cascade-engine.md)
- [Brand Identity & Native Icon Specification](docs/specs/01a0fc49a5197278-minimalist-identity-and-icon-system.md)
- [Persistent Code Signing Specification](docs/specs/01a0fc7ed70771c2-persistent-code-signing-and-tcc.md)
- [Window Order Persistence Specification](docs/specs/f449f0cfe05f4db0-window-order-persistence.md)
- [Multi-Screen Support Specification](docs/specs/ab844179246d4c2d-multi-screen-support.md)
- [Invariant Cascade Success Story](docs/stories/01a0f7ec7c122619-invariant-cascade-success.md)
- [Minimalist Identity Success Story](docs/stories/01a0fc49a5197278-minimalist-identity-and-icon-success.md)
- [Persistent Code Signing Story](docs/stories/01a0fc7ed70771c2-persistent-code-signing-success.md)
- [Window Order Persistence Story](docs/stories/f449f0cfe05f4db0-window-order-persistence-success.md)
- [Multi-Screen Support Story](docs/stories/ab844179246d4c2d-multi-screen-support-success.md)
- [Quit Menu Item Enabled Story](docs/stories/f352ca5cf26a4345-quit-menu-item-enabled-success.md)
- [Status Bar Icon Geometry Fix Story](docs/stories/fd10f6ae52d04fd8-status-bar-icon-metrics-success.md)
- [Screen Configuration Persistence Story](docs/stories/ccc46c535e764e3d-screen-config-persistence-success.md)
- [Pointer-Screen Cascade Story](docs/stories/c5db1b63123a4e2c-pointer-screen-cascade-success.md)
- [Auto-Cascade Target Screen Story](docs/stories/31d539e4f4de4d6d-auto-cascade-target-screen-success.md)
- [Order Preservation Story](docs/stories/01a0f7ec7c122619-order-preservation-success.md)
- [Preferred App Order Story](docs/stories/01a0f7ec7c122619-preferred-app-order-success.md)
- [User Preferences Persistence Story](docs/stories/01a0f7ec7c122619-user-preferences-persistence-success.md)
- [Resilient Permissions Story](docs/stories/01a0f7ec7c122619-resilient-permissions-check-success.md)
- [Windows Order Redesign Story](docs/stories/01a0f7ec7c122619-windows-order-modal-redesign-success.md)
- [Accessibility & Code Signing Postmortem](docs/stories/01a0f7ec7c122619-accessibility-code-signing-postmortem.md)
- [Interactive Brand Showcase](resources/brand/brand-preview.html)

## License

MIT License. See LICENSE for details.
