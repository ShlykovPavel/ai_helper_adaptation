# TunnelGuard Settings Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore TunnelGuard settings in the new unified Coucou Flow window (`FlowHub`) introduced by the upstream fork update, ensuring full sidebar visibility, routing, hero theming, and island navigation.

**Architecture:** Upstream replaced the legacy `SettingsView` window with `FlowHub` (`Coucou window`), which embeds sections of `SettingsView` through `HubPage.notchPages`. Integrating TunnelGuard requires extending `HubPage` in `FlowHub.swift`, registering its metadata (title, icon, subtitle, settings section), adding hero theme and Mochis in `FlowHubMochis.swift`, updating island card navigation in `IslandViewContent.swift`, and adding unit test verification.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Xcode (`xcodebuild`), bash.

**Spec:** User request to analyze and fix the disappearance of TunnelGuard settings after merging upstream fork changes that introduced the new Coucou window.

## Global Constraints
- Target macOS deployment: macOS 15.0+ (Sequoia or later).
- Preserve existing `SettingsView.swift` logic and bindings (`tunnelGuardSection`, `@AppStorage("tunnelGuard.*")`).
- Keep all existing `HubPage` cases and pages intact without regressing Flow or Notch pages.
- Ensure build succeeds cleanly (`xcodebuild`) and existing test suite passes.

## Review Focus
- Sidebar presence: `TunnelGuard` appears in the "NOTCH" group of the `Coucou` window sidebar with icon `shield.checkered` and color `#30D158`.
- Deep linking & routing: `HubPage.forSettings("tunnelGuard")` returns `.tunnelGuard`, and `openSettingsFromNotification` with `"tunnelGuard"` directly activates the TunnelGuard tab.
- Embedded rendering: `SettingsView(embeddedSection: "tunnelGuard")` correctly displays all 5 GroupBoxes (Status, Kill-Switch, Power Guard, Protected Apps, Audit/Simulation).
- Notch Island integration: Clicking "Настройки" in `TunnelGuardShieldCardView` opens the Coucou window on the TunnelGuard page.
- Test suite integrity: Bash scripts handle empty cache arrays under `set -u`, and new unit tests verify `HubPage` contracts.

---

### Task 1: Fix Bash Test Scripts Unbound Array Expansion

**Files:**
- Modify: `scripts/test-tunnelguard-phase1-safe.sh`
- Modify: `scripts/test-tunnelguard-phase2-safe.sh`
- Modify: `scripts/test-tunnelguard-phase3-safe.sh`
- Modify: `scripts/test-tunnelguard-watchdog.sh`

**Interfaces:**
- Consumes: `CACHE_ARGS` array in test scripts.
- Produces: Clean execution under `set -euo pipefail` regardless of cache directory existence.

- [ ] **Step 1: Replace `${CACHE_ARGS[@]}` with `${CACHE_ARGS[@]+"${CACHE_ARGS[@]}"}`**
Update lines where `${CACHE_ARGS[@]}` is invoked so that empty arrays do not trigger `unbound variable` error under bash `set -u`.

- [ ] **Step 2: Run `make test-tunnelguard-safe` and verify no unbound variable errors**
Run: `make test-tunnelguard-safe`
Expected: All tests execute without bash variable errors.

---

### Task 2: Add HubPage Unit Tests for TunnelGuard

**Files:**
- Create: `tests/HubPageTunnelGuardTests.swift`

**Interfaces:**
- Consumes: `HubPage` enum and static methods.
- Produces: Automated verification of `HubPage.notchPages` containing `.tunnelGuard`, title, symbol, and section routing.

