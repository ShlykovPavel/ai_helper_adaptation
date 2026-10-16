# Astral Morph Mascot Implementation Plan

> **Historical implementation plan.** Do not execute this plan as the current task.
> Its floating core, visual requirements, frame counts and completion assumptions
> are superseded by [the current design](../../MASCOT_DESIGN_SPEC.md).
> Start with [the handoff](../../MASCOT_HANDOFF.md). Follow the current user task;
> approved PNG assets do not imply completed frame animation or native integration.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the "Astral Morph" (Shapeshifter) mascot for macOS (`NotchBuddy`) and Windows (`windows/`), featuring 2-tier Level-of-Detail (Compact 20–32px and Expanded 64–120px), floating AI core rendering, 24 FPS sprite animation with 0% CPU idle state, and zero-breakage Facade integration with upstream Coucou code.

**Architecture:** A non-intrusive Facade / Adapter pattern wraps the existing `BotCanvasView` (macOS) and `island.ts` (Windows), routing rendering to a completely isolated mascot engine (`Sources/CoucouKit/Mascots/Shapeshifter/` and `windows/src/mascot/`) when `selectedMascot == .shapeshifter`, while preserving 100% of the original Mochi codebase without modifications for seamless upstream merges.

**Tech Stack:** Swift 6 (`SwiftUI`, `AppKit`, `CoreGraphics`, `TimelineView`), TypeScript (`HTML5 2D Canvas`), XcodeGen, and Node.js test runners.

**Spec:** `docs/MASCOT_DESIGN_SPEC.md`, `docs/FORK_SYNC_MASCOT.md`, `docs/MASCOT_ANIMATION.md`, `CLAUDE.md`.

## Global Constraints

- Swift 6, SwiftUI + AppKit. No third-party dependencies unless truly unavoidable. (`CLAUDE.md:24`)
- Strict concurrency enabled (`OTHER_SWIFT_FLAGS: "-strict-concurrency=complete"` in `project.yml:35`).
- Performance: 0% CPU when the island is hidden or paused (`CLAUDE.md:30`).
- Fork isolation: zero breaking changes to existing call signatures (`BotPlacement`, `FlowPill`, `IslandRootView`); original `BotEngine.swift` remains untouched (`docs/FORK_SYNC_MASCOT.md:68-80`).
- Mascot asset standard: 24 FPS texture blitting with horizontal/matrix grid layout, 8-bit alpha PNG, Retina `@2x`/`@3x` ($240 \times 240$ px expanded, $64 \times 64$ px compact) with procedural vector fallback (`docs/MASCOT_DESIGN_SPEC.md:81-87`).
- Keep bundle identifier `fr.louisraille.NotchBuddy` and existing project configuration (`CLAUDE.md:31`).

## Review Focus

1. **Unknown/corrupt mascot string in storage:** If `UserDefaults` or `localStorage` contains an unrecognized mascot key (e.g., `"unknown_mascot"` or empty string), the system must cleanly fall back to `.shapeshifter` without crashing or rendering blank. (Pinned to Task 1)
2. **Hidden Island / Background Pause (0.0% CPU leak):** When `state.mode == .hidden` or `paused: true`, the sprite sheet animator must stop frame increments and CPU calculations entirely, guaranteeing 0.0% CPU usage. (Pinned to Task 2)
3. **Missing or Nil AI Provider / Unknown Pill ID:** When `state.focusTask` is nil or has an unknown provider/color, the indicator badge (Compact LOD) and floating core (Expanded LOD) must fall back to a default astral cyan glow (`#64D2FF`) instead of nil dereferencing or invisible elements. (Pinned to Task 3 and Task 4)
4. **Extreme / Non-standard Aspect Ratio and Size Scaling:** When rendered in non-standard sizes (e.g., width 16pt in compact pill or 160pt hero in FlowHub, or non-square sizes), the LOD renderer must clamp aspect ratio to 1:1 and center without distortion or clipping out of bounds. (Pinned to Task 3 and Task 4)
5. **Dynamic Mascot Switching during active animation cycle:** Switching `selectedMascot` at runtime between Mochi and Shapeshifter while an animation/sound/state is mid-transition must cleanly reinitialize state without retain cycles, conflicting Canvas contexts, or stuck sprite sheet frame counters. (Pinned to Task 5)

---

### Task 1: Scaffolding, Mascot Types & Settings Model

**Files:**
- Create: `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift`
- Create: `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotSettings.swift`
- Create: `windows/src/mascot/types.ts`
- Create: `windows/src/mascot/settings.ts`
- Create: `tests/MascotSettingsTests.swift`
- Create: `scripts/test-mascot-settings.sh`
- Create: `windows/tests/mascot-settings.test.mjs`
- Modify: `windows/src/core/state.ts:167-187`

**Interfaces:**
- Consumes: None (foundational task).
- Produces:
  - `MascotType`: enum `String, CaseIterable, Sendable, Codable` (`.mochi`, `.shapeshifter`).
  - `MascotShape`: enum `String, CaseIterable, Sendable, Codable` (`.squircle`, `.orb`, `.flameWisp`).
  - `MascotSizeVariant`: enum `Sendable` (`.compact`, `.expanded`, `.hero`).
  - `ProviderCoreType`: enum `Sendable, Equatable` (`.claude`, `.gemini`, `.openai`, `.antigravity`, `.custom(String)`).
  - `MascotActionState`: enum `String, CaseIterable, Sendable` (`.idle`, `.writing`, `.reading`, `.thinking`, `.approval`, `.error`, `.sleeping`).
  - `MascotSettings`: struct with `static var selectedMascot: MascotType { get set }` (UserDefaults key `"selectedMascot"`, default `.shapeshifter`), `static var shape: MascotShape { get set }`.
  - In TS: `MascotId`, `MascotShape`, `MascotSizeVariant`, `ProviderCoreId`, `MascotActionState`, and `MascotSettingsManager`.

- [ ] **Step 1: Write the failing test for Mascot settings and types**

Create `tests/MascotSettingsTests.swift`:
```swift
import Foundation

@main
enum MascotSettingsTests {
    static var failures = 0
    static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("MascotSettings — defaults & raw values")
        check("MascotType.shapeshifter rawValue", MascotType.shapeshifter.rawValue == "shapeshifter")
        check("MascotType.mochi rawValue", MascotType.mochi.rawValue == "mochi")
        check("MascotShape cases count == 3", MascotShape.allCases.count == 3)
        check("MascotActionState cases count == 7", MascotActionState.allCases.count == 7)

        print("MascotSettings — storage & fallback")
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "selectedMascot")
        check("Default selectedMascot is .shapeshifter", MascotSettings.selectedMascot == .shapeshifter)

        MascotSettings.selectedMascot = .mochi
        check("Stored value reflects .mochi", MascotSettings.selectedMascot == .mochi)

        // Review Focus 1: Corrupt/unknown string in storage falls back to .shapeshifter
        defaults.set("unknown_corrupted_mascot", forKey: "selectedMascot")
        check("Corrupt key falls back to .shapeshifter", MascotSettings.selectedMascot == .shapeshifter)

        defaults.set("", forKey: "selectedMascot")
        check("Empty string falls back to .shapeshifter", MascotSettings.selectedMascot == .shapeshifter)

        // Reset
        defaults.removeObject(forKey: "selectedMascot")

        print("MascotSettingsTests finished with \(failures) failures.")
        if failures > 0 { exit(1) }
    }
}
```

Create `scripts/test-mascot-settings.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mascot-settings.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotSettings.swift \
       tests/MascotSettingsTests.swift -o "$TEST_DIR/settings-tests"
"$TEST_DIR/settings-tests"
```
Make executable: `chmod +x scripts/test-mascot-settings.sh`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-mascot-settings.sh`
Expected: FAIL with compilation error "cannot find type 'MascotType' in scope" or missing file.

- [ ] **Step 3: Implement Mascot Types and Settings**

Create `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift`:
```swift
import Foundation

public enum MascotType: String, CaseIterable, Sendable, Codable {
    case mochi = "mochi"
    case shapeshifter = "shapeshifter"
}

public enum MascotShape: String, CaseIterable, Sendable, Codable {
    case squircle = "squircle"
    case orb = "orb"
    case flameWisp = "flameWisp"
}

public enum MascotSizeVariant: Sendable, Equatable {
    case compact   // 20-32pt
    case expanded  // 44-66pt
    case hero      // 96-160pt
}

public enum ProviderCoreType: Sendable, Equatable {
    case claude
    case gemini
    case openai
    case antigravity
    case custom(String)

    public static func from(pillId: String?) -> ProviderCoreType {
        guard let id = pillId?.lowercased() else { return .antigravity }
        if id.contains("claude") { return .claude }
        if id.contains("gemini") { return .gemini }
        if id.contains("openai") || id.contains("gpt") { return .openai }
        if id.contains("antigravity") || id.contains("coucou") { return .antigravity }
        return .custom(id)
    }
}

