---
date: 2026-10-11
title: Update Check and Notification Engine Success Story
---

# Update Check and Notification Engine Success Story

## Context and Problem

Cascade provides high-performance macOS window management across multiple displays with mathematically guaranteed unoccluded click tabs. As the tool iterates, users need clear, non-intrusive awareness of bug fixes and feature releases.

Previous manual update checks suffered from several severe friction points common to macOS developer utilities:
1. **TCC Permission Revocation on Installer Update:** [`install.sh#L101`](file:///Users/chainsona/Code/src/github.com/brunobrise/cascade/install.sh#L101) signed installed bundles with ad-hoc signatures (`codesign -s -`), which changed the Designated Requirement Mach-O code directory hash (`cdhash`) upon rebuilding or updating. Consequently, macOS TCC revoked Accessibility authorization, breaking window manipulation until manual system settings re-authorization.
2. **Terminal Pipeline Pollution:** Typical CLI updaters pollute `stdout` with release banners, which breaks downstream Unix pipes (`cascade --list | grep ...`).
3. **Execution Latency:** Synchronous network checks on the CLI hot path (`cascade --apply`) introduce hundreds of milliseconds of latency and hang in offline environments.
4. **API Rate Limiting & Private Repos:** The GitHub REST API enforces a strict 60 req/hr rate limit on unauthenticated calls, and returns HTTP 404 for private repositories.
5. **Privacy Alarm:** Window managers linking heavy telemetry frameworks trigger firewall warnings (Little Snitch, LuLu), destroying user trust.

## Solution

We designed and implemented a unified, lightweight update checking and notification engine (`UpdateChecker`) in native Objective-C with zero external dependencies:

1. **Zero-Cost Release Resolution:**
   - Evaluates releases using an HTTP `HEAD` request to `https://github.com/brunobrise/cascade/releases/latest` with redirect following disabled. The HTTP 302 `Location` header is parsed directly to extract the latest release tag (e.g., `v0.24.0`), consuming 0 REST API rate limit quota and transferring less than 1KB.
   - Supports explicit `GITHUB_TOKEN` / `GH_TOKEN` environment variables and `gh release view` CLI fallback to seamlessly work with private repositories during development.
2. **Strict SemVer Integer Triple Parsing:**
   - Replaced fragile ASCII string comparisons with numeric integer triple comparison (`major.minor.patch`). Eliminates ASCII sorting bugs where `"0.23.10" < "0.23.4"`.
3. **Two-Tier 24-Hour Caching & Throttling:**
   - Atomic disk cache in `~/Library/Caches/com.brunobrise.cascade/update_state.json`.
   - Network requests are throttled to at most once per 24 hours (0ms latency on hot path).
   - CLI update notices on `stderr` are throttled to at most once per 24 hours, completely eliminating repetitive terminal spam.
4. **Context-Aware Non-Intrusive Presentation:**
   - **CLI:** `--check-update` flag for manual checks. Passive check prints exclusively to `stderr`, strictly checks `isatty(STDERR_FILENO)`, and is silenced when `CI=true` or `CASCADE_NO_UPDATE_CHECK=1`. Detects install origin (`brew upgrade cascade` vs `git pull && make install` vs `install.sh`).
   - **Status Bar App:** Adds non-intrusive status item `✨ Update Available: vX.Y.Z...` opening release notes, and a manual "Check for Updates..." alert dialog.
   - **Settings Modal:** Includes `Automatically check for updates daily` checkbox and interactive `Check Now...` button with inline status.
5. **Installer Code-Signing Preservation:**
   - Updated [`install.sh`](file:///Users/chainsona/Code/src/github.com/brunobrise/cascade/install.sh) to dynamically detect `Cascade Code Signing` or `Apple Development` identities, matching [`Makefile`](file:///Users/chainsona/Code/src/github.com/brunobrise/cascade/Makefile). Updates installed via `install.sh` preserve the cryptographic Designated Requirement and maintain continuous Accessibility permissions.

## Verification & Results

- **Unit Tests:** Added [`tests/test_update_checker.m`](file:///Users/chainsona/Code/src/github.com/brunobrise/cascade/tests/test_update_checker.m) covering SemVer integer comparison, multi-digit patch edge cases (`0.23.10` > `0.23.4`), state serialization round-trip, TTL evaluation, throttle logic, and install origin detection.
- **CLI Verification:**
  - Ran `cascade --check-update`: Returned clean status with zero blocking.
  - Ran simulated update on `cascade --plan`: Displayed context-aware notice on first run, remained completely silent on subsequent runs within 24 hours.
  - Tested pipe safety: Piped output to `grep` with zero leakage into `stdout`.
- **GUI Verification:**
  - Compiled and validated `test_settings` and `test_ignore` suites with `UpdateChecker.o`.
  - Confirmed non-blocking asynchronous UI dispatch.

## Reusable Engineering Patterns

- **Zero-Cost Release Head Inspection:** Using HTTP `HEAD` against `github.com/.../releases/latest` to read the `Location` header is the optimal, rate-limit-free pattern for open-source GitHub release tracking.
- **Execution-Safe CLI Notice Delivery:** Route all CLI update notices to `stderr`, guard with `isatty(STDERR_FILENO)`, check `CI` environment variable, and throttle notification timestamps in local cache.
- **Identity-Anchored Updating:** Never allow an installer or updater to drop code signing certificates to ad-hoc (`-s -`) on macOS applications requiring TCC permissions. Always query and re-apply the persistent identity.
