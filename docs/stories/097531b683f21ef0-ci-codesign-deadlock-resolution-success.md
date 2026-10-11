---
date: 2026-10-11
type: success
status: validated
related_specs:
  - ../specs/b43adb6ab6461446-persistent-code-signing-and-tcc-preservation.md
---

# CI Codesign Deadlock Resolution & Release Pipeline Success Story

## Context and Failure Discovery

During the release tagging of `v0.25.0`, the automated GitHub Actions CI release workflow (`release.yml`, run `38129881285`) hung indefinitely on Step 4 (`Generate App Iconset & ICNS`). Concurrently, the user inquired why the running Cascade app was not detecting the new `v0.25.0` update.

Deep investigation across GitHub Actions runner logs and Makefile execution targets revealed two interconnected root causes:

1. **Headless Keychain Authorization Deadlock:**
   - In commit `683f21e`, `Makefile` incorporated an immediate fallback:
     `_INIT_CERT := $(shell ./tools/setup_signing_cert.sh >/dev/null 2>&1)`
   - On local macOS developer machines with active user sessions, `tools/setup_signing_cert.sh` silently imported and partitioned the `Cascade Code Signing` key.
   - On ephemeral GitHub Actions macOS runners (`macos-latest`), no interactive GUI session or unlocked user login keychain exists. When `security set-key-partition-list` executed, it blocked indefinitely waiting for an interactive password prompt or terminal confirmation.
   - Because `$(shell ...)` executes during Makefile parsing, any `make` invocation (such as `make icon` in Step 4) froze the entire CI job.
   - Consequently, Step 7 (`action-gh-release`) was never reached, and `v0.25.0` was never published to GitHub Releases.

2. **Client-Side Cache & Private Repository Fallback:**
   - The running application (`v0.24.0`) had cached release status with a 24-hour TTL in `~/Library/Caches/com.brunobrise/cascade/update_state.json`.
   - Furthermore, because `brunobrise/cascade` is a private repository, `UpdateChecker` relied on `gh release view`, which correctly reported `v0.24.0` as the latest release since GitHub had not yet received `v0.25.0` assets.
   - Since `0.24.0` matched the running version, no update notification was surfaced.

## Solution

1. **CI Environment Bypass Guards:**
   - Updated `tools/setup_signing_cert.sh`:
     ```bash
     if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
         echo "CI environment detected. Skipping local keychain certificate generation."
         exit 0
     fi
     ```
   - Updated `Makefile`:
     Wrapped `_INIT_CERT` and `Cascade Code Signing` auto-provisioning in `ifeq ($(CI),) / ifeq ($(GITHUB_ACTIONS),)` blocks, defaulting immediately to ad-hoc signing (`-s -`) on CI.
   - Updated `tools/package.sh`:
     Bypassed interactive keychain setup when `CI` or `GITHUB_ACTIONS` is set.
   - Updated `tests/test_signing.m`:
     Added `ciEnv` check to skip local root-certificate assertions when executing on ephemeral CI runners.

2. **Pipeline Restart:**
   - Cancelled hanging run `38129881285`.
   - Pushed fix commit `097531b` to `main`.
   - Re-pointed and force-pushed annotated tag `v0.25.0` to trigger a clean release build.

3. **Cache Invalidation:**
   - Cleared `~/Library/Caches/com.brunobrise/cascade/update_state.json` to allow immediate polling of the freshly published `v0.25.0` release.

## Verification & Results

- Verified `make icon` and `make test` complete in under 5 seconds with `CI=true`.
- Verified `test_signing` gracefully reports `[SKIP] CI environment active`.
- GitHub Actions workflow resumed and published release assets cleanly.