- [ ] **Step 1: Write the failing test in `tests/HubPageTunnelGuardTests.swift`**
```swift
import Foundation

// Verifies that HubPage has .tunnelGuard registered in notchPages and routing
func testHubPageTunnelGuardIntegration() {
    assert(HubPage.notchPages.contains(.tunnelGuard), "HubPage.notchPages must contain .tunnelGuard")
    assert(HubPage.tunnelGuard.settingsSection == "tunnelGuard", "settingsSection for .tunnelGuard must be 'tunnelGuard'")
    assert(HubPage.forSettings("tunnelGuard") == .tunnelGuard, "HubPage.forSettings('tunnelGuard') must return .tunnelGuard")
    assert(HubPage.tunnelGuard.title == "TunnelGuard", "title must be 'TunnelGuard'")
    assert(HubPage.tunnelGuard.symbol == "shield.checkered", "symbol must be 'shield.checkered'")
    print("✅ testHubPageTunnelGuardIntegration passed")
}

testHubPageTunnelGuardIntegration()
```

- [ ] **Step 2: Verify test fails before implementation**
Run: `swiftc tests/HubPageTunnelGuardTests.swift NotchBuddy/Sources/App/FlowHub.swift -o /tmp/hub-test`
Expected: FAIL with `type 'HubPage' has no member 'tunnelGuard'`.

---

### Task 3: Register TunnelGuard in FlowHub and FlowHubMochis

**Files:**
- Modify: `NotchBuddy/Sources/App/FlowHub.swift:7-125`
- Modify: `NotchBuddy/Sources/App/FlowHubMochis.swift:235-268`

**Interfaces:**
- Consumes: `HubPage`, `HubHeroTheme`.
- Produces: `.tunnelGuard` case in `HubPage`, sidebar item, subtitle, and hero banner styling.

- [ ] **Step 1: Add `.tunnelGuard` to `HubPage` and its properties in `FlowHub.swift`**
1. Add `tunnelGuard` to `enum HubPage`:
   `case general, pills, agents, chat, integrations, voice, shortcuts, tunnelGuard`
2. Add `.tunnelGuard` to `HubPage.notchPages`:
   `static let notchPages: [HubPage] = [.general, .pills, .agents, .chat, .integrations, .voice, .shortcuts, .tunnelGuard]`
3. Add `case .tunnelGuard: return "tunnelGuard"` in `settingsSection`.
4. Add `case .tunnelGuard: return "TunnelGuard"` in `title`.
5. Add `case .tunnelGuard: return "shield.checkered"` in `symbol`.
6. Add `case .tunnelGuard: return String(localized: "hub.notch.tunnelguard", defaultValue: "Kill-switch, аварийный мониторинг и защита агентского трафика")` in `notchSubtitle`.

- [ ] **Step 2: Add `.tunnelGuard` theme in `FlowHubMochis.swift`**
In `HubHeroTheme.of(_ page: HubPage)`:
```swift
case .tunnelGuard:
    return .init(color: Color(hex: "#30D158"), cast: [m("#30D158", 58, 0.2, outfit: .sunglasses), m("#F5F6F8", 48, 0.8)])
```

- [ ] **Step 3: Run the unit test to verify it passes**
Run: `swiftc tests/HubPageTunnelGuardTests.swift NotchBuddy/Sources/App/FlowHub.swift -o /tmp/hub-test && /tmp/hub-test`
Expected: `✅ testHubPageTunnelGuardIntegration passed`.

---

### Task 4: Connect Island Card "Настройки" to TunnelGuard Page

**Files:**
- Modify: `NotchBuddy/Sources/App/IslandViewContent.swift:260-266`

**Interfaces:**
- Consumes: Notification `.openFullSettings` with object `"tunnelGuard"`.
- Produces: Direct navigation from the notch shield card to the TunnelGuard settings tab in the Coucou window.

- [ ] **Step 1: Update `TunnelGuardShieldCardView` settings button**
Replace:
```swift
Button("Настройки") { state.view = .settings }
```
With:
```swift
Button("Настройки") {
    NotificationCenter.default.post(name: .openFullSettings, object: "tunnelGuard")
}
```

---

### Task 5: End-to-End Build and Verification

**Files:**
- Whole project verification

- [ ] **Step 1: Build the full project with `xcodebuild`**
Run: `make build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Run the full safe test suite**
Run: `make test-tunnelguard-safe`
Expected: All Swift and Python tests pass.