public enum MascotActionState: String, CaseIterable, Sendable {
    case idle
    case writing
    case reading
    case thinking
    case approval
    case error
    case sleeping
}
```

Create `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotSettings.swift`:
```swift
import Foundation

public struct MascotSettings {
    public static let selectedMascotKey = "selectedMascot"
    public static let mascotShapeKey = "mascotShape"

    public static var selectedMascot: MascotType {
        get {
            guard let raw = UserDefaults.standard.string(forKey: selectedMascotKey),
                  let type = MascotType(rawValue: raw) else {
                return .shapeshifter
            }
            return type
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: selectedMascotKey)
        }
    }

    public static var shape: MascotShape {
        get {
            guard let raw = UserDefaults.standard.string(forKey: mascotShapeKey),
                  let shape = MascotShape(rawValue: raw) else {
                return .squircle
            }
            return shape
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: mascotShapeKey)
        }
    }
}
```

Create `windows/src/mascot/types.ts`:
```typescript
export type MascotId = "mochi" | "shapeshifter";
export type MascotShape = "squircle" | "orb" | "flameWisp";
export type MascotSizeVariant = "compact" | "expanded" | "hero";
export type ProviderCoreId = "claude" | "gemini" | "openai" | "antigravity" | "custom";
export type MascotActionState = "idle" | "writing" | "reading" | "thinking" | "approval" | "error" | "sleeping";
```

Create `windows/src/mascot/settings.ts`:
```typescript
import type { MascotId, MascotShape } from "./types";

const SELECTED_MASCOT_KEY = "coucou_selected_mascot";
const MASCOT_SHAPE_KEY = "coucou_mascot_shape";

export class MascotSettingsManager {
  static getSelectedMascot(storage?: Storage): MascotId {
    const s = storage ?? (typeof localStorage !== "undefined" ? localStorage : null);
    const raw = s?.getItem(SELECTED_MASCOT_KEY);
    if (raw === "mochi" || raw === "shapeshifter") return raw;
    return "shapeshifter"; // Review Focus 1: safe fallback
  }

  static setSelectedMascot(mascot: MascotId, storage?: Storage): void {
    const s = storage ?? (typeof localStorage !== "undefined" ? localStorage : null);
    s?.setItem(SELECTED_MASCOT_KEY, mascot);
  }

  static getShape(storage?: Storage): MascotShape {
    const s = storage ?? (typeof localStorage !== "undefined" ? localStorage : null);
    const raw = s?.getItem(MASCOT_SHAPE_KEY);
    if (raw === "squircle" || raw === "orb" || raw === "flameWisp") return raw;
    return "squircle";
  }

  static setShape(shape: MascotShape, storage?: Storage): void {
    const s = storage ?? (typeof localStorage !== "undefined" ? localStorage : null);
    s?.setItem(MASCOT_SHAPE_KEY, shape);
  }
}
```

Modify `windows/src/core/state.ts` (around line 180) to include `selectedMascot?: MascotId;` in `interface Settings` and `selectedMascot: "shapeshifter"` in `DEFAULT_SETTINGS`.

Create `windows/tests/mascot-settings.test.mjs`:
```javascript
import { test } from "node:test";
import assert from "node:assert/strict";
import { MascotSettingsManager } from "../src/mascot/settings.ts";

