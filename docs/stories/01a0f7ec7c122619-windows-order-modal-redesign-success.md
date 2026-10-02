---
date: 2026-10-02
type: success
status: validated
related_specs:
  - ../specs/01a0f7ec7c122619-window-cascade-engine.md
---

# Windows Order Configuration UI/UX Redesign Success Story

## 1. Context

Cascade allows users to customize the priority order of applications when cascading windows via the **Preferred App Order** mode. Previously, configuring this order relied on an `NSAlert` modal presenting a single 320 px text box for comma-separated strings (`"Cursor, Google Chrome, Terminal, Slack"`).

This early implementation suffered from severe usability issues:
1. **High Cognitive Load (Recall over Recognition):** Users had to recall and manually type exact application bundle names from memory without auto-completion, typo handling, or visual feedback.
2. **Modality Lock (`runModal`):** The synchronous alert modal locked the macOS run loop and blocked user interaction, preventing users from seeing or arranging the windows on their desktop while configuring.
3. **Absence of Direct Manipulation:** Reordering required manually editing commas and strings in a small input field rather than native drag-and-drop or accessible move controls.
4. **Context Disconnection:** Users had to configure in isolation without any ability to capture or reference their currently open, active windows.

## 2. Intended Outcome

1. **Non-Modal Utility Panel (`NSPanel`):** Replace the blocking `NSAlert` with an interactive, floating utility window following macOS Human Interface Guidelines.
2. **One-Click Window Snapshot:** Provide a **"📸 Capture Current Window Order"** action that instantly reads active on-screen windows in their front-to-back layout and populates the priority list.
3. **Visual Reorderable Table (`NSTableView`):**
   - High-resolution application icons retrieved via running processes or `/Applications`.
   - Clear ranking badges (`#1 Front`, `#2`, `#3`... `#N Back`) clarifying the spatial cascade depth.
   - Smooth drag-and-drop row reordering.
   - Accessible Up (`▲`) and Down (`▼`) buttons and keyboard shortcuts.
4. **Running Apps Quick-Picker:** A `+` popup menu listing all currently active GUI applications with their real icons for one-click addition, plus a file picker fallback.
5. **Immediate Application Option:** Checkbox to automatically cascade windows immediately upon saving.
6. **Strict Code Quality & LOC Budget:** Modular controller architecture keeping all files strictly under 420 LOC.

## 3. What Worked and Why

1. **Modular Architecture (`AppOrderWindowController`):**
   - Decoupled the entire window and table view logic into `src/AppOrderWindowController.h` (12 LOC) and `src/AppOrderWindowController.m` (372 LOC).
   - Reduced `src/main_bar.m` from 389 to 378 LOC by replacing the inlined alert code with a clean completion handler callback.
2. **Native Reorderable Table with AppKit Drag-and-Drop:**
   - Implemented `pasteboardWriterForRow:`, `validateDrop:`, and `acceptDrop:` using `NSPasteboardTypeString`.
   - Bound selection state to Up/Down/Remove buttons (`updateButtonStates`) ensuring clear visual affordances and accessibility.
3. **Dynamic Running Applications Discovery:**
   - Filtered `[[NSWorkspace sharedWorkspace] runningApplications]` by `NSApplicationActivationPolicyRegular` to present only user-facing GUI apps.
   - Enabled one-click addition without browsing the filesystem.
4. **Active Screen Capture:**
   - Leveraging `[CascadeEngine collectStandardWindowsWithOnly:nil exclude:nil]` allows users to arrange windows on screen and snapshot the exact sequence into their preferences with zero typing.

## 4. Empirical Evidence

- **Unit Test Suite (`tests/test_app_order.m`):**
  - Verified singleton initialization, preference setting, and round-trip retrieval.
  - All test suites (`test_engine`, `test_login`, `test_watcher`, `test_app_order`) pass with 100% success rate:
    ```bash
    make test
    ```
- **Line Count Discipline:**
  - `src/AppOrderWindowController.h`: 12 LOC
  - `src/AppOrderWindowController.m`: 372 LOC (under 420 limit)
  - `src/main_bar.m`: 378 LOC (under 420 limit)
  - `tests/test_app_order.m`: 34 LOC
  - All non-CSS/non-MD files verified under 420 LOC.

## 5. Reusable Engineering Pattern

When designing list customization or priority rules in macOS utility software:
1. **Never use `NSAlert` with text fields for structured lists:** Use an `NSPanel` with a view-based `NSTableView` containing icons and titles.
2. **Provide "Capture Current State" affordances:** The highest user efficiency comes from snapshotting the user's active workspace rather than requiring manual reconstruction.
3. **Offer dual reordering mechanisms:** Always pair drag-and-drop with keyboard shortcuts and Move Up/Down buttons to guarantee accessibility across trackpads, mice, and assistive technologies.
