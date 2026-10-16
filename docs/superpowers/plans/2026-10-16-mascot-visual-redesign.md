# Astral Morph Mascot Visual Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Overhaul the visual appearance, character expressiveness, geometry alignment, and secondary surface presence of the Astral Morph mascot across macOS (`NotchBuddy`) and Windows (`windows/`), transforming wireframes and generic circles into an adorable, luminous spirit character with big glossy eyes, flame crown, blush cheeks, floating AI core, action props, and 24 FPS sprite animation support with procedural vector fallback.

**Architecture:** 
1. Geometry Anchoring: Correct vertical offset compensation (`+particleOverhang / 2`) in `ShapeshifterHostView` to anchor the spirit to the notch floor and prevent bezel clipping.
2. Compact & Expanded Expressive Procedural Renderers: Replace hollow wireframes and plain circles with high-fidelity glassmorphic spirits featuring big expressive eyes with specular highlights that track cursor look angles, cute flame crowns, rosy cheeks, and distinct action props (stylus + tablet, reading book, thinking spark).
3. Hybrid Sprite Engine: Load and blit 24 FPS texture sheets when bundled in `Resources/Mascots/Shapeshifter/`, with seamless zero-glitch fallback to the expressive vector renderer when assets are missing.
4. Non-Intrusive Facades: Wrap secondary surfaces (`FlowHub` sidebar header and `TunnelGuard` hero banner) with `HubLiveMascot` and `HubHeroTheme` adaptation, preserving 100% of original Mochi codebase without breaking upstream Coucou merges.

**Tech Stack:** Swift 6 (`SwiftUI`, `AppKit`, `CoreGraphics`, `TimelineView`), TypeScript (`HTML5 2D Canvas`), XcodeGen, and Node.js test runners.

**Spec:** `design/prototype/astral_morph_concept.jpg`, `docs/MASCOT_DESIGN_SPEC.md`, `docs/FORK_SYNC_MASCOT.md`, `CLAUDE.md`.

## Global Constraints

- Swift 6 strict concurrency (`OTHER_SWIFT_FLAGS: "-strict-concurrency=complete"` in `project.yml:35`).
- 0.0% CPU usage when the notch island is hidden, minimized, or paused (`CLAUDE.md:30`).
- Fork isolation: zero breaking changes to existing signatures (`BotPlacement`, `FlowPill`, `IslandRootView`); original `BotEngine.swift` remains untouched (`docs/FORK_SYNC_MASCOT.md:68-80`).
- Mascot asset standard: 24 FPS texture blitting with horizontal/matrix grid layout, 8-bit alpha PNG, Retina `@2x`/`@3x` ($240 \times 240$ px expanded, $64 \times 64$ px compact) with procedural vector fallback (`docs/MASCOT_DESIGN_SPEC.md:81-87`).
- Keep bundle identifier `fr.louisraille.NotchBuddy` and existing project configuration (`CLAUDE.md:31`).

## Review Focus

1. **Vertical Offset & Notch Bezel Clipping (Overhang Compensation):** When the island is in collapsed or resting mode (`mode == .compact` or `.hidden`) with `particleOverhang > 0` (e.g. 40pt), the mascot body must be vertically offset downwards by `+ particleOverhang / 2` so its center exactly aligns with `cy`, preventing the head/crown from being pushed into the physical screen bezel. (Pinned to Task 1)
2. **Missing Sprite Sheet Fallback & Missing Action Assets:** When sprite sheet PNG assets for a given `MascotActionState` (e.g. `approval`, `error`, `sleeping`) are absent, corrupt, or unreadable from the app bundle, the renderer must seamlessly fall back to Task 3's expressive procedural vector spirit with zero visual glitch, zero crashes, and 0.0% CPU overhead. (Pinned to Task 4)
3. **Empty / Unknown / Custom Provider Color & Spark Fallback:** When a task or pill has `nil`, empty, or unrecognized provider string (e.g., `"unknown-worker"`, `""`), `ProviderCoreType.from(pillId:)` must safely map to `.custom("...")` and both compact and expanded renderers must resolve to the astral cyan `#64D2FF` default core/spark and never crash or render invisible black dots. (Pinned to Task 2 and Task 3)
4. **Non-Square / Extreme Bounding Dimensions in Floating Cards or Mini Pills:** When host container passes an asymmetric or stretched frame (e.g. `width: 120, height: 28` in an agent pill, or `width: 320, height: 92` in a hero banner), renderers must clamp the mascot to a 1:1 aspect ratio based on `min(width, height)` and center it along the larger axis, preserving eye tracking, proportions, and blush positions without stretching or clipping. (Pinned to Task 2 and Task 3)
5. **Runtime Mascot Switching Integrity & 0.0% CPU Paused State:** When the user toggles `MascotSettings.selectedMascot` between `.mochi` and `.shapeshifter` repeatedly while the island is animating, hidden, or backgrounded, animation timers and timeline ticks must suspend with strictly 0.0% CPU usage, and switching must preserve all state mapping (working -> writing, searching -> reading) without engine leaks or visual artifacts. (Pinned to Task 5)

