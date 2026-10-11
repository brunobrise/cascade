---
date: 2026-10-11
type: success
status: validated
related_specs:
  - ../specs/b43adb6ab6461446-persistent-code-signing-and-tcc-preservation.md
---

# TCC Permission Preservation & Auto-Provisioned Signing Success Story

## Context and Root Cause Analysis

Users reported that upon running a new install or update ("when new install, need to set permissions again"), macOS Accessibility authorization was repeatedly invalidated, breaking global window shortcuts and status bar window cascades until manual re-authorization in System Settings.

Deep investigation across `TCC.db`, Mach-O headers, and code signature requirements revealed three compounded causes:

1. **Passive Fallback to Ad-Hoc `cdhash` Requirements:**
   - Although `tools/setup_signing_cert.sh` existed in the repository, neither `install.sh`, `Makefile`, nor `package.sh` automatically provisioned the certificate if it was missing from the user's keychain.
   - When `security find-identity -v -p codesigning` returned 0 valid identities, all build and install scripts silently fell back to ad-hoc signing (`codesign -s -`).
   - Ad-hoc signatures lack a public-key identity root, forcing macOS `tccd` to anchor the Designated Requirement to the exact compiled binary hash:
     $$\text{DR}_{\text{adhoc}} = \text{cdhash } H\text{"ae16e3323348e62047128d27e2f0c789e0bbee43"}$$
   - Any recompile, release update, or installation changed the Mach-O binary bytes. When the updated app launched, `tccd` evaluated the stored requirement, detected a `cdhash` mismatch, and immediately revoked Accessibility trust (`kAXErrorAPIDisabled -25211`).

2. **Dual-Installation Collision:**
   - `Makefile` previously installed `Cascade.app` into `~/Applications/Cascade.app` AND, if `/Applications` was writable, also into `/Applications/Cascade.app`.
   - Having two distinct bundle instances sharing bundle identifier `com.brunobrise.cascade` caused LaunchServices registration race conditions and conflicting TCC client records.

3. **Gatekeeper App Translocation:**
   - Pre-packaged bundles downloaded from the internet retained the `com.apple.quarantine` extended attribute, causing macOS to run the app from randomized read-only paths (`/private/var/folders/.../AppTranslocation/...`), preventing persistent TCC client matching.

## Solution

We implemented an automated, self-healing code signing and single-path deployment architecture:

1. **Auto-Provisioning in `install.sh` and `Makefile`:**
   - Both `install.sh` and `Makefile` now query `security find-identity`. If neither `Cascade Code Signing` nor `Apple Development` is present, the script dynamically generates a 2048-bit RSA key and self-signed certificate (`Cascade Code Signing`) valid for 10 years, imports it into `login.keychain-db`, sets key partitions to allow silent `/usr/bin/codesign` execution, and marks it trusted for `codeSign`.
   - The resulting Designated Requirement permanently anchors to the certificate root:
     $$\text{DR}_{\text{cert}} = \text{identifier "com.brunobrise.cascade" } \land \text{ certificate root} = H\text{"b43adb6ab646144637f9333c5f7c0ba19321febb"}$$
   - Because the root hash is constant across all subsequent rebuilds, updates, and releases, macOS TCC evaluates the updated application as satisfying the original authorization rule without prompting or revoking permissions.

2. **Single Canonical Installation Path:**
   - If `/Applications` is writable, `make install` and `install.sh` install exclusively to `/Applications/Cascade.app` and purge any legacy duplicate in `~/Applications/Cascade.app`.
   - If `/Applications` is not writable, they install exclusively to `~/Applications/Cascade.app` and purge `/Applications/Cascade.app`.

3. **Quarantine Stripping & LaunchServices Refresh:**
   - `xattr -cr` is executed on both the CLI binary and the `.app` bundle upon installation.
   - `lsregister -f -r` is called to immediately update the LaunchServices database.

4. **Automated Verification Suite:**
   - Updated [`tests/test_signing.m`](file:///Users/chainsona/Code/src/github.com/brunobrise/cascade/tests/test_signing.m) with `testPersistentIdentityRequirement` which queries `codesign -d -r-` and asserts that the Designated Requirement is anchored to `certificate root` or `certificate leaf` and contains **no** `cdhash` fallback.

## Verification & Results

- **Test Suite:** Ran `make test`. All 12 test suites passed, and `testPersistentIdentityRequirement` confirmed:
  ```text
  === Running Cascade Code Signing Verification Tests ===
  Running testBundleSignatureIntegrity...
    Designated Requirement: designated => identifier "com.brunobrise.cascade" and certificate root = H"b43adb6ab646144637f9333c5f7c0ba19321febb"
    [PASS] testBundleSignatureIntegrity passed.
  Running testPersistentIdentityRequirement...
    [PASS] Confirmed persistent identity requirement anchor (NO cdhash).
  === All Code Signing Tests Passed Successfully! ===
  ```
- **Install Verification:** Ran `make install`:
  - Verified `/Users/chainsona/Applications/Cascade.app` purged.
  - Verified single instance at `/Applications/Cascade.app`.
  - Verified `codesign -d -r- /Applications/Cascade.app` has `certificate root = H"b43adb6ab646144637f9333c5f7c0ba19321febb"`.
  - Verified `codesign -d -r- ~/.local/bin/cascade` has `certificate root = H"b43adb6ab646144637f9333c5f7c0ba19321febb"`.
  - Launched app and verified accessibility permissions remain intact without re-prompting.

## Reusable Engineering Patterns

- **Auto-Provisioning Over Passive Fallback:** When a developer tool requires persistent macOS security capabilities (TCC, keychain, network filters), never silently fall back to ad-hoc signing (`-s -`). Detect the absence of an identity and auto-generate a local 10-year self-signed certificate.
- **Root-Anchored Designated Requirements:** Verify via `codesign -d -r-` that the Designated Requirement contains `certificate root = H"..."` and zero `cdhash` references before distributing or installing macOS utilities requiring TCC access.
- **Single-Path Discipline:** Ensure installers actively remove duplicates from alternative paths (`~/Applications` vs `/Applications`) to prevent LaunchServices confusion and multiple conflicting entries in `TCC.db`.