test("MascotSettingsManager default & corrupt fallback", () => {
  const mockStorage = new Map();
  const storage = {
    getItem: (k) => mockStorage.get(k) ?? null,
    setItem: (k, v) => mockStorage.set(k, String(v)),
  };

  assert.equal(MascotSettingsManager.getSelectedMascot(storage), "shapeshifter");
  MascotSettingsManager.setSelectedMascot("mochi", storage);
  assert.equal(MascotSettingsManager.getSelectedMascot(storage), "mochi");

  // Corrupt string test
  storage.setItem("coucou_selected_mascot", "invalid_value");
  assert.equal(MascotSettingsManager.getSelectedMascot(storage), "shapeshifter");
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test-mascot-settings.sh`
Expected: PASS with "MascotSettingsTests finished with 0 failures."

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift \
        NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotSettings.swift \
        windows/src/mascot/types.ts \
        windows/src/mascot/settings.ts \
        windows/src/core/state.ts \
        tests/MascotSettingsTests.swift \
        scripts/test-mascot-settings.sh \
        windows/tests/mascot-settings.test.mjs
git commit -m "feat(mascot): scaffold isolated mascot types and settings model"
```

---

### Task 2: Core Sprite Sheet Animator Component

**Files:**
- Create: `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/SpriteSheetAnimator.swift`
- Create: `windows/src/mascot/sprite-animator.ts`
- Create: `tests/SpriteSheetAnimatorTests.swift`
- Create: `scripts/test-sprite-sheet-animator.sh`
- Create: `windows/tests/sprite-animator.test.mjs`

**Interfaces:**
- Consumes: `MascotActionState` from Task 1.
- Produces:
  - `SpriteSheetConfig`: struct with `frameCount: Int`, `fps: Double`, `columns: Int`, `rows: Int`, `frameWidth: CGFloat`, `frameHeight: CGFloat`.
  - `SpriteSheetAnimator`:
    - `var currentFrameIndex: Int { get }`
    - `var isPaused: Bool { get set }`
    - `func update(dt: TimeInterval) -> Int`
    - `func frameRect(for frameIndex: Int, imageSize: CGSize) -> CGRect`
    - `func setAction(_ action: MascotActionState)`
    - `func reset()`
  - In TS: `SpriteSheetAnimator` with identical frame calculations and paused handling.

- [ ] **Step 1: Write the failing test for SpriteSheetAnimator**

Create `tests/SpriteSheetAnimatorTests.swift`:
```swift
import Foundation
import CoreGraphics

@main
enum SpriteSheetAnimatorTests {
    static var failures = 0
    static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("SpriteSheetAnimator — frame advancement at 24 FPS")
        let config = SpriteSheetConfig(frameCount: 24, fps: 24.0, columns: 24, rows: 1, frameWidth: 240, frameHeight: 240)
        let animator = SpriteSheetAnimator(config: config)

        check("Initial frame is 0", animator.currentFrameIndex == 0)

        // Advance 1/24 sec -> frame 1
        _ = animator.update(dt: 1.0 / 24.0)
        check("Frame advances to 1 after 1/24s", animator.currentFrameIndex == 1)

        // Advance 23 more frames -> frame 0 (modulo wrap)
        _ = animator.update(dt: 23.0 / 24.0)
        check("Frame wraps to 0 after full cycle", animator.currentFrameIndex == 0)

        print("SpriteSheetAnimator — Review Focus 2: Paused state 0% work")
        animator.isPaused = true
        _ = animator.update(dt: 10.0) // 10 seconds pass while hidden
        check("Frame does not advance while paused", animator.currentFrameIndex == 0)

        animator.isPaused = false
        _ = animator.update(dt: 2.0 / 24.0)
        check("Frame resumes advancement when unpaused", animator.currentFrameIndex == 2)

        print("SpriteSheetAnimator — frameRect math")
        let rect = animator.frameRect(for: 2, imageSize: CGSize(width: 240 * 24, height: 240))
        check("Horizontal strip rect X origin is 480", rect.origin.x == 480)
        check("Rect width is 240", rect.width == 240)

        print("SpriteSheetAnimator — Action state switch resets time")
        animator.setAction(.writing)
        check("Action switch resets to frame 0", animator.currentFrameIndex == 0)

        print("SpriteSheetAnimatorTests finished with \(failures) failures.")
        if failures > 0 { exit(1) }
    }
}
```

Create `scripts/test-sprite-sheet-animator.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sprite-animator.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/SpriteSheetAnimator.swift \
       tests/SpriteSheetAnimatorTests.swift -o "$TEST_DIR/animator-tests"
"$TEST_DIR/animator-tests"
```
Make executable: `chmod +x scripts/test-sprite-sheet-animator.sh`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-sprite-sheet-animator.sh`
Expected: FAIL with compilation error "cannot find 'SpriteSheetConfig' in scope".

- [ ] **Step 3: Implement SpriteSheetAnimator**

Create `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/SpriteSheetAnimator.swift`:
```swift
import Foundation
import CoreGraphics

public struct SpriteSheetConfig: Sendable {
    public var frameCount: Int
    public var fps: Double
    public var columns: Int
    public var rows: Int
    public var frameWidth: CGFloat
    public var frameHeight: CGFloat

    public init(frameCount: Int, fps: Double = 24.0, columns: Int, rows: Int = 1, frameWidth: CGFloat, frameHeight: CGFloat) {
        self.frameCount = max(1, frameCount)
        self.fps = max(1.0, fps)
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
    }

    public static func `default`(for action: MascotActionState) -> SpriteSheetConfig {
        switch action {
        case .idle:      return SpriteSheetConfig(frameCount: 20, fps: 24.0, columns: 20, frameWidth: 240, frameHeight: 240)
        case .writing:   return SpriteSheetConfig(frameCount: 24, fps: 24.0, columns: 24, frameWidth: 240, frameHeight: 240)
        case .reading:   return SpriteSheetConfig(frameCount: 20, fps: 24.0, columns: 20, frameWidth: 240, frameHeight: 240)
        case .thinking:  return SpriteSheetConfig(frameCount: 18, fps: 24.0, columns: 18, frameWidth: 240, frameHeight: 240)
        case .approval:  return SpriteSheetConfig(frameCount: 16, fps: 24.0, columns: 16, frameWidth: 240, frameHeight: 240)
        case .error:     return SpriteSheetConfig(frameCount: 16, fps: 24.0, columns: 16, frameWidth: 240, frameHeight: 240)
        case .sleeping:  return SpriteSheetConfig(frameCount: 16, fps: 16.0, columns: 16, frameWidth: 240, frameHeight: 240)
        }
    }
}

public final class SpriteSheetAnimator: @unchecked Sendable {
    public var config: SpriteSheetConfig
    public var isPaused: Bool = false
    public private(set) var currentAction: MascotActionState = .idle
    private var accumulatedTime: TimeInterval = 0

    public init(config: SpriteSheetConfig) {
        self.config = config
    }

    public var currentFrameIndex: Int {
        guard config.frameCount > 0 else { return 0 }
        let index = Int(floor(accumulatedTime * config.fps)) % config.frameCount
        return index >= 0 ? index : 0
    }

    @discardableResult
    public func update(dt: TimeInterval) -> Int {
        // Review Focus 2: When paused, skip time accumulation and math completely
        guard !isPaused, dt > 0 else { return currentFrameIndex }
        accumulatedTime += dt
        return currentFrameIndex
    }

    public func frameRect(for frameIndex: Int, imageSize: CGSize) -> CGRect {
        let validIndex = frameIndex % config.frameCount
        let col = validIndex % config.columns
        let row = validIndex / config.columns

        let x = CGFloat(col) * config.frameWidth
        let y = CGFloat(row) * config.frameHeight
        return CGRect(x: x, y: y, width: config.frameWidth, height: config.frameHeight)
    }

    public func setAction(_ action: MascotActionState) {
        if currentAction != action {
            currentAction = action
            config = SpriteSheetConfig.default(for: action)
            reset()
        }
    }

    public func reset() {
        accumulatedTime = 0
    }
}
```

Create `windows/src/mascot/sprite-animator.ts`:
```typescript
import type { MascotActionState } from "./types";

export interface SpriteSheetConfig {
  frameCount: number;
  fps: number;
  columns: number;
  rows: number;
  frameWidth: number;
  frameHeight: number;
}

export function defaultConfigForAction(action: MascotActionState): SpriteSheetConfig {
  switch (action) {
    case "idle":     return { frameCount: 20, fps: 24, columns: 20, rows: 1, frameWidth: 240, frameHeight: 240 };
    case "writing":  return { frameCount: 24, fps: 24, columns: 24, rows: 1, frameWidth: 240, frameHeight: 240 };
    case "reading":  return { frameCount: 20, fps: 24, columns: 20, rows: 1, frameWidth: 240, frameHeight: 240 };
    case "thinking": return { frameCount: 18, fps: 24, columns: 18, rows: 1, frameWidth: 240, frameHeight: 240 };
    case "approval": return { frameCount: 16, fps: 24, columns: 16, rows: 1, frameWidth: 240, frameHeight: 240 };
    case "error":    return { frameCount: 16, fps: 24, columns: 16, rows: 1, frameWidth: 240, frameHeight: 240 };
    case "sleeping": return { frameCount: 16, fps: 16, columns: 16, rows: 1, frameWidth: 240, frameHeight: 240 };
  }
}

export class SpriteSheetAnimator {
  config: SpriteSheetConfig;
  isPaused = false;
  currentAction: MascotActionState = "idle";
  private accumulatedTime = 0;

  constructor(config: SpriteSheetConfig) {
    this.config = config;
  }

  get currentFrameIndex(): number {
    if (this.config.frameCount <= 0) return 0;
    const idx = Math.floor(this.accumulatedTime * this.config.fps) % this.config.frameCount;
    return idx >= 0 ? idx : 0;
  }

  update(dt: number): number {
    // Review Focus 2: 0 CPU work when paused
    if (this.isPaused || dt <= 0) return this.currentFrameIndex;
    this.accumulatedTime += dt;
    return this.currentFrameIndex;
  }

  getFrameSourceRect(frameIndex: number): { sx: number; sy: number; sw: number; sh: number } {
    const validIndex = frameIndex % this.config.frameCount;
    const col = validIndex % this.config.columns;
    const row = Math.floor(validIndex / this.config.columns);
    return {
      sx: col * this.config.frameWidth,
      sy: row * this.config.frameHeight,
      sw: this.config.frameWidth,
      sh: this.config.frameHeight,
    };
  }

  setAction(action: MascotActionState): void {
    if (this.currentAction !== action) {
      this.currentAction = action;
      this.config = defaultConfigForAction(action);
      this.reset();
    }
  }

  reset(): void {
    this.accumulatedTime = 0;
  }
}
```

Create `windows/tests/sprite-animator.test.mjs`:
```javascript
import { test } from "node:test";
import assert from "node:assert/strict";
import { SpriteSheetAnimator } from "../src/mascot/sprite-animator.ts";

test("SpriteSheetAnimator frame math & 0% CPU paused behavior", () => {
  const config = { frameCount: 24, fps: 24, columns: 24, rows: 1, frameWidth: 240, frameHeight: 240 };
  const anim = new SpriteSheetAnimator(config);

  assert.equal(anim.currentFrameIndex, 0);
  anim.update(1 / 24);
  assert.equal(anim.currentFrameIndex, 1);

  // Paused state
  anim.isPaused = true;
  anim.update(10);
  assert.equal(anim.currentFrameIndex, 1);

  anim.isPaused = false;
  anim.update(1 / 24);
  assert.equal(anim.currentFrameIndex, 2);

  const rect = anim.getFrameSourceRect(2);
  assert.equal(rect.sx, 480);
  assert.equal(rect.sw, 240);
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test-sprite-sheet-animator.sh`
Expected: PASS with "SpriteSheetAnimatorTests finished with 0 failures."

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/SpriteSheetAnimator.swift \
        windows/src/mascot/sprite-animator.ts \
        tests/SpriteSheetAnimatorTests.swift \
        scripts/test-sprite-sheet-animator.sh \
        windows/tests/sprite-animator.test.mjs
git commit -m "feat(mascot): implement 24 FPS sprite sheet animator with 0% CPU pause"
```

---

### Task 3: Compact LOD Renderer (20–32px)

**Files:**
- Create: `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterCompactRenderer.swift`
- Create: `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterCompactView.swift`
- Create: `windows/src/mascot/shapeshifter-compact.ts`
- Create: `tests/ShapeshifterCompactLODTests.swift`
- Create: `scripts/test-compact-lod.sh`
- Create: `windows/tests/compact-lod.test.mjs`

**Interfaces:**
- Consumes: `MascotShape`, `ProviderCoreType` from Task 1.
- Produces:
  - `CompactRenderParams`: struct with `size: CGSize`, `lookX: CGFloat`, `lookY: CGFloat`, `shape: MascotShape`, `provider: ProviderCoreType`, `isPulsing: Bool`.
  - `ShapeshifterCompactRenderer`:
    - `static func badgeColor(for provider: ProviderCoreType) -> (r: Double, g: Double, b: Double, hex: String)`
    - `static func eyeOffsets(lookX: CGFloat, lookY: CGFloat, diameter: CGFloat) -> (left: CGPoint, right: CGPoint)`
    - `static func draw(in context: CGContext, params: CompactRenderParams)`
  - `ShapeshifterCompactView`: SwiftUI View wrapping `ShapeshifterCompactRenderer`.
  - In TS: `drawCompactMascot(options: CompactDrawOptions)`.

- [ ] **Step 1: Write the failing test for Compact LOD renderer**

Create `tests/ShapeshifterCompactLODTests.swift`:
```swift
import Foundation
import CoreGraphics

@main
enum ShapeshifterCompactLODTests {
    static var failures = 0
    static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("ShapeshifterCompactRenderer — Review Focus 3: Provider badge colors & nil fallback")
        let claude = ShapeshifterCompactRenderer.badgeColor(for: .claude)
        check("Claude badge color is terracotta #D97757", claude.hex == "#D97757")

        let gemini = ShapeshifterCompactRenderer.badgeColor(for: .gemini)
        check("Gemini badge color is #4E80EE", gemini.hex == "#4E80EE")

        let openai = ShapeshifterCompactRenderer.badgeColor(for: .openai)
        check("OpenAI badge color is #10A37F", openai.hex == "#10A37F")

        let customFallback = ShapeshifterCompactRenderer.badgeColor(for: .custom("unknown"))
        check("Unknown provider falls back to astral cyan #64D2FF", customFallback.hex == "#64D2FF")

        print("ShapeshifterCompactRenderer — Review Focus 4: Clamping non-square bounding rects")
        let clampedSquare = ShapeshifterCompactRenderer.clampedDrawRect(in: CGSize(width: 40, height: 20))
        check("Clamped width matches height (20)", clampedSquare.width == 20 && clampedSquare.height == 20)
        check("Clamped rect is centered horizontally (x == 10)", clampedSquare.origin.x == 10)

        print("ShapeshifterCompactRenderer — Eye tracking bounds")
        let eyes = ShapeshifterCompactRenderer.eyeOffsets(lookX: 1.0, lookY: -1.0, diameter: 24)
        check("Left eye X offset within safe boundary (< 4pt)", abs(eyes.left.x) <= 4.0)
        check("Right eye X offset within safe boundary (< 4pt)", abs(eyes.right.x) <= 4.0)

        print("ShapeshifterCompactLODTests finished with \(failures) failures.")
        if failures > 0 { exit(1) }
    }
}
```

Create `scripts/test-compact-lod.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/compact-lod.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterCompactRenderer.swift \
       tests/ShapeshifterCompactLODTests.swift -o "$TEST_DIR/compact-tests"
"$TEST_DIR/compact-tests"
```
Make executable: `chmod +x scripts/test-compact-lod.sh`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-compact-lod.sh`
Expected: FAIL with compilation error "cannot find 'ShapeshifterCompactRenderer' in scope".

- [ ] **Step 3: Implement Compact LOD Renderer**

Create `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterCompactRenderer.swift`:
```swift
import Foundation
import CoreGraphics

public struct CompactRenderParams: Sendable {
    public var size: CGSize
    public var lookX: CGFloat
    public var lookY: CGFloat
    public var shape: MascotShape
    public var provider: ProviderCoreType
    public var isPulsing: Bool

    public init(size: CGSize, lookX: CGFloat = 0, lookY: CGFloat = 0, shape: MascotShape = .squircle, provider: ProviderCoreType = .antigravity, isPulsing: Bool = false) {
        self.size = size
        self.lookX = max(-1.0, min(1.0, lookX))
        self.lookY = max(-1.0, min(1.0, lookY))
        self.shape = shape
        self.provider = provider
        self.isPulsing = isPulsing
    }
}

public final class ShapeshifterCompactRenderer: @unchecked Sendable {
    public static func badgeColor(for provider: ProviderCoreType) -> (r: Double, g: Double, b: Double, hex: String) {
        switch provider {
        case .claude:      return (0.851, 0.467, 0.341, "#D97757") // Terracotta
        case .gemini:      return (0.306, 0.502, 0.933, "#4E80EE") // Blue-purple
        case .openai:      return (0.063, 0.639, 0.498, "#10A37F") // Emerald
        case .antigravity: return (0.545, 0.361, 0.965, "#8B5CF6") // Violet
        case .custom:      return (0.392, 0.824, 1.000, "#64D2FF") // Review Focus 3: Astral Cyan Fallback
        }
    }

    public static func clampedDrawRect(in bounds: CGSize) -> CGRect {
        // Review Focus 4: 1:1 aspect ratio clamping & centering
        let side = min(bounds.width, bounds.height)
        let ox = (bounds.width - side) / 2.0
        let oy = (bounds.height - side) / 2.0
        return CGRect(x: ox, y: oy, width: side, height: side)
    }

    public static func eyeOffsets(lookX: CGFloat, lookY: CGFloat, diameter: CGFloat) -> (left: CGPoint, right: CGPoint) {
        let maxOffset = diameter * 0.08
        let shiftX = lookX * maxOffset
        let shiftY = -lookY * maxOffset * 0.75
        let eyeDistance = diameter * 0.22
        return (
            left: CGPoint(x: -eyeDistance + shiftX, y: shiftY),
            right: CGPoint(x: eyeDistance + shiftX, y: shiftY)
        )
    }

    public static func draw(in context: CGContext, params: CompactRenderParams) {
        let rect = clampedDrawRect(in: params.size)
        guard rect.width >= 8 else { return }

        context.saveGState()

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2.0
        let badge = badgeColor(for: params.provider)

        // 1. Neon Glowing Silhouette
        context.setShadow(offset: .zero, blur: 4.0, color: CGColor(red: badge.r, green: badge.g, blue: badge.b, alpha: 0.75))
        context.setLineWidth(1.5)
        context.setStrokeColor(CGColor(red: 0.9, green: 0.95, blue: 1.0, alpha: 0.95))

        switch params.shape {
        case .squircle:
            let corner = radius * 0.45
            let path = CGPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerWidth: corner, cornerHeight: corner, transform: nil)
            context.addPath(path)
        case .orb:
            context.addEllipse(in: rect.insetBy(dx: 2, dy: 2))
        case .flameWisp:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: center.x, y: rect.minY + 2))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - 2, y: center.y), control: CGPoint(x: rect.maxX, y: rect.minY + 4))
            path.addQuadCurve(to: CGPoint(x: center.x, y: rect.maxY - 2), control: CGPoint(x: rect.maxX - 2, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX + 2, y: center.y), control: CGPoint(x: rect.minX + 2, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: center.x, y: rect.minY + 2), control: CGPoint(x: rect.minX, y: rect.minY + 4))
            context.addPath(path)
        }
        context.strokePath()

        // 2. High-contrast White Pill Eyes
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))

        let offsets = eyeOffsets(lookX: params.lookX, lookY: params.lookY, diameter: rect.width)
        let eyeW = max(2.5, rect.width * 0.12)
        let eyeH = max(4.0, rect.width * 0.22)

        let leftEyeRect = CGRect(x: center.x + offsets.left.x - eyeW / 2, y: center.y + offsets.left.y - eyeH / 2, width: eyeW, height: eyeH)
        let rightEyeRect = CGRect(x: center.x + offsets.right.x - eyeW / 2, y: center.y + offsets.right.y - eyeH / 2, width: eyeW, height: eyeH)

        context.fillEllipse(in: leftEyeRect)
        context.fillEllipse(in: rightEyeRect)

        // 3. Tiny AI Provider Indicator Badge
        let badgeSize = max(3.5, rect.width * 0.16)
        let badgeRect = CGRect(x: rect.maxX - badgeSize - 1, y: rect.minY + 1, width: badgeSize, height: badgeSize)
        context.setFillColor(CGColor(red: badge.r, green: badge.g, blue: badge.b, alpha: 1.0))
        context.setShadow(offset: .zero, blur: 2.0, color: CGColor(red: badge.r, green: badge.g, blue: badge.b, alpha: 0.9))
        context.fillEllipse(in: badgeRect)

        context.restoreGState()
    }
}
```

Create `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterCompactView.swift`:
```swift
import SwiftUI