---

### Task 1: Geometry & Notch Anchoring Fix

**Files:**
- Create: `tests/ShapeshifterGeometryTests.swift`
- Create: `scripts/test-geometry.sh`
- Modify: `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift:37-46`
- Modify: `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterHostView.swift:18-63`

**Interfaces:**
- Consumes: `IslandMode`, `BotState`, `particleOverhang: CGFloat`.
- Produces:
  - `ShapeshifterGeometry.verticalOffset(particleOverhang: CGFloat) -> CGFloat`: Returns `particleOverhang / 2.0` to compensate for `position(x: cx, y: cy - overhang / 2)` in `IslandRootView.swift`.
  - `ShapeshifterGeometry.isCompactMode(mode: IslandMode, isMini: Bool) -> Bool`: Returns `true` when `isMini || mode == .compact || mode == .hidden` so the collapsed resting notch never renders the 64pt expanded disk.
  - `ShapeshifterGeometry.targetMascotSize(isCompact: Bool, isMini: Bool, canvasSize: CGSize, overhang: CGFloat) -> CGSize`: Clamps size safely so resting notch diameter is 20-26pt and expanded card diameter is 60-80pt.

- [ ] **Step 1: Write the failing test for Shapeshifter geometry and notch anchoring**

Create `tests/ShapeshifterGeometryTests.swift`:
```swift
import Foundation
import CoreGraphics

#if STANDALONE_CLI
public enum IslandMode: Sendable {
    case hidden
    case compact
    case expanded
}
#endif

@main
enum ShapeshifterGeometryTests {
    static var failures = 0
    static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("ShapeshifterGeometry — Review Focus 1: Vertical Offset & Notch Overhang Compensation")
        let overhang40 = ShapeshifterGeometry.verticalOffset(particleOverhang: 40)
        check("Overhang 40 yields downward offset +20", overhang40 == 20)

        let overhangZero = ShapeshifterGeometry.verticalOffset(particleOverhang: 0)
        check("Overhang 0 yields downward offset 0", overhangZero == 0)

        print("ShapeshifterGeometry — Mode Detection (Collapsed notch must be compact)")
        check("Hidden mode is compact", ShapeshifterGeometry.isCompactMode(mode: .hidden, isMini: false))
        check("Compact mode is compact", ShapeshifterGeometry.isCompactMode(mode: .compact, isMini: false))
        check("Mini pill is compact", ShapeshifterGeometry.isCompactMode(mode: .expanded, isMini: true))
        check("Expanded mode is NOT compact", !ShapeshifterGeometry.isCompactMode(mode: .expanded, isMini: false))

        print("ShapeshifterGeometry — Review Focus 4: Target Sizing in Notch and Cards")
        let miniSize = ShapeshifterGeometry.targetMascotSize(isCompact: true, isMini: true, canvasSize: CGSize(width: 18, height: 18), overhang: 0)
        check("Mini size is exactly 18x18", miniSize.width == 18 && miniSize.height == 18)

        let restingSize = ShapeshifterGeometry.targetMascotSize(isCompact: true, isMini: false, canvasSize: CGSize(width: 40, height: 72), overhang: 40)
        check("Resting notch size is clamped <= 26pt", restingSize.width <= 26 && restingSize.width >= 20)

        let expandedSize = ShapeshifterGeometry.targetMascotSize(isCompact: false, isMini: false, canvasSize: CGSize(width: 120, height: 120), overhang: 0)
        check("Expanded size fills card frame (120x120)", expandedSize.width == 120 && expandedSize.height == 120)

        print("ShapeshifterGeometryTests finished with \(failures) failures.")
        if failures > 0 { exit(1) }
    }
}
```

Create `scripts/test-geometry.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/geometry-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -DSTANDALONE_CLI \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift \
       tests/ShapeshifterGeometryTests.swift -o "$TEST_DIR/geometry-tests"
"$TEST_DIR/geometry-tests"
```
Make executable: `chmod +x scripts/test-geometry.sh`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-geometry.sh`
Expected: FAIL with "unresolved identifier ShapeshifterGeometry".

- [ ] **Step 3: Implement `ShapeshifterGeometry` in `MascotTypes.swift` and apply in `ShapeshifterHostView.swift`**

Add to `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift`:
```swift
#if !STANDALONE_CLI
import SwiftUI
#endif

