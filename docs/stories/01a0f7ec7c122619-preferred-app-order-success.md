---
date: 2026-10-01
type: success
status: validated
related_specs:
  - ../specs/01a0f7ec7c122619-window-cascade-engine.md
---

# User-Configurable Preferred Application Ordering Success Story

## 1. Context

In daily multitasking workflows, users frequently maintain an intuitive hierarchy of applications. For example, a developer may want their primary editor (`Cursor`) always in the primary foreground slot (Slot 0), their web browser (`Google Chrome`) in Slot 1, their `Terminal` in Slot 2, and communication tools (`Slack`) in Slot 3 or further back.

Previously, Cascade provided three fixed sorting modes:
- Most Recently Used (`MRU`): Based on momentary WindowServer focus.
- Spatial: Left-to-right based on screen position.
- Alphabetical: Ordered by localized application name.

Users requested the ability to define and persist an explicit application hierarchy by name so that cascading windows immediately arranges their preferred applications into designated priority slots.

## 2. Intended Outcome

1. **Configurable Application Priority List:** Users can specify a comma-separated list of application names (e.g., `Cursor, Google Chrome, Terminal, Slack`).
2. **Deterministic Priority Ranking:**
   - Windows of applications in the preferred list occupy the front cascade slots in exact preference sequence.
   - Applications not listed in the preference list follow in secondary MRU order at the tail of the cascade.
   - Multiple windows of the same application preserve their intra-application MRU order.
3. **Dual Interface Support:**
   - Status bar menu: "Window Order" > "Preferred App Order" and "Configure App Order..." modal dialog with immediate cascade execution upon saving.
   - Command-line interface: `--order preferred`, `--app-order "<list>"`, `--set-app-order "<list>"`, and `--get-app-order`.
4. **Preference Persistence:** Stored reliably across sessions in `NSUserDefaults` under key `preferredAppOrder`.
5. **Seamless Event Preservation:** Seamlessly integrates with the event-driven order preservation engine, ensuring that subsequent window open/resize/minimize/close events preserve the preferred cascade slots.

## 3. What Worked and Why

1. **Two-Tier Matching and Multi-Key Sorting:**
   - App rank matching (`rankForApp`) performs exact case-insensitive comparison first (`localizedCaseInsensitiveCompare:`), followed by case-insensitive substring search (`localizedCaseInsensitiveContainsString:`). This allows natural shorthands like `"Chrome"` matching `"Google Chrome"` or `"Code"` matching `"Visual Studio Code"`.
   - The comparator sorts by:
     1. Primary: Configured preferred rank (0, 1, 2, ...; unlisted apps get rank 999999).
     2. Secondary: Intra-app or unlisted tie-breaker using WindowServer MRU Z-rank (`a.zRank < b.zRank`).
     3. Tertiary: Alphabetical fallback.
2. **Compact UI Architecture (`makeItem`):**
   - Factoring menu item construction into a compact static helper in `main_bar.m` reduced repetitive boilerplate by over 35 lines, enabling rich dialog and preference integration while staying comfortably under the 420 LOC limit (397 LOC).
3. **Persistent State Synchronization:**
   - `orderMode` and `preferredAppOrder` synchronize to `NSUserDefaults`, ensuring that user preferences persist across application restarts.

## 4. Empirical Evidence

- **Automated Tests (`tests/test_engine.m`):**
  - `testPreferredAppOrderSorting` validated rank-based placement (`Cursor` -> `Chrome 1` -> `Chrome 2` -> `Terminal` -> `Slack`), substring matching, intra-app MRU preservation between two Chrome windows, and unlisted application fallback.
  - Full test suite passed across all 3 test binaries (`test_engine`, `test_login`, `test_watcher`).
- **CLI Verification:**
  - Tested `--set-app-order` and `--get-app-order` persistence and formatting.
  - Verified `--order preferred` argument parsing and help output.

## 5. Reusable Engineering Pattern

When providing customizable sorting preferences over complex system entities:
- Implement a hierarchical comparator: (Explicit Priority Rank) $\to$ (MRU Depth) $\to$ (Deterministic Identifier).
- Support both exact and prefix/substring matching to tolerate minor differences between system application bundle names and common user names.
- Always persist configuration changes immediately and provide both interactive GUI and scriptable CLI access points.