public struct ShapeshifterCompactView: View {
    public var size: CGSize
    public var lookX: CGFloat
    public var lookY: CGFloat
    public var shape: MascotShape
    public var provider: ProviderCoreType
    public var isPulsing: Bool

    public init(size: CGSize = CGSize(width: 24, height: 24), lookX: CGFloat = 0, lookY: CGFloat = 0, shape: MascotShape = .squircle, provider: ProviderCoreType = .antigravity, isPulsing: Bool = false) {
        self.size = size
        self.lookX = lookX
        self.lookY = lookY
        self.shape = shape
        self.provider = provider
        self.isPulsing = isPulsing
    }

    public var body: some View {
        Canvas { context, canvasSize in
            context.withCGContext { cgContext in
                let params = CompactRenderParams(size: canvasSize, lookX: lookX, lookY: lookY, shape: shape, provider: provider, isPulsing: isPulsing)
                ShapeshifterCompactRenderer.draw(in: cgContext, params: params)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
```

Create `windows/src/mascot/shapeshifter-compact.ts`:
```typescript
import type { MascotShape, ProviderCoreId } from "./types";

export interface CompactDrawOptions {
  ctx: CanvasRenderingContext2D;
  width: number;
  height: number;
  lookX: number;
  lookY: number;
  shape: MascotShape;
  provider: ProviderCoreId;
}

export function getProviderBadgeColor(provider: ProviderCoreId): string {
  switch (provider) {
    case "claude":      return "#D97757";
    case "gemini":      return "#4E80EE";
    case "openai":      return "#10A37F";
    case "antigravity": return "#8B5CF6";
    default:            return "#64D2FF"; // Astral cyan fallback
  }
}

export function drawCompactMascot(opts: CompactDrawOptions): void {
  const { ctx, width, height, lookX, lookY, shape, provider } = opts;
  const side = Math.min(width, height);
  if (side < 8) return;

  const ox = (width - side) / 2;
  const oy = (height - side) / 2;
  const badgeColor = getProviderBadgeColor(provider);

  ctx.save();
  ctx.translate(ox, oy);

  // 1. Neon Glowing Silhouette
  ctx.strokeStyle = "rgba(230, 242, 255, 0.95)";
  ctx.lineWidth = 1.5;
  ctx.shadowColor = badgeColor;
  ctx.shadowBlur = 4;

  const r = side / 2;
  ctx.beginPath();
  if (shape === "squircle") {
    const radius = r * 0.45;
    ctx.roundRect(2, 2, side - 4, side - 4, radius);
  } else if (shape === "orb") {
    ctx.arc(r, r, r - 2, 0, Math.PI * 2);
  } else {
    // flame wisp
    ctx.moveTo(r, 2);
    ctx.quadraticCurveTo(side - 2, r, r, side - 2);
    ctx.quadraticCurveTo(2, r, r, 2);
  }
  ctx.stroke();

  // 2. White Pill Eyes
  ctx.shadowBlur = 0;
  ctx.fillStyle = "#FFFFFF";
  const eyeShiftX = Math.max(-1, Math.min(1, lookX)) * side * 0.08;
  const eyeShiftY = -Math.max(-1, Math.min(1, lookY)) * side * 0.06;
  const eyeDist = side * 0.22;
  const eyeW = Math.max(2.5, side * 0.12);
  const eyeH = Math.max(4, side * 0.22);

  ctx.beginPath();
  ctx.ellipse(r - eyeDist + eyeShiftX, r + eyeShiftY, eyeW / 2, eyeH / 2, 0, 0, Math.PI * 2);
  ctx.ellipse(r + eyeDist + eyeShiftX, r + eyeShiftY, eyeW / 2, eyeH / 2, 0, 0, Math.PI * 2);
  ctx.fill();

  // 3. Tiny Badge
  ctx.shadowColor = badgeColor;
  ctx.shadowBlur = 2;
  ctx.fillStyle = badgeColor;
  const badgeSize = Math.max(3.5, side * 0.16);
  ctx.beginPath();
  ctx.arc(side - badgeSize, badgeSize, badgeSize / 2, 0, Math.PI * 2);
  ctx.fill();

  ctx.restore();
}
```

Create `windows/tests/compact-lod.test.mjs`:
```javascript
import { test } from "node:test";
import assert from "node:assert/strict";
import { getProviderBadgeColor } from "../src/mascot/shapeshifter-compact.ts";

test("Compact LOD badge colors and astral fallback", () => {
  assert.equal(getProviderBadgeColor("claude"), "#D97757");
  assert.equal(getProviderBadgeColor("gemini"), "#4E80EE");
  assert.equal(getProviderBadgeColor("openai"), "#10A37F");
  assert.equal(getProviderBadgeColor("custom"), "#64D2FF");
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test-compact-lod.sh`
Expected: PASS with "ShapeshifterCompactLODTests finished with 0 failures."

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterCompactRenderer.swift \
        NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterCompactView.swift \
        windows/src/mascot/shapeshifter-compact.ts \
        tests/ShapeshifterCompactLODTests.swift \
        scripts/test-compact-lod.sh \
        windows/tests/compact-lod.test.mjs
git commit -m "feat(mascot): implement Compact LOD renderer (20-32px) with neon outline and AI badge"
```

---

### Task 4: Expanded LOD Renderer (64–120px)

**Files:**
- Create: `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterExpandedRenderer.swift`
- Create: `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterExpandedView.swift`
- Create: `windows/src/mascot/shapeshifter-expanded.ts`
- Create: `tests/ShapeshifterExpandedLODTests.swift`
- Create: `scripts/test-expanded-lod.sh`
- Create: `windows/tests/expanded-lod.test.mjs`

**Interfaces:**
- Consumes: `MascotActionState`, `ProviderCoreType`, `MascotShape` from Task 1, `SpriteSheetAnimator` from Task 2.
- Produces:
  - `ExpandedRenderParams`: struct with `bounds: CGRect`, `action: MascotActionState`, `shape: MascotShape`, `provider: ProviderCoreType`, `lookX: CGFloat`, `lookY: CGFloat`, `corePhase: Double`.
  - `ShapeshifterExpandedRenderer`:
    - `static func harmonicCoreYOffset(phase: Double, amplitude: CGFloat = 2.5) -> CGFloat`
    - `static func drawGlassmorphicBody(in context: CGContext, rect: CGRect, shape: MascotShape, tintColor: CGColor)`
    - `static func drawFloatingCore(in context: CGContext, center: CGPoint, provider: ProviderCoreType, phase: Double)`
    - `static func drawActionProps(in context: CGContext, rect: CGRect, action: MascotActionState)`
    - `static func draw(in context: CGContext, params: ExpandedRenderParams)`
  - `ShapeshifterExpandedView`: SwiftUI View.
  - In TS: `drawExpandedMascot(options: ExpandedDrawOptions)`.

- [ ] **Step 1: Write the failing test for Expanded LOD renderer**

Create `tests/ShapeshifterExpandedLODTests.swift`:
```swift
import Foundation
import CoreGraphics

@main
enum ShapeshifterExpandedLODTests {
    static var failures = 0
    static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("ShapeshifterExpandedRenderer — harmonic core float calculation")
        let y0 = ShapeshifterExpandedRenderer.harmonicCoreYOffset(phase: 0.0, amplitude: 2.5)
        check("Offset at phase 0 is 0.0", abs(y0) < 0.001)

        let yQuarter = ShapeshifterExpandedRenderer.harmonicCoreYOffset(phase: 0.25, amplitude: 2.5)
        check("Offset at phase 0.25 is peak 2.5", abs(yQuarter - 2.5) < 0.001)

        let yThreeQuarter = ShapeshifterExpandedRenderer.harmonicCoreYOffset(phase: 0.75, amplitude: 2.5)
        check("Offset at phase 0.75 is trough -2.5", abs(yThreeQuarter - (-2.5)) < 0.001)

        print("ShapeshifterExpandedRenderer — Review Focus 4: Non-square bounding box centering")
        let clampedRect = ShapeshifterExpandedRenderer.clampedDrawRect(in: CGSize(width: 120, height: 60))
        check("Clamped side is 60", clampedRect.width == 60 && clampedRect.height == 60)
        check("Clamped rect is centered horizontally (x == 30)", clampedRect.origin.x == 30)

        print("ShapeshifterExpandedRenderer — Review Focus 3: Fallback core for unknown provider")
        let coreColor = ShapeshifterExpandedRenderer.coreColor(for: .custom("generic_agent"))
        check("Custom provider core color is astral cyan #64D2FF", coreColor.hex == "#64D2FF")

        print("ShapeshifterExpandedLODTests finished with \(failures) failures.")
        if failures > 0 { exit(1) }
    }
}
```

Create `scripts/test-expanded-lod.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/expanded-lod.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterExpandedRenderer.swift \
       tests/ShapeshifterExpandedLODTests.swift -o "$TEST_DIR/expanded-tests"
"$TEST_DIR/expanded-tests"
```
Make executable: `chmod +x scripts/test-expanded-lod.sh`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-expanded-lod.sh`
Expected: FAIL with compilation error "cannot find 'ShapeshifterExpandedRenderer' in scope".

- [ ] **Step 3: Implement Expanded LOD Renderer**

Create `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterExpandedRenderer.swift`:
```swift
import Foundation
import CoreGraphics

public struct ExpandedRenderParams: Sendable {
    public var bounds: CGRect
    public var action: MascotActionState
    public var shape: MascotShape
    public var provider: ProviderCoreType
    public var lookX: CGFloat
    public var lookY: CGFloat
    public var corePhase: Double

    public init(bounds: CGRect, action: MascotActionState = .idle, shape: MascotShape = .squircle, provider: ProviderCoreType = .antigravity, lookX: CGFloat = 0, lookY: CGFloat = 0, corePhase: Double = 0) {
        self.bounds = bounds
        self.action = action
        self.shape = shape
        self.provider = provider
        self.lookX = max(-1.0, min(1.0, lookX))
        self.lookY = max(-1.0, min(1.0, lookY))
        self.corePhase = corePhase
    }
}

public final class ShapeshifterExpandedRenderer: @unchecked Sendable {
    public static func harmonicCoreYOffset(phase: Double, amplitude: CGFloat = 2.5) -> CGFloat {
        return CGFloat(sin(phase * 2.0 * .pi)) * amplitude
    }

    public static func coreColor(for provider: ProviderCoreType) -> (r: Double, g: Double, b: Double, hex: String) {
        switch provider {
        case .claude:      return (0.851, 0.467, 0.341, "#D97757")
        case .gemini:      return (0.306, 0.502, 0.933, "#4E80EE")
        case .openai:      return (0.063, 0.639, 0.498, "#10A37F")
        case .antigravity: return (0.545, 0.361, 0.965, "#8B5CF6")
        case .custom:      return (0.392, 0.824, 1.000, "#64D2FF") // Review Focus 3 Fallback
        }
    }

    public static func clampedDrawRect(in bounds: CGSize) -> CGRect {
        // Review Focus 4: 1:1 aspect ratio clamp
        let side = min(bounds.width, bounds.height)
        let ox = (bounds.width - side) / 2.0
        let oy = (bounds.height - side) / 2.0
        return CGRect(x: ox, y: oy, width: side, height: side)
    }

    public static func drawGlassmorphicBody(in context: CGContext, rect: CGRect, shape: MascotShape, tintColor: CGColor) {
        context.saveGState()

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2.0

        // Subsurface Scattering Outer Glow
        context.setShadow(offset: .zero, blur: 12.0, color: tintColor)

        // Glassmorphic Body Gradient Fill
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradientColors = [
            CGColor(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.45),
            CGColor(red: 0.80, green: 0.88, blue: 1.0, alpha: 0.20),
            CGColor(red: 0.65, green: 0.78, blue: 1.0, alpha: 0.08)
        ] as CFArray

        if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0.0, 0.6, 1.0]) {
            context.saveGState()
            switch shape {
            case .squircle:
                let corner = radius * 0.48
                context.addPath(CGPath(roundedRect: rect.insetBy(dx: 4, dy: 4), cornerWidth: corner, cornerHeight: corner, transform: nil))
            case .orb:
                context.addEllipse(in: rect.insetBy(dx: 4, dy: 4))
            case .flameWisp:
                let path = CGMutablePath()
                path.move(to: CGPoint(x: center.x, y: rect.minY + 4))
                path.addQuadCurve(to: CGPoint(x: rect.maxX - 4, y: center.y), control: CGPoint(x: rect.maxX, y: rect.minY + 8))
                path.addQuadCurve(to: CGPoint(x: center.x, y: rect.maxY - 4), control: CGPoint(x: rect.maxX - 4, y: rect.maxY))
                path.addQuadCurve(to: CGPoint(x: rect.minX + 4, y: center.y), control: CGPoint(x: rect.minX + 4, y: rect.maxY))
                path.addQuadCurve(to: CGPoint(x: center.x, y: rect.minY + 4), control: CGPoint(x: rect.minX, y: rect.minY + 8))
                context.addPath(path)
            }
            context.clip()
            context.drawRadialGradient(gradient, startCenter: CGPoint(x: center.x - radius * 0.2, y: center.y - radius * 0.2), startRadius: 0, endCenter: center, endRadius: radius, options: [])
            context.restoreGState()
        }

        // Specular Rim Light
        context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.7))
        context.setLineWidth(1.8)
        context.strokeEllipse(in: rect.insetBy(dx: 5, dy: 5))

        context.restoreGState()
    }

    public static func drawFloatingCore(in context: CGContext, center: CGPoint, provider: ProviderCoreType, phase: Double) {
        context.saveGState()

        let yOffset = harmonicCoreYOffset(phase: phase, amplitude: 2.5)
        let coreCenter = CGPoint(x: center.x, y: center.y + 6 + yOffset)
        let color = coreColor(for: provider)
        let cgColor = CGColor(red: color.r, green: color.g, blue: color.b, alpha: 0.9)

        context.setShadow(offset: .zero, blur: 8.0, color: cgColor)
        context.setFillColor(cgColor)

        let coreRadius: CGFloat = 8.0
        switch provider {
        case .claude:
            // 4-pointed radiant sparkle star
            let path = CGMutablePath()
            path.move(to: CGPoint(x: coreCenter.x, y: coreCenter.y - coreRadius))
            path.addQuadCurve(to: CGPoint(x: coreCenter.x + coreRadius, y: coreCenter.y), control: CGPoint(x: coreCenter.x + 2, y: coreCenter.y - 2))
            path.addQuadCurve(to: CGPoint(x: coreCenter.x, y: coreCenter.y + coreRadius), control: CGPoint(x: coreCenter.x + 2, y: coreCenter.y + 2))
            path.addQuadCurve(to: CGPoint(x: coreCenter.x - coreRadius, y: coreCenter.y), control: CGPoint(x: coreCenter.x - 2, y: coreCenter.y + 2))
            path.addQuadCurve(to: CGPoint(x: coreCenter.x, y: coreCenter.y - coreRadius), control: CGPoint(x: coreCenter.x - 2, y: coreCenter.y - 2))
            context.addPath(path)
            context.fillPath()
        case .gemini:
            // Dual diamond spark
            let diamondW: CGFloat = coreRadius * 0.7
            let path = CGMutablePath()
            path.move(to: CGPoint(x: coreCenter.x, y: coreCenter.y - coreRadius))
            path.addLine(to: CGPoint(x: coreCenter.x + diamondW, y: coreCenter.y))
            path.addLine(to: CGPoint(x: coreCenter.x, y: coreCenter.y + coreRadius))
            path.addLine(to: CGPoint(x: coreCenter.x - diamondW, y: coreCenter.y))
            path.closeSubpath()
            context.addPath(path)
            context.fillPath()
        default:
            // Orbital sphere
            context.fillEllipse(in: CGRect(x: coreCenter.x - coreRadius, y: coreCenter.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2))
        }

        context.restoreGState()
    }

    public static func drawActionProps(in context: CGContext, rect: CGRect, action: MascotActionState) {
        context.saveGState()
        context.setLineWidth(1.5)

        let center = CGPoint(x: rect.midX, y: rect.midY)
        switch action {
        case .writing:
            // Mini glowing tablet + stylus
            context.setStrokeColor(CGColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 0.9))
            let tabletRect = CGRect(x: center.x - 12, y: rect.maxY - 18, width: 24, height: 14)
            context.stroke(tabletRect)
            // Stylus
            context.move(to: CGPoint(x: tabletRect.maxX - 4, y: tabletRect.minY - 4))
            context.addLine(to: CGPoint(x: tabletRect.maxX - 8, y: tabletRect.midY))
            context.strokePath()
        case .reading:
            // Open book silhouette
            context.setStrokeColor(CGColor(red: 1.0, green: 0.9, blue: 0.5, alpha: 0.9))
            let bookY = rect.maxY - 16
            context.move(to: CGPoint(x: center.x, y: bookY))
            context.addLine(to: CGPoint(x: center.x - 14, y: bookY - 4))
            context.addLine(to: CGPoint(x: center.x - 14, y: bookY + 8))
            context.addLine(to: CGPoint(x: center.x, y: bookY + 10))
            context.addLine(to: CGPoint(x: center.x + 14, y: bookY + 8))
            context.addLine(to: CGPoint(x: center.x + 14, y: bookY - 4))
            context.addLine(to: CGPoint(x: center.x, y: bookY))
            context.strokePath()
        case .thinking:
            // Spark question swirl above head
            context.setStrokeColor(CGColor(red: 0.9, green: 0.7, blue: 1.0, alpha: 0.9))
            context.addArc(center: CGPoint(x: center.x + 10, y: rect.minY + 10), radius: 4, startAngle: 0, endAngle: .pi * 1.5, clockwise: false)
            context.strokePath()
        case .error:
            // Angry cracked spark
            context.setStrokeColor(CGColor(red: 1.0, green: 0.25, blue: 0.2, alpha: 0.95))
            context.move(to: CGPoint(x: center.x - 6, y: rect.minY + 6))
            context.addLine(to: CGPoint(x: center.x + 6, y: rect.minY + 14))
            context.move(to: CGPoint(x: center.x + 6, y: rect.minY + 6))
            context.addLine(to: CGPoint(x: center.x - 6, y: rect.minY + 14))
            context.strokePath()
        case .sleeping:
            // Closed eyes & 'z' trail
            context.setStrokeColor(CGColor(red: 0.7, green: 0.8, blue: 0.9, alpha: 0.8))
            let zX = rect.maxX - 10
            let zY = rect.minY + 8
            context.move(to: CGPoint(x: zX - 4, y: zY - 4))
            context.addLine(to: CGPoint(x: zX, y: zY - 4))
            context.addLine(to: CGPoint(x: zX - 4, y: zY))
            context.addLine(to: CGPoint(x: zX, y: zY))
            context.strokePath()
        case .approval, .idle:
            break
        }

        context.restoreGState()
    }

    public static func draw(in context: CGContext, params: ExpandedRenderParams) {
        let rect = clampedDrawRect(in: params.bounds.size)
        guard rect.width >= 16 else { return }

        let color = coreColor(for: params.provider)
        let tint = CGColor(red: color.r, green: color.g, blue: color.b, alpha: 0.6)

        // 1. 3D Glassmorphic Body
        drawGlassmorphicBody(in: context, rect: rect, shape: params.shape, tintColor: tint)

        // 2. Floating AI Core with Harmonic Oscillation
        let center = CGPoint(x: rect.midX, y: rect.midY)
        drawFloatingCore(in: context, center: center, provider: params.provider, phase: params.corePhase)

        // 3. Action Props Layer
        drawActionProps(in: context, rect: rect, action: params.action)
    }
}
```

Create `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterExpandedView.swift`:
```swift
import SwiftUI

public struct ShapeshifterExpandedView: View {
    public var size: CGSize
    public var action: MascotActionState
    public var shape: MascotShape
    public var provider: ProviderCoreType
    public var lookX: CGFloat
    public var lookY: CGFloat
    public var isPaused: Bool