public enum ShapeshifterGeometry: Sendable {
    public static func verticalOffset(particleOverhang: CGFloat) -> CGFloat {
        return particleOverhang / 2.0
    }

    #if STANDALONE_CLI
    public static func isCompactMode(mode: IslandMode, isMini: Bool) -> Bool {
        return isMini || mode == .compact || mode == .hidden
    }
    #else
    public static func isCompactMode(mode: IslandMode, isMini: Bool) -> Bool {
        return isMini || mode == .compact || mode == .hidden
    }
    #endif

    public static func targetMascotSize(isCompact: Bool, isMini: Bool, canvasSize: CGSize, overhang: CGFloat) -> CGSize {
        if isMini {
            return CGSize(width: 18, height: 18)
        } else if isCompact {
            let availableHeight = max(0, canvasSize.height - overhang)
            let side = min(canvasSize.width, availableHeight > 0 ? availableHeight : canvasSize.height)
            let clamped = min(26.0, max(18.0, side))
            return CGSize(width: clamped, height: clamped)
        } else {
            let availableHeight = max(0, canvasSize.height - overhang)
            let side = min(canvasSize.width, availableHeight > 0 ? availableHeight : canvasSize.height)
            let clamped = max(44.0, side)
            return CGSize(width: clamped, height: clamped)
        }
    }
}
```

Update `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterHostView.swift`:
```swift
    public var body: some View {
        let isCompact = ShapeshifterGeometry.isCompactMode(mode: state.mode, isMini: isMini)
        let action = ShapeshifterStateMapper.mapAction(state: state.effectiveState.rawValue)
        let provider = ProviderCoreType.from(pillId: state.focusTask?.id ?? state.mainPillId)
        let isPaused = paused || state.mode == .hidden
        let yOffset = ShapeshifterGeometry.verticalOffset(particleOverhang: particleOverhang)

        GeometryReader { geo in
            let mascotSize = ShapeshifterGeometry.targetMascotSize(
                isCompact: isCompact,
                isMini: isMini,
                canvasSize: geo.size,
                overhang: particleOverhang
            )
            ZStack(alignment: .center) {
                if isCompact {
                    ShapeshifterCompactView(
                        size: mascotSize,
                        lookX: 0,
                        lookY: 0,
                        shape: MascotSettings.shape,
                        provider: provider,
                        isPulsing: state.effectiveState == .thinking
                    )
                } else {
                    ShapeshifterExpandedView(
                        size: mascotSize,
                        action: action,
                        shape: MascotSettings.shape,
                        provider: provider,
                        lookX: 0,
                        lookY: 0,
                        isPaused: isPaused
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .offset(y: yOffset)
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test-geometry.sh`
Expected: PASS with 0 failures.

- [ ] **Step 5: Commit**

```bash
git add tests/ShapeshifterGeometryTests.swift scripts/test-geometry.sh NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterHostView.swift
git commit -m "fix(mascot): compensate particleOverhang and anchor resting notch to bottom floor"
```

---

### Task 2: Expressive Vector Spirit Renderer for Compact LOD & Mini Pills

**Files:**
- Modify: `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterCompactRenderer.swift`
- Modify: `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterCompactView.swift`
- Modify: `windows/src/mascot/shapeshifter-compact.ts`
- Modify: `tests/ShapeshifterCompactLODTests.swift`
- Modify: `windows/tests/compact-lod.test.mjs`

**Interfaces:**
- Consumes: `CompactRenderParams(size:lookX:lookY:shape:provider:isPulsing:)`.
- Produces:
  - `ShapeshifterCompactRenderer.draw(in:params:)`: Renders a cute filled translucent spirit body, glowing flame crown tuft, big glossy eyes with specular white highlights, soft rosy blush cheeks (`#FF85A1` at 0.4 alpha), and provider spark.
  - `ShapeshifterCompactRenderer.eyeOffsets(lookX:lookY:diameter:)`: Returns clamped eye center coordinates.
  - `ShapeshifterCompactRenderer.specularHighlightOffsets(lookX:lookY:diameter:)`: Returns primary and secondary specular dot coordinates.
  - `ShapeshifterCompactRenderer.cheekBlushOffsets(diameter:)`: Returns left and right cheek blush centers and radius.

- [ ] **Step 1: Write the failing tests for expressive Compact LOD features**

Update `tests/ShapeshifterCompactLODTests.swift`:
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

        let antigravity = ShapeshifterCompactRenderer.badgeColor(for: .antigravity)
        check("Antigravity badge color is #8B5CF6", antigravity.hex == "#8B5CF6")

        let customFallback = ShapeshifterCompactRenderer.badgeColor(for: .custom("unknown"))
        check("Unknown provider falls back to astral cyan #64D2FF", customFallback.hex == "#64D2FF")

        print("ShapeshifterCompactRenderer — Review Focus 4: Clamping non-square bounding rects")
        let clampedSquare = ShapeshifterCompactRenderer.clampedDrawRect(in: CGSize(width: 40, height: 20))
        check("Clamped width matches height (20)", clampedSquare.width == 20 && clampedSquare.height == 20)
        check("Clamped rect is centered horizontally (x == 10)", clampedSquare.origin.x == 10)

        print("ShapeshifterCompactRenderer — Expressive Character Features (Eyes & Specular Highlights)")
        let eyes = ShapeshifterCompactRenderer.eyeOffsets(lookX: 1.0, lookY: -1.0, diameter: 24)
        check("Left eye within safe horizontal boundary", abs(eyes.left.x) <= 6.0)
        check("Right eye within safe horizontal boundary", abs(eyes.right.x) <= 6.0)

        let highlights = ShapeshifterCompactRenderer.specularHighlightOffsets(lookX: 0.0, lookY: 0.0, diameter: 24)
        check("Left eye primary specular dot is in top-left quadrant", highlights.leftPrimary.x < eyes.left.x && highlights.leftPrimary.y < eyes.left.y)

        print("ShapeshifterCompactRenderer — Rosy Cheek Blush Geometry")
        let cheeks = ShapeshifterCompactRenderer.cheekBlushOffsets(diameter: 24)
        check("Cheeks are positioned below eye level", cheeks.left.y > 0 && cheeks.right.y > 0)
        check("Cheek radius is proportional (approx 1.5 - 2.5pt)", cheeks.radius >= 1.2 && cheeks.radius <= 3.0)

        print("ShapeshifterCompactLODTests finished with \(failures) failures.")
        if failures > 0 { exit(1) }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-compact-lod.sh`
Expected: FAIL with "specularHighlightOffsets" and "cheekBlushOffsets" not defined.

- [ ] **Step 3: Implement expressive spirit rendering in `ShapeshifterCompactRenderer.swift` and `shapeshifter-compact.ts`**

Update `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterCompactRenderer.swift`:
- Implement:
  1. `specularHighlightOffsets(lookX:lookY:diameter:)`
  2. `cheekBlushOffsets(diameter:)`
  3. `draw(in:params:)`:
     - Subsurface glowing aura (`setShadow`).
     - Translucent gradient-filled spirit body (`drawRadialGradient` or multi-stop fill from celestial white `rgba(240, 248, 255, 0.75)` to spirit blue `rgba(140, 190, 255, 0.25)`).
     - Head flame crown tuft at top center.
     - Big glossy dark oval eyes (`CGColor(red: 0.08, green: 0.10, blue: 0.16, alpha: 0.95)`).
     - Specular white highlight dots inside each eye.
     - Soft rosy blush cheeks (`CGColor(red: 1.0, green: 0.52, blue: 0.63, alpha: 0.40)`).
     - Micro provider jewel badge at top right with outer glow.

Update `windows/src/mascot/shapeshifter-compact.ts`:
- Implement matching filled spirit body, flame crown tuft, glossy dark eyes with specular dots, rosy cheeks, and provider badge.

Update `windows/tests/compact-lod.test.mjs`:
- Add test assertions for specular dots and cheek blush math.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/test-compact-lod.sh && node windows/tests/compact-lod.test.mjs`
Expected: PASS with 0 failures.

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterCompactRenderer.swift windows/src/mascot/shapeshifter-compact.ts tests/ShapeshifterCompactLODTests.swift windows/tests/compact-lod.test.mjs
git commit -m "feat(mascot): render expressive compact spirit with filled body, glossy eyes, flame tuft and blush"
```

---

### Task 3: Expressive Vector Spirit Renderer for Expanded LOD Fallback

**Files:**
- Modify: `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterExpandedRenderer.swift`
- Modify: `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterExpandedView.swift`
- Modify: `windows/src/mascot/shapeshifter-expanded.ts`
- Modify: `tests/ShapeshifterExpandedLODTests.swift`
- Modify: `windows/tests/expanded-lod.test.mjs`

**Interfaces:**
- Consumes: `ExpandedRenderParams(bounds:action:shape:provider:lookX:lookY:corePhase:)`.
- Produces:
  - `ShapeshifterExpandedRenderer.draw(in:params:)`: Full expressive character rendering including flame crown, big glossy dark eyes with primary/secondary specular highlights, mouth expressions, rosy cheeks, harmonic floating core, and cute stubby hands with action props.
  - `ShapeshifterExpandedRenderer.faceGeometry(rect:lookX:lookY:)`: Coordinates for eyes, pupils, specular reflections, cheeks, and mouth.
  - `ShapeshifterExpandedRenderer.actionPropsGeometry(rect:action:)`: Paths and anchor points for tablet + stylus, reading book, thinking spark swirl, approval thumbs-up/shield, error alert, and sleeping snooze.

- [ ] **Step 1: Write the failing tests for expressive Expanded LOD features**

Update `tests/ShapeshifterExpandedLODTests.swift`:
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

        print("ShapeshifterExpandedRenderer — Review Focus 4: Non-square bounding box centering")
        let clampedRect = ShapeshifterExpandedRenderer.clampedDrawRect(in: CGSize(width: 120, height: 60))
        check("Clamped side is 60", clampedRect.width == 60 && clampedRect.height == 60)
        check("Clamped rect is centered horizontally (x == 30)", clampedRect.origin.x == 30)

        print("ShapeshifterExpandedRenderer — Expressive Character Face Geometry")
        let face = ShapeshifterExpandedRenderer.faceGeometry(rect: CGRect(x: 0, y: 0, width: 80, height: 80), lookX: 0.5, lookY: -0.5)
        check("Left and right eye distinct horizontal positions", face.leftEyeCenter.x < face.rightEyeCenter.x)
        check("Pupil specular highlight offset inside eye bounds", face.leftSpecularPrimary.x < face.leftEyeCenter.x)
        check("Cheeks positioned symmetrically below eyes", face.leftCheekCenter.y > face.leftEyeCenter.y && face.rightCheekCenter.y > face.rightEyeCenter.y)
        check("Mouth positioned between cheeks", face.mouthCenter.y >= face.leftCheekCenter.y - 2)

        print("ShapeshifterExpandedRenderer — Review Focus 3: Fallback core for unknown provider")
        let coreColor = ShapeshifterExpandedRenderer.coreColor(for: .custom("generic_agent"))
        check("Custom provider core color is astral cyan #64D2FF", coreColor.hex == "#64D2FF")

        print("ShapeshifterExpandedLODTests finished with \(failures) failures.")
        if failures > 0 { exit(1) }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-expanded-lod.sh`
Expected: FAIL with "faceGeometry" not defined.

- [ ] **Step 3: Implement expressive character face, crown, hands, and props in `ShapeshifterExpandedRenderer.swift` and `shapeshifter-expanded.ts`**

Update `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterExpandedRenderer.swift`:
- Add `faceGeometry(rect:lookX:lookY:)`.
- In `drawGlassmorphicBody`: add top flickering flame crown tuft.
- Add `drawExpressiveFace(in:context:face:action:)`:
  - Big dark glossy oval eyes (`CGColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 0.95)`).
  - Primary bright white circular highlight dot in upper-left and secondary micro-dot in lower-right.
  - Soft rosy blush cheeks (`#FF85A1` at 0.45 alpha).
  - Expressive mouth arc tailored to `action` (smile, 'o', wavy, 'z').
- Add `drawCuteHandsAndProps(in:context:rect:action:)`:
  - Translucent spirit hands holding stylus + tablet for `.writing`, open book for `.reading`, touching chin with astral swirl for `.thinking`, thumbs-up/shield for `.approval`.
- Update `draw(in:params:)` to assemble body -> flame crown -> floating core -> face & eyes -> hands & action props.

Update `windows/src/mascot/shapeshifter-expanded.ts`:
- Implement matching face, eyes, specular dots, flame crown, blush cheeks, mouth, and cute hands with props.

Update `windows/tests/expanded-lod.test.mjs`:
- Add test assertions for expanded face geometry and action prop rendering.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/test-expanded-lod.sh && node windows/tests/expanded-lod.test.mjs`
Expected: PASS with 0 failures.

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterExpandedRenderer.swift windows/src/mascot/shapeshifter-expanded.ts tests/ShapeshifterExpandedLODTests.swift windows/tests/expanded-lod.test.mjs
git commit -m "feat(mascot): render expressive expanded character with glossy eyes, flame crown, blush and props"
```

---

### Task 4: High-Fidelity 3D Sprite Sheet Integration

**Files:**
- Modify: `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/SpriteSheetAnimator.swift`
- Modify: `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterExpandedView.swift`
- Create directory: `NotchBuddy/Resources/Mascots/Shapeshifter/`
- Modify: `tests/SpriteSheetAnimatorTests.swift`
- Modify: `scripts/test-sprite-sheet-animator.sh`

**Interfaces:**
- Consumes: `MascotActionState`, bundle resources in `Resources/Mascots/Shapeshifter/`.
- Produces:
  - `SpriteSheetLoader.shared.image(for: MascotActionState) -> CGImage?`: Cached thread-safe texture sheet provider.
  - `ShapeshifterExpandedView`: Blits 24 FPS texture frame when sprite asset is present; seamlessly falls back to `ShapeshifterExpandedRenderer.draw` when sprite sheet is nil/missing (Review Focus 2).

- [ ] **Step 1: Write the failing test for SpriteSheetLoader and graceful vector fallback**

Update `tests/SpriteSheetAnimatorTests.swift`:
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

        _ = animator.update(dt: 1.0 / 24.0)
        check("Frame advances to 1 after 1/24s", animator.currentFrameIndex == 1)

        print("SpriteSheetAnimator — Review Focus 2: Missing asset graceful fallback")
        let missingAssetImage = SpriteSheetLoader.shared.image(for: .sleeping, bundle: Bundle(for: SpriteSheetAnimator.self))
        check("Non-existent sprite returns nil without crash", missingAssetImage == nil)

        let fallbackDecision = SpriteSheetLoader.shouldUseVectorFallback(action: .sleeping, bundle: Bundle(for: SpriteSheetAnimator.self))
        check("Fallback flag is true when asset is missing", fallbackDecision == true)

        print("SpriteSheetAnimator — Review Focus 2: Paused state 0% work")
        animator.isPaused = true
        _ = animator.update(dt: 10.0)
        check("Frame does not advance while paused", animator.currentFrameIndex == 1)

        print("SpriteSheetAnimatorTests finished with \(failures) failures.")
        if failures > 0 { exit(1) }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-sprite-sheet-animator.sh`
Expected: FAIL with "unresolved identifier SpriteSheetLoader".

- [ ] **Step 3: Implement `SpriteSheetLoader` in `SpriteSheetAnimator.swift` and integrate into `ShapeshifterExpandedView.swift`**

Add `SpriteSheetLoader` to `SpriteSheetAnimator.swift`:
```swift
public final class SpriteSheetLoader: @unchecked Sendable {
    public static let shared = SpriteSheetLoader()
    private var cache = [MascotActionState: CGImage]()
    private let lock = NSLock()

    public func image(for action: MascotActionState, bundle: Bundle = .main) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[action] { return cached }
        let resourceName = "astral_\(action.rawValue)"
        guard let url = bundle.url(forResource: resourceName, withExtension: "png", subdirectory: "Mascots/Shapeshifter")
                ?? bundle.url(forResource: resourceName, withExtension: "png") else {
            return nil
        }
        guard let dataProvider = CGDataProvider(url: url as CFURL),
              let img = CGImage(pngDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            return nil
        }
        cache[action] = img
        return img
    }

    public static func shouldUseVectorFallback(action: MascotActionState, bundle: Bundle = .main) -> Bool {
        return shared.image(for: action, bundle: bundle) == nil
    }
}
```

Update `ShapeshifterExpandedView.swift`:
```swift
    public var body: some View {
        TimelineView(.animation(paused: isPaused)) { timeline in
            Canvas { context, canvasSize in
                context.withCGContext { cgContext in
                    if !isPaused, let spriteSheet = SpriteSheetLoader.shared.image(for: action) {
                        let config = SpriteSheetConfig.default(for: action)
                        let animator = SpriteSheetAnimator(config: config)
                        let elapsed = timeline.date.timeIntervalSinceReferenceDate
                        let frameIdx = Int(floor(elapsed * config.fps)) % config.frameCount
                        let srcRect = animator.frameRect(for: frameIdx, imageSize: CGSize(width: spriteSheet.width, height: spriteSheet.height))
                        if let frameImage = spriteSheet.cropping(to: srcRect) {
                            let destRect = ShapeshifterExpandedRenderer.clampedDrawRect(in: canvasSize)
                            cgContext.draw(frameImage, in: destRect)
                            return
                        }
                    }
                    // Seamless procedural vector fallback
                    let elapsed = isPaused ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    let corePhase = (elapsed.truncatingRemainder(dividingBy: 2.0)) / 2.0
                    let params = ExpandedRenderParams(
                        bounds: CGRect(origin: .zero, size: canvasSize),
                        action: action,
                        shape: shape,
                        provider: provider,
                        lookX: lookX,
                        lookY: lookY,
                        corePhase: corePhase
                    )
                    ShapeshifterExpandedRenderer.draw(in: cgContext, params: params)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
```

Create directory `NotchBuddy/Resources/Mascots/Shapeshifter/` with `.gitkeep`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test-sprite-sheet-animator.sh`
Expected: PASS with 0 failures.

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/SpriteSheetAnimator.swift NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterExpandedView.swift tests/SpriteSheetAnimatorTests.swift NotchBuddy/Resources/Mascots/Shapeshifter/.gitkeep
git commit -m "feat(mascot): add SpriteSheetLoader with 24 FPS texture blitting and seamless vector fallback"
```

---

### Task 5: Secondary Surfaces Facade (FlowHub & TunnelGuard)

**Files:**
- Modify: `NotchBuddy/Sources/App/FlowHub.swift:260-267`
- Modify: `NotchBuddy/Sources/App/FlowHubMochis.swift:205-225,280-315`
- Modify: `tests/FlowHubTestStubs.swift:40-49`
- Create: `tests/FlowHubMascotTests.swift`
- Modify: `scripts/test-facade.sh`

**Interfaces:**
- Consumes: `MascotSettings.selectedMascot`, `HubPage`.
- Produces:
  - `HubLiveMascot(size: CGFloat, state: BotState, outfit: Outfit)`: Renders `ShapeshifterCompactView` when `selectedMascot == .shapeshifter` and `HubLiveMochi` when `selectedMascot == .mochi`.
  - `HubHeroTheme.of(page)`: When `page == .tunnelGuard` and `selectedMascot == .shapeshifter`, displays the Astral Morph spirit in hero guarding stance instead of Mochi beans.

- [ ] **Step 1: Write the failing test for FlowHub secondary surface mascot switching**

Create `tests/FlowHubMascotTests.swift`:
```swift
import Foundation

@main
enum FlowHubMascotTests {
    static var failures = 0
    static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("FlowHubMascot — Review Focus 5: Surface Facade Switching")
        MascotSettings.selectedMascot = .shapeshifter
        check("When selectedMascot is .shapeshifter, HubLiveMascot uses shapeshifter engine", HubMascotResolver.isShapeshifterActive)

        MascotSettings.selectedMascot = .mochi
        check("When selectedMascot is .mochi, HubLiveMascot uses mochi engine", !HubMascotResolver.isShapeshifterActive)

        print("FlowHubMascot — TunnelGuard Banner Hero Mascot Adaptation")
        MascotSettings.selectedMascot = .shapeshifter
        let tgTheme = HubHeroTheme.of(.tunnelGuard)
        check("TunnelGuard hero color is green #30D158", tgTheme.colorHex == "#30D158")
        check("TunnelGuard hero identifies shapeshifter active", tgTheme.usesShapeshifterHero)

        MascotSettings.selectedMascot = .shapeshifter // reset
        print("FlowHubMascotTests finished with \(failures) failures.")
        if failures > 0 { exit(1) }
    }
}
```

Update `scripts/test-facade.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/facade-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -DSTANDALONE_CLI \
       tests/FlowHubTestStubs.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotSettings.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterHostView.swift \
       tests/ShapeshifterFacadeTests.swift \
       tests/FlowHubMascotTests.swift -o "$TEST_DIR/facade-tests"
"$TEST_DIR/facade-tests"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-facade.sh`
Expected: FAIL with "unresolved identifier HubMascotResolver".

- [ ] **Step 3: Implement `HubLiveMascot` and `HubHeroTheme` mascot adaptation**

In `NotchBuddy/Sources/App/FlowHubMochis.swift`:
```swift
public enum HubMascotResolver {
    public static var isShapeshifterActive: Bool {
        return MascotSettings.selectedMascot == .shapeshifter
    }
}

/// Dynamic mascot view for Hub header (switches between Mochi and Astral Morph)
struct HubLiveMascot: View {
    var color = "#F5F6F8"
    var size: CGFloat = 28
    var state: BotState = .idle
    var outfit: Outfit = .none

    var body: some View {
        if MascotSettings.selectedMascot == .shapeshifter {
            ShapeshifterCompactView(
                size: CGSize(width: size, height: size),
                lookX: 0,
                lookY: 0,
                shape: MascotSettings.shape,
                provider: .antigravity
            )
            .frame(width: size, height: size)
        } else {
            HubLiveMochi(color: color, size: size, state: state, outfit: outfit)
        }
    }
}
```

In `FlowHub.swift:263`:
Replace:
```swift
HubLiveMochi(size: 28)
```
with:
```swift
HubLiveMascot(size: 28)
```

In `HubHeroTheme`:
Add property `public var usesShapeshifterHero: Bool { MascotSettings.selectedMascot == .shapeshifter }` and `public var colorHex: String`.
In `HubHero`: when `usesShapeshifterHero && page == .tunnelGuard`, render `ShapeshifterExpandedView(size: CGSize(width: compact ? 70 : 96, height: compact ? 70 : 96), action: .approval, shape: MascotSettings.shape, provider: .antigravity)`.

Update `tests/FlowHubTestStubs.swift` with `HubLiveMascot` and `HubMascotResolver`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test-facade.sh`
Expected: PASS with 0 failures.

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/App/FlowHub.swift NotchBuddy/Sources/App/FlowHubMochis.swift tests/FlowHubTestStubs.swift tests/FlowHubMascotTests.swift scripts/test-facade.sh
git commit -m "feat(mascot): add HubLiveMascot and adapt TunnelGuard hero banner to Astral Morph"
```

---

### Task 6: Full Verification, Xcode Build, and Visual Preview

**Files:**
- Create: `scripts/test-all-mascot.sh`
- Modify: `tests/AstralMorphE2ETests.swift`
- Modify: `design/prototype/mascot-showcase.html`

**Interfaces:**
- Consumes: All test suites and build tools.
- Produces:
  - Unified passing test run across all 6 test scripts and Node.js suites.
  - Zero compile errors on `xcodegen generate` and `xcodebuild -scheme NotchBuddy -configuration Debug build`.
  - Visual preview showcase in `design/prototype/mascot-showcase.html`.

- [ ] **Step 1: Write unified end-to-end verification script `scripts/test-all-mascot.sh`**

Create `scripts/test-all-mascot.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=========================================================="
echo "      Astral Morph Mascot Full Verification Suite        "
echo "=========================================================="

echo "[1/7] Running Geometry & Notch Anchoring Tests..."
bash scripts/test-geometry.sh

echo "[2/7] Running Compact LOD & Mini Pill Tests..."
bash scripts/test-compact-lod.sh

echo "[3/7] Running Expanded LOD & Expressive Face Tests..."
bash scripts/test-expanded-lod.sh

echo "[4/7] Running Sprite Sheet Animator & Fallback Tests..."
bash scripts/test-sprite-sheet-animator.sh

echo "[5/7] Running Facade & Secondary Surfaces Tests..."
bash scripts/test-facade.sh

echo "[6/7] Running Astral Morph E2E Tests..."
bash scripts/test-astral-morph-e2e.sh

echo "[7/7] Running Cross-Platform TypeScript / Node.js Tests..."
node windows/tests/compact-lod.test.mjs
node windows/tests/expanded-lod.test.mjs

echo "=========================================================="
echo "  ✅ All Mascot Tests Passed Successfully! (0 Failures)  "
echo "=========================================================="
```
Make executable: `chmod +x scripts/test-all-mascot.sh`.

- [ ] **Step 2: Update `tests/AstralMorphE2ETests.swift` to assert all 5 Review Focus items**

Update `tests/AstralMorphE2ETests.swift`:
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

        print("1. Geometry & Overhang Compensation")
        check("Overhang 40 offset is 20", ShapeshifterGeometry.verticalOffset(particleOverhang: 40) == 20)
        check("Collapsed notch mode is compact", ShapeshifterGeometry.isCompactMode(mode: .hidden, isMini: false))

        print("2. 24 FPS Sprite Animation Pipeline & Fallback")
        let anim = SpriteSheetAnimator(config: .default(for: .writing))
        check("Writing cycle has 24 frames", anim.config.frameCount == 24)
        _ = anim.update(dt: 0.5)
        check("Midway frame index is 12", anim.currentFrameIndex == 12)
        check("Missing asset flags vector fallback", SpriteSheetLoader.shouldUseVectorFallback(action: .writing))

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

        print("5. Facade & Secondary Surfaces")
        check("working -> writing", ShapeshifterStateMapper.mapAction(state: "working") == .writing)
        check("searching -> reading", ShapeshifterStateMapper.mapAction(state: "searching") == .reading)
        check("Hub live mascot resolves shapeshifter when active", HubMascotResolver.isShapeshifterActive)

        print("=== E2E Test Result: \(failures) failures ===")
        if failures > 0 { exit(1) }
    }
}
```

- [ ] **Step 3: Run full verification suite**

Run: `bash scripts/test-all-mascot.sh`
Expected: PASS with all 7 suites reporting 0 failures.

- [ ] **Step 4: Verify Xcode Project build**

Run:
```bash
xcodegen generate --spec NotchBuddy/project.yml --project NotchBuddy
xcodebuild -scheme NotchBuddy -configuration Debug -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
```
Expected: `** BUILD SUCCEEDED **` with zero Swift 6 concurrency errors.

- [ ] **Step 5: Update `design/prototype/mascot-showcase.html` with interactive renders**

Add live interactive HTML5 Canvas demos to `design/prototype/mascot-showcase.html` showing:
1. Resting Notch preview (with black notch bezel overlay proving no clipping).
2. Mini agent pills (Claude, Gemini, Antigravity) with filled spirit body and glossy eyes.
3. Expanded card mascot with expressive face, flame crown, blush cheeks, and action props (writing, reading, thinking).

- [ ] **Step 6: Commit**

```bash
git add scripts/test-all-mascot.sh tests/AstralMorphE2ETests.swift design/prototype/mascot-showcase.html
git commit -m "test(mascot): full verification suite, xcodebuild pass and interactive showcase preview"
```
