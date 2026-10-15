# Universal Package & Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide an automated packaging workflow for Coucou (NotchBuddy) producing a Universal binary (Apple Silicon + Intel), ad-hoc codesigning, a double-clickable Gatekeeper unlock helper, and a clear user instruction in both `.dmg` and `.zip` distribution archives.

**Architecture:** A dedicated packaging script (`scripts/package.sh`) orchestrates the universal Release build (`ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO`), applies ad-hoc codesigning, bundles user instructions and a helper `.command` script, and creates DMG and ZIP archives in `dist/`. Makefile targets `package` and `dist` provide one-command access.

**Tech Stack:** Bash, Xcode (`xcodebuild`, `codesign`, `lipo`), `hdiutil`, `ditto`, GNU Make.

**Spec:** User request to build a universal package for Intel and M-series chips with instructions for users having launch issues.

## Global Constraints
- Target macOS deployment: macOS 15.0+ (Sequoia or later).
- Universal binary architectures: `arm64` and `x86_64`.
- No reliance on paid Apple Developer certificate (use ad-hoc codesigning: `codesign --force --deep -s -`).
- Preserve all existing tests and Makefile targets intact.

## Review Focus
- Binary architecture verification: ensure both `arm64` and `x86_64` are present in the final binary via `lipo -info`.
- Gatekeeper unlock script usability: ensure `Разблокировать_Coucou.command` is executable (`chmod +x`) and correctly targets `/Applications/Coucou.app`.
- DMG and ZIP generation: ensure DMG mounts cleanly or handles environments where `hdiutil` creates UDZO images.
- Clean working directory: `dist/` and build staging artifacts are properly created and added to `.gitignore` if needed.
- Ad-hoc codesigning validity: verify `codesign -v --deep` passes.

---

### Task 1: Enforce Universal Binary in Release Build

**Files:**
- Modify: `scripts/build-release.sh`
- Test: Verify with `lipo -info` / `file`

**Interfaces:**
- Consumes: Xcode scheme `NotchBuddy`, configuration `Release`.
- Produces: Mach-O universal binary containing `arm64` and `x86_64`.

- [ ] **Step 1: Update `scripts/build-release.sh` to enforce universal architecture**
Add `ARCHS="arm64 x86_64"` and `ONLY_ACTIVE_ARCH=NO` to `xcodebuild` arguments. Support optional custom `CONFIGURATION_BUILD_DIR` environment variable or parameter.

- [ ] **Step 2: Run release build and verify dual architecture**
Run: `./scripts/build-release.sh`
Run: `lipo -info NotchBuddy/build/Build/Products/Release/Coucou.app/Contents/MacOS/Coucou` (or DerivedData location)
Expected: `Architectures in the fat file: ... are: x86_64 arm64`

---

### Task 2: Create Distribution Packaging Script (`scripts/package.sh`)

**Files:**
- Create: `scripts/package.sh`
- Test: Run `./scripts/package.sh` and inspect `dist/`

**Interfaces:**
- Consumes: `scripts/build-release.sh` output.
- Produces: `dist/Coucou-<version>-macOS-Universal.dmg` and `dist/Coucou-<version>-macOS-Universal.zip` containing:
  - `Coucou.app` (ad-hoc signed)
  - `ИНСТРУКЦИЯ.txt` (detailed troubleshooting & installation guide)
  - `Разблокировать_Coucou.command` (double-clickable script to remove quarantine)

- [ ] **Step 1: Implement `scripts/package.sh`**
Implement staging folder preparation, release build invocation into staging, ad-hoc codesigning with `codesign --force --deep -s -`, creation of `ИНСТРУКЦИЯ.txt` and `Разблокировать_Coucou.command`, and packaging into DMG (via `hdiutil`) and ZIP (via `ditto`).

- [ ] **Step 2: Make `scripts/package.sh` executable and test package generation**
Run: `chmod +x scripts/package.sh && ./scripts/package.sh`
Expected: Output archives created in `dist/` with zero exit code.

- [ ] **Step 3: Verify package contents and signatures**
Inspect archives and check `lipo -info` and `codesign -v --deep` on the packaged app.

---

### Task 3: Makefile Integration, .gitignore, and Documentation

**Files:**
- Modify: `Makefile`
- Modify: `.gitignore`
- Modify: `docs/tunnelguard/BUILD_MACOS.md`

**Interfaces:**
- Consumes: `scripts/package.sh`.
- Produces: `make package` and `make dist` targets, updated documentation.

- [ ] **Step 1: Add `dist/` to `.gitignore`**
Ensure distribution archives in `dist/` are not tracked by git.

- [ ] **Step 2: Add `package` and `dist` targets to `Makefile`**
Add `.PHONY: package dist` and wire them to `./scripts/package.sh`.

- [ ] **Step 3: Update `docs/tunnelguard/BUILD_MACOS.md`**
Document the distribution packaging workflow and troubleshooting steps for colleagues.

- [ ] **Step 4: Run verification**
Run: `make -n package`
Run: `make test`
Verify all tests pass and `dist/` contains valid packages.
