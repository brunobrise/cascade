---
date: 2026-10-17
type: success
status: validated
---

# Application Window Grouping Invariant Success Story

## Context

User requested a strict grouping guarantee across the entire window management lifecycle:
> *"Ensure windows from same app are grouped no matter the mode. ultrathink twice, don't hesitate to challenge yourself, if needed! /ultrathink"*

Following deep `/ultrathink` analysis and adversarial stress-testing, we recognized that individual window sorting in MRU and Spatial modes leads to interleaved window sequences (e.g. `[Safari 1, Terminal 1, Safari 2, Terminal 2]`). This created cognitive fragmentation when scanning unoccluded tabs or navigating between multi-window apps.

## Mathematical Invariant & Architecture

We established and proved the **Application Contiguity Invariant**:
$$\forall i < j, \quad A(o_i) = A(o_j) \implies \forall k \in [i, j], \quad A(o_k) = A(o_i)$$
Windows belonging to the same application are guaranteed to form a contiguous cluster without interruption by windows from other applications.

### Implementation Architecture
1. **Partitioning (`CascadeAppGroup`):** Windows are partitioned into application groups by `appName` (case-insensitive).
2. **Representative Metric Key ($K_{app}$):**
   - **MRU:** $K_{MRU} = \min_{w \in G_A}(w.zRank)$ (most recently focused app is placed first).
   - **Spatial:** $K_{Spatial} = \min_{w \in G_A}(w.currentFrame.origin.x)$ (leftmost app is placed first).
   - **Alphabetical:** $K_{Alpha} = A.appName$ (alphabetical ordering).
   - **Custom:** $K_{Pref} = rankForApp(A.appName, preferredOrder)$, tie-breaking unlisted apps by $\min(zRank)$.
   - **Fractal:** $K_{Pref} = rankForApp$, or initial input appearance.
3. **Intra-Group Ordering:**
   - Frontmost or leftmost window of the app sits at the head of the app cluster.
4. **Lifecycle Preservation:**
   - In `preservingOrderFrom:`, when a new window opens for an existing app, it is inserted immediately adjacent to its sibling windows rather than appended at the end of the cascade.
   - An idempotent stabilization pass guarantees contiguity across arbitrary lifecycle states.

## Verification & Test Results

All modes were verified with targeted unit tests in `tests/test_engine.m` and `tests/test_fractal.m`:
- `testAppGroupingMRU`: Verified that interleaved windows `[A1, B1, A2, C1, B2]` sort cleanly into `[B1, B2, A1, A2, C1]`.
- `testAppGroupingSpatial`: Verified spatial grouping `[X1, X2, Y1, Y2, Z1]` based on leftmost origin.
- `testAppGroupingCustomWithUnlistedApps`: Verified preferred apps group first, followed by unlisted apps grouped by recent use.
- `testAppGroupingOrderPreservationOnNewWindow`: Verified new app window insertion adjacent to existing app windows in `preservingOrderFrom:`.
- `testFractalAppGrouping`: Verified contiguous app grouping in Fractal layout.
- All 13 test suites pass cleanly with 0 warnings or errors.
