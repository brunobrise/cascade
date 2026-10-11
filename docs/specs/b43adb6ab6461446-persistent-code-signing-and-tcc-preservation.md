---
date: 2026-10-11
title: Persistent Code Signing and TCC Permission Preservation Specification
---

# Persistent Code Signing and TCC Permission Preservation Specification

## Problem and Goal

Cascade requires macOS Accessibility (`kTCCServiceAccessibility`) permissions to inspect and manipulate application windows. Under macOS Transparency, Consent, and Control (TCC), granted permissions are cryptographically anchored to an application's **Designated Requirement (DR)** stored inside `/Library/Application Support/com.apple.TCC/TCC.db`.

Previous installations suffered from recurring permission loss ("when new install, need to set permissions again"):
1. **Ad-Hoc `cdhash` Invalidation:** When binaries are signed ad-hoc (`codesign -s -`), macOS cannot bind the permission to a certificate authority. It falls back to binding the Designated Requirement to the exact SHA-256 hash of the compiled Mach-O binary (`designated => cdhash H"..."`). Any recompile, update, version bump, or new release changes the binary hash, causing `tccd` to immediately revoke Accessibility trust (`kAXErrorAPIDisabled -25211`).
2. **Zombie TCC Interface State:** In macOS System Settings, the Accessibility toggle frequently remains visually active ("blue"), while the system daemon denies API access, misleading users and forcing manual deletion and re-addition via the `-` and `+` buttons.
3. **Dual Install Path Collision:** Build tools historically copied `Cascade.app` to both `~/Applications/Cascade.app` and `/Applications/Cascade.app`, confusing LaunchServices and creating conflicting TCC client records.
4. **Gatekeeper App Translocation:** Downloads carrying `com.apple.quarantine` execute from temporary randomized read-only mount points (`/private/var/folders/.../AppTranslocation/...`), preventing persistent TCC identity matching.

The goal of this specification is to:
1. Ensure `Cascade.app` and `cascade` CLI are permanently signed with an auto-provisioned local cryptographic identity (`Cascade Code Signing`) valid for 10 years (3,650 days).
2. Anchor the Designated Requirement to `identifier "com.brunobrise.cascade" and certificate root = H"..."`, completely eliminating `cdhash` dependency.
3. Enforce single-path installation (canonical `/Applications` if writable, else `~/Applications`) and purge duplicate bundles.
4. Strip quarantine extended attributes to guarantee direct execution without App Translocation.

## Technical Specification

### 1. Persistent Identity Auto-Provisioning (`tools/setup_signing_cert.sh` & `install.sh`)

When building or installing without an existing Apple Developer ID:
1. Query `security find-identity -v -p codesigning`.
2. If `Cascade Code Signing` or `Apple Development` is absent:
   - Generate a 2048-bit RSA private key and self-signed X.509 certificate with:
     - `CN = Cascade Code Signing`
     - `O = Bruno BriSe Local Development`
     - `basicConstraints = critical, CA:TRUE`
     - `keyUsage = critical, digitalSignature, keyCertSign, cRLSign`
     - `extendedKeyUsage = critical, codeSigning`
   - Import into `~/Library/Keychains/login.keychain-db` with PKCS#12 payload.
   - Authorize `/usr/bin/codesign` via `security set-key-partition-list` to prevent interactive keychain authorization dialogues.
   - Mark trusted for `codeSign` policy via `security add-trusted-cert`.

### 2. Designated Requirement Verification

The compiled bundle's Designated Requirement must satisfy:
$$\text{DR} = \text{identifier "com.brunobrise.cascade"} \land \text{certificate root} = H"..."$$
Contrasted with the flawed ad-hoc requirement:
$$\text{DR}_{\text{adhoc}} = \text{cdhash } H"..."$$

Because the root certificate hash is fixed across all local rebuilds and updates, subsequent installations preserve Accessibility trust permanently.

### 3. Canonical Installation Path & Conflict Cleanup

Installation targets must enforce a single canonical destination:
- If `/Applications` is writable:
  - Destination: `/Applications/Cascade.app`
  - Purge target: `rm -rf ~/Applications/Cascade.app`
- If `/Applications` is not writable:
  - Destination: `~/Applications/Cascade.app`
  - Purge target: `rm -rf /Applications/Cascade.app 2>/dev/null || true`
- Execute LaunchServices registration:
  `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -r <destination>`
- Strip quarantine:
  `xattr -cr <destination>`

## Acceptance Criteria

- [ ] `security find-identity` detects `Cascade Code Signing` in login keychain.
- [ ] `codesign -d -r- build/Cascade.app` outputs requirement anchored to certificate root without `cdhash`.
- [ ] `install.sh` auto-provisions `Cascade Code Signing` if missing before signing.
- [ ] `Makefile` auto-provisions `Cascade Code Signing` if missing before signing.
- [ ] Rebuilding or reinstalling does not revoke Accessibility trust in `AXIsProcessTrusted()`.
- [ ] Only one `Cascade.app` bundle exists across `/Applications` and `~/Applications`.
- [ ] All unit and signing tests pass.