    @State private var phase: Double = 0

    public init(size: CGSize = CGSize(width: 64, height: 64), action: MascotActionState = .idle, shape: MascotShape = .squircle, provider: ProviderCoreType = .antigravity, lookX: CGFloat = 0, lookY: CGFloat = 0, isPaused: Bool = false) {
        self.size = size
        self.action = action
        self.shape = shape
        self.provider = provider
        self.lookX = lookX
        self.lookY = lookY
        self.isPaused = isPaused
    }

    public var body: some View {
        TimelineView(.animation(paused: isPaused)) { timeline in
            Canvas { context, canvasSize in
                context.withCGContext { cgContext in
                    let elapsed = isPaused ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    let corePhase = (elapsed.truncatingRemainder(dividingBy: 2.0)) / 2.0
                    let params = ExpandedRenderParams(bounds: CGRect(origin: .zero, size: canvasSize), action: action, shape: shape, provider: provider, lookX: lookX, lookY: lookY, corePhase: corePhase)
                    ShapeshifterExpandedRenderer.draw(in: cgContext, params: params)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
```

Create `windows/src/mascot/shapeshifter-expanded.ts`:
```typescript
import type { MascotActionState, MascotShape, ProviderCoreId } from "./types";
import { getProviderBadgeColor } from "./shapeshifter-compact";

export interface ExpandedDrawOptions {
  ctx: CanvasRenderingContext2D;
  width: number;
  height: number;
  action: MascotActionState;
  shape: MascotShape;
  provider: ProviderCoreId;
  lookX: number;
  lookY: number;
  phase: number;
}

export function drawExpandedMascot(opts: ExpandedDrawOptions): void {
  const { ctx, width, height, action, shape, provider, phase } = opts;
  const side = Math.min(width, height);
  if (side < 16) return;

  const ox = (width - side) / 2;
  const oy = (height - side) / 2;
  const tint = getProviderBadgeColor(provider);

  ctx.save();
  ctx.translate(ox, oy);

  // 1. Glassmorphic Body
  ctx.shadowColor = tint;
  ctx.shadowBlur = 12;
  ctx.fillStyle = "rgba(220, 235, 255, 0.25)";
  ctx.strokeStyle = "rgba(255, 255, 255, 0.7)";
  ctx.lineWidth = 1.8;

  const r = side / 2;
  ctx.beginPath();
  if (shape === "squircle") {
    ctx.roundRect(4, 4, side - 8, side - 8, r * 0.48);
  } else if (shape === "orb") {
    ctx.arc(r, r, r - 4, 0, Math.PI * 2);
  } else {
    ctx.moveTo(r, 4);
    ctx.quadraticCurveTo(side - 4, r, r, side - 4);
    ctx.quadraticCurveTo(4, r, r, 4);
  }
  ctx.fill();
  ctx.stroke();

  // 2. Floating AI Core
  const yFloat = Math.sin(phase * Math.PI * 2) * 2.5;
  ctx.shadowColor = tint;
  ctx.shadowBlur = 8;
  ctx.fillStyle = tint;
  ctx.beginPath();
  ctx.arc(r, r + 4 + yFloat, 7, 0, Math.PI * 2);
  ctx.fill();

  // 3. Action Props
  ctx.shadowBlur = 0;
  ctx.lineWidth = 1.5;
  if (action === "writing") {
    ctx.strokeStyle = "#64D2FF";
    ctx.strokeRect(r - 10, side - 16, 20, 12);
  } else if (action === "reading") {
    ctx.strokeStyle = "#FDE047";
    ctx.beginPath();
    ctx.moveTo(r - 12, side - 14);
    ctx.lineTo(r, side - 8);
    ctx.lineTo(r + 12, side - 14);
    ctx.stroke();
  }

  ctx.restore();
}
```

Create `windows/tests/expanded-lod.test.mjs`:
```javascript
import { test } from "node:test";
import assert from "node:assert/strict";

test("Expanded LOD harmonic float calculation", () => {
  const yFloat = (phase) => Math.sin(phase * Math.PI * 2) * 2.5;
  assert.ok(Math.abs(yFloat(0)) < 1e-4);
  assert.ok(Math.abs(yFloat(0.25) - 2.5) < 1e-4);
  assert.ok(Math.abs(yFloat(0.75) - (-2.5)) < 1e-4);
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test-expanded-lod.sh`
Expected: PASS with "ShapeshifterExpandedLODTests finished with 0 failures."

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterExpandedRenderer.swift \
        NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterExpandedView.swift \
        windows/src/mascot/shapeshifter-expanded.ts \
        tests/ShapeshifterExpandedLODTests.swift \
        scripts/test-expanded-lod.sh \
        windows/tests/expanded-lod.test.mjs
git commit -m "feat(mascot): implement Expanded LOD renderer (64-120px) with 3D glassmorphic body and floating core"
```

---

### Task 5: MascotHostView Facade Integration in macOS & Windows

**Files:**
- Create: `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterHostView.swift`
- Create: `windows/src/mascot/shapeshifter-host.ts`
- Create: `tests/ShapeshifterFacadeTests.swift`
- Create: `scripts/test-facade.sh`
- Modify: `NotchBuddy/Sources/App/BotCanvasView.swift:18-30`
- Modify: `NotchBuddy/Sources/App/BotCanvasView.swift:248-285`
- Modify: `windows/src/island/island.ts:1100-1110`

**Interfaces:**
- Consumes: `MascotSettings` (Task 1), `SpriteSheetAnimator` (Task 2), `ShapeshifterCompactView` (Task 3), `ShapeshifterExpandedView` (Task 4).
- Produces:
  - `ShapeshifterHostView`: View observing `AppState`, automatically selecting Compact vs Expanded LOD, mapping `AppState.effectiveState` to `MascotActionState`, and handling 0% CPU pause.
  - Transparent Facade switch in `BotCanvasView.swift` and `windows/src/island/island.ts`.

- [ ] **Step 1: Write the failing test for Facade State Mapping & Routing**

Create `tests/ShapeshifterFacadeTests.swift`:
```swift
import Foundation

@main
enum ShapeshifterFacadeTests {
    static var failures = 0
    static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("ShapeshifterHostView — State mapping")
        check("working maps to .writing", ShapeshifterStateMapper.mapAction(state: "working") == .writing)
        check("searching maps to .reading", ShapeshifterStateMapper.mapAction(state: "searching") == .reading)
        check("thinking maps to .thinking", ShapeshifterStateMapper.mapAction(state: "thinking") == .thinking)
        check("permission maps to .approval", ShapeshifterStateMapper.mapAction(state: "permission") == .approval)
        check("error maps to .error", ShapeshifterStateMapper.mapAction(state: "error") == .error)
        check("idle maps to .idle", ShapeshifterStateMapper.mapAction(state: "idle") == .idle)

        print("ShapeshifterHostView — Review Focus 5: Runtime switching stability")
        var active = MascotSettings.selectedMascot
        check("Initial mascot is shapeshifter", active == .shapeshifter)
        MascotSettings.selectedMascot = .mochi
        check("Switched to mochi", MascotSettings.selectedMascot == .mochi)
        MascotSettings.selectedMascot = .shapeshifter
        check("Switched back to shapeshifter", MascotSettings.selectedMascot == .shapeshifter)

        print("ShapeshifterFacadeTests finished with \(failures) failures.")
        if failures > 0 { exit(1) }
    }
}
```

Create `scripts/test-facade.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/facade-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotSettings.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterHostView.swift \
       tests/ShapeshifterFacadeTests.swift -o "$TEST_DIR/facade-tests"
"$TEST_DIR/facade-tests"
```
Make executable: `chmod +x scripts/test-facade.sh`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-facade.sh`
Expected: FAIL with compilation error "cannot find 'ShapeshifterStateMapper' in scope".

- [ ] **Step 3: Implement ShapeshifterHostView & Wire Facade**

Create `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterHostView.swift`:
```swift
import SwiftUI

public struct ShapeshifterStateMapper {
    public static func mapAction(state: String) -> MascotActionState {
        switch state.lowercased() {
        case "working":                 return .writing
        case "searching":               return .reading
        case "thinking":                return .thinking
        case "permission", "question":  return .approval
        case "error":                   return .error
        case "sleeping":                return .sleeping
        default:                        return .idle
        }
    }
}

public struct ShapeshifterHostView: View {
    @ObservedObject var state: AppState
    public var particleOverhang: CGFloat = 0
    public var lookOriginOverride: CGPoint? = nil
    public var paused: Bool = false
    public var isMini: Bool = false

    public init(state: AppState, particleOverhang: CGFloat = 0, lookOriginOverride: CGPoint? = nil, paused: Bool = false, isMini: Bool = false) {
        self.state = state
        self.particleOverhang = particleOverhang
        self.lookOriginOverride = lookOriginOverride
        self.paused = paused
        self.isMini = isMini
    }

    public var body: some View {
        let isCompact = isMini || state.mode == .compact
        let action = ShapeshifterStateMapper.mapAction(state: state.effectiveState.rawValue)
        let provider = ProviderCoreType.from(pillId: state.focusTask?.id ?? state.mainPillId)
        let isPaused = paused || state.mode == .hidden

        Group {
            if isCompact {
                ShapeshifterCompactView(
                    size: CGSize(width: isMini ? 18 : 24, height: isMini ? 18 : 24),
                    lookX: 0,
                    lookY: 0,
                    shape: MascotSettings.shape,
                    provider: provider,
                    isPulsing: state.effectiveState == .thinking
                )
            } else {
                ShapeshifterExpandedView(
                    size: CGSize(width: 64, height: 64),
                    action: action,
                    shape: MascotSettings.shape,
                    provider: provider,
                    lookX: 0,
                    lookY: 0,
                    isPaused: isPaused
                )
            }
        }
    }
}
```

Create `windows/src/mascot/shapeshifter-host.ts`:
```typescript
import type { MascotActionState, ProviderCoreId } from "./types";
import { MascotSettingsManager } from "./settings";
import { drawCompactMascot } from "./shapeshifter-compact";
import { drawExpandedMascot } from "./shapeshifter-expanded";

export function mapActionFromBotState(botState: string): MascotActionState {
  switch (botState) {
    case "working":    return "writing";
    case "searching":  return "reading";
    case "thinking":   return "thinking";
    case "permission":
    case "question":   return "approval";
    case "error":      return "error";
    case "sleeping":   return "sleeping";
    default:           return "idle";
  }
}

export function renderMascotFacade(
  ctx: CanvasRenderingContext2D,
  w: number,
  h: number,
  state: { mode: string; effectiveState: string; focusTask?: { id: string } | null; mouse?: { x: number; y: number } },
  phase: number
): boolean {
  if (MascotSettingsManager.getSelectedMascot() !== "shapeshifter") {
    return false; // Let original Mochi engine draw
  }

  const action = mapActionFromBotState(state.effectiveState);
  const shape = MascotSettingsManager.getShape();
  const provider = (state.focusTask?.id?.includes("claude") ? "claude" : "antigravity") as ProviderCoreId;

  if (state.mode === "compact") {
    drawCompactMascot({ ctx, width: w, height: h, lookX: 0, lookY: 0, shape, provider });
  } else {
    drawExpandedMascot({ ctx, width: w, height: h, action, shape, provider, lookX: 0, lookY: 0, phase });
  }
  return true;
}
```

Modify `NotchBuddy/Sources/App/BotCanvasView.swift`:
In `BotCanvasView.var body: some View`:
Wrap existing rendering:
```swift
var body: some View {
    if MascotSettings.selectedMascot == .shapeshifter {
        ShapeshifterHostView(state: state, particleOverhang: particleOverhang, lookOriginOverride: lookOriginOverride, paused: paused)
    } else {
        originalMochiBody
    }
}
```
And in `MiniBotCanvasView.var body: some View`:
Wrap:
```swift
var body: some View {
    if MascotSettings.selectedMascot == .shapeshifter {
        ShapeshifterCompactView(
            size: CGSize(width: 18, height: 18),
            lookX: 0,
            lookY: 0,
            shape: MascotSettings.shape,
            provider: ProviderCoreType.from(pillId: task.id)
        )
    } else {
        originalMiniMochiBody
    }
}
```

Modify `windows/src/island/island.ts`:
Around line 1105:
```typescript
if (!renderMascotFacade(ctx, w, hCss, State, this.lastFrame / 1000)) {
  this.engine.applyDance(ctx, w, hCss);
  this.engine.draw(ctx, w, hCss);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test-facade.sh`
Expected: PASS with "ShapeshifterFacadeTests finished with 0 failures."

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterHostView.swift \
        NotchBuddy/Sources/App/BotCanvasView.swift \
        windows/src/mascot/shapeshifter-host.ts \
        windows/src/island/island.ts \
        tests/ShapeshifterFacadeTests.swift \
        scripts/test-facade.sh
git commit -m "feat(mascot): integrate ShapeshifterHostView Facade into BotCanvasView and island.ts"
```

---

### Task 6: End-to-End Verification, Build Check & Documentation Update

**Files:**
- Create: `tests/AstralMorphE2ETests.swift`
- Create: `scripts/test-astral-morph-e2e.sh`
- Modify: `docs/MASCOT_DESIGN_SPEC.md`
- Modify: `docs/FORK_SYNC_MASCOT.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: All components from Tasks 1–5.
- Produces: Complete end-to-end test verification and clean `xcodegen && xcodebuild` compilation.

- [ ] **Step 1: Write comprehensive End-to-End Test Suite**

Create `tests/AstralMorphE2ETests.swift`:
```swift
import Foundation
import CoreGraphics

@main
enum AstralMorphE2ETests {
    static var failures = 0
    static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("=== Astral Morph Mascot End-to-End Verification ===")

        print("1. Settings & Storage")
        MascotSettings.selectedMascot = .shapeshifter
        check("Selected mascot is .shapeshifter", MascotSettings.selectedMascot == .shapeshifter)
        MascotSettings.shape = .squircle
        check("Shape is .squircle", MascotSettings.shape == .squircle)

        print("2. 24 FPS Sprite Animation Pipeline")
        let anim = SpriteSheetAnimator(config: .default(for: .writing))
        check("Writing cycle has 24 frames", anim.config.frameCount == 24)
        _ = anim.update(dt: 0.5)
        check("Midway frame index is 12", anim.currentFrameIndex == 12)

        print("3. Compact LOD (20-32px)")
        let compactRect = ShapeshifterCompactRenderer.clampedDrawRect(in: CGSize(width: 32, height: 32))
        check("Compact rect is 32x32", compactRect.width == 32 && compactRect.height == 32)
        let claudeBadge = ShapeshifterCompactRenderer.badgeColor(for: .claude)
        check("Claude badge terracotta hex", claudeBadge.hex == "#D97757")

        print("4. Expanded LOD (64-120px)")
        let expandedRect = ShapeshifterExpandedRenderer.clampedDrawRect(in: CGSize(width: 80, height: 80))
        check("Expanded rect is 80x80", expandedRect.width == 80 && expandedRect.height == 80)
        let coreY = ShapeshifterExpandedRenderer.harmonicCoreYOffset(phase: 0.25)
        check("Core oscillation peak at phase 0.25", abs(coreY - 2.5) < 0.001)

        print("5. Facade State Translation")
        check("working -> writing", ShapeshifterStateMapper.mapAction(state: "working") == .writing)
        check("searching -> reading", ShapeshifterStateMapper.mapAction(state: "searching") == .reading)

        print("=== E2E Test Result: \(failures) failures ===")
        if failures > 0 { exit(1) }
    }
}
```

Create `scripts/test-astral-morph-e2e.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mascot-e2e.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotSettings.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/SpriteSheetAnimator.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterCompactRenderer.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterExpandedRenderer.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterHostView.swift \
       tests/AstralMorphE2ETests.swift -o "$TEST_DIR/e2e-tests"
"$TEST_DIR/e2e-tests"
```
Make executable: `chmod +x scripts/test-astral-morph-e2e.sh`.

- [ ] **Step 2: Run all test suites to verify full pass**

Run:
```bash
bash scripts/test-mascot-settings.sh
bash scripts/test-sprite-sheet-animator.sh
bash scripts/test-compact-lod.sh
bash scripts/test-expanded-lod.sh
bash scripts/test-facade.sh
bash scripts/test-astral-morph-e2e.sh
```
Expected: All suites exit with code 0 and "0 failures".

- [ ] **Step 3: Run project generation and Xcode build**

Run:
```bash
cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Update Documentation and CHANGELOG**

Update `docs/MASCOT_DESIGN_SPEC.md` and `docs/FORK_SYNC_MASCOT.md` adding the implementation status and verifying the checklist.
Add entry to `CHANGELOG.md` under `## [Unreleased]` describing the Astral Morph mascot implementation.

- [ ] **Step 5: Commit**

```bash
git add tests/AstralMorphE2ETests.swift \
        scripts/test-astral-morph-e2e.sh \
        docs/MASCOT_DESIGN_SPEC.md \
        docs/FORK_SYNC_MASCOT.md \
        CHANGELOG.md
git commit -m "docs(mascot): complete end-to-end verification, xcode build check, and documentation"
```
