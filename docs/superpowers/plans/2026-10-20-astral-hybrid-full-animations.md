# Astral Hybrid Full Mascot Animations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved Hybrid Architecture (Variant 2: 3D Body + Procedural Physics + Expressive Vector Eyes) across ALL mascot states in NotchBuddy, replacing the legacy 2D procedural canvas ("cringe" cartoon drawings with mouths, cheeks, and flat props) with high-fidelity, zero-overhead 3D forms.

**Architecture:**
- **3D Master Bodies:** Clean raster master images without pre-drawn eyes for all 4 approved forms:
  - Ghost (`astral-body-480.png`) for `idle`, `sleeping`, `working`, `thinking`, `searching`
  - Orb (`astral-orb-480.png`) for `finished`
  - Cube (`astral-cube-480.png`) for `question`, `approval`, `permission`
  - Wisp (`astral-wisp-480.png`) for `error`, `ratelimit`, `dizzy`
- **Procedural Physics & Motion:**
  - Ghost: Sinusoidal float Y + squash & stretch breathing; focused micro-pulse for `working`; thoughtful drift for `thinking`; horizontal scan for `searching`.
  - Orb: Joyful bounce / hop with elastic compression on landing for `finished`.
  - Cube: Curious lateral tilt (6-8°) with attentive micro-hover for `question` / `approval`.
  - Wisp: Flame flicker vibration + jittery error shake for `error` / `ratelimit`.
- **Procedural Expressive Eyes:**
  - Awake / Idle: Vector glowing capsules, mouse tracking (`lookX`, `lookY`), periodic squash-blinks.
  - Sleeping: Soft glowing curved lines `∪ ∪`.
  - Finished: Joyful cheerful arcs `^ ^`.
  - Question / Approval: Curious tilted eyes (one eye slightly higher/larger).
  - Error / Dizzy: Dizzy spiral / spinning eyes `@ @` or alert rings.
  - Working: Focused, slightly narrower capsules tracking the active workspace.
  - Searching: Smooth horizontal back-and-forth gaze sweep.
- **Performance & Footprint:**
  - Memory: < 0.25 MB RAM per instance (shared texture cache).
  - CPU: Exactly 0.0% CPU when notch is collapsed / paused; < 0.2% on 120 FPS ProMotion.
  - Geometry: 22×22 pt in collapsed notch, 66×66 pt in expanded card, 13×13 pt in agent pills.

**Tech Stack:** Swift 6, AppKit / SwiftUI, CoreGraphics, Python 3 / Pillow, HTML5 / Canvas.

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `scripts/prepare-astral-hybrid-bodies.py` | Create | Script to clean eye regions from master 3D renders (Orb, Cube, Wisp) and export 480px / 240px PNGs |
| `design/mascot/astral-v2/astral-orb-{240,480}.png` | Create | Clean 3D Orb body without eyes |
| `design/mascot/astral-v2/astral-cube-{240,480}.png` | Create | Clean 3D Cube body without eyes |
| `design/mascot/astral-v2/astral-wisp-{240,480}.png` | Create | Clean 3D Wisp body without eyes |
| `NotchBuddy/Resources/Mascots/AstralHybrid/astral-orb-{240,480}.png` | Create | App resource: Clean 3D Orb body |
| `NotchBuddy/Resources/Mascots/AstralHybrid/astral-cube-{240,480}.png` | Create | App resource: Clean 3D Cube body |
| `NotchBuddy/Resources/Mascots/AstralHybrid/astral-wisp-{240,480}.png` | Create | App resource: Clean 3D Wisp body |
| `NotchBuddy/Sources/App/AstralHybridIdleAnimation.swift` | Modify/Expand | Full hybrid animation engine: multi-form asset loading, state-driven physics, procedural expressive eyes |
| `NotchBuddy/Sources/App/AstralHybridIdleView.swift` | Modify/Expand | Generalize `AstralHybridIdleView` to `AstralHybridView` supporting all `BotState` / `MascotActionState` |
| `NotchBuddy/Sources/App/BotCanvasView.swift` | Modify | Route ALL `selectedMascot == .shapeshifter` states to `AstralHybridView` (both main bot & `MiniBotCanvasView`) |
| `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterHostView.swift` | Modify | Forward all actions to AstralHybrid renderer, retiring 2D cartoon procedural fallback |
| `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` | Modify | Register new AstralHybrid PNG resources |
| `design/animations/hybrid-idle-prototype.html` | Modify | Update prototype to showcase all 4 forms and all 8 states live in browser |
| `tests/AstralHybridIdleTests.swift` | Modify/Expand | Comprehensive tests for multi-form physics, eye shapes, and memory loading |
| `tests/FlowHubTestStubs.swift` | Modify | Fix missing `AskQuestion` and `TelegramEvent` type declarations in test stubs |

---

## Tasks

### Task 1: Generate Clean 3D Master Bodies for Orb, Cube, and Wisp

**Files:**
- `scripts/prepare-astral-hybrid-bodies.py`
- `design/mascot/astral-v2/astral-{orb,cube,wisp}-{240,480}.png`
- `NotchBuddy/Resources/Mascots/AstralHybrid/astral-{orb,cube,wisp}-{240,480}.png`

- [ ] Write Python script `scripts/prepare-astral-hybrid-bodies.py` that loads:
  - `design/mascot/astral-v2/morph-kit/frames/astral-orb-480.png`
  - `design/mascot/astral-v2/morph-kit/frames/astral-cube-480.png`
  - `design/mascot/astral-v2/morph-kit/frames/astral-wisp-480.png`
  and seamlessly reconstructs the smooth glass body across the eye bbox (`x=144..335, y=96..277`) using surrounding glass gradient & texture interpolation.
- [ ] Generate 480×480 and 240×240 exports for Orb, Cube, and Wisp.
- [ ] Place generated files in `design/mascot/astral-v2/` and `NotchBuddy/Resources/Mascots/AstralHybrid/`.
- [ ] Verify image files exist, have correct dimensions, alpha transparency, and no artifacts.

---

### Task 2: Update Interactive HTML Prototype

**Files:**
- `design/animations/hybrid-idle-prototype.html`

- [ ] Add Form & State switcher:
  - Idle (Ghost)
  - Sleeping (Ghost)
  - Working (Ghost)
  - Thinking (Ghost)
  - Searching (Ghost)
  - Finished (Orb)
  - Question / Approval (Cube)
  - Error / Warning (Wisp)
- [ ] Embed the clean 480px bodies (Ghost, Orb, Cube, Wisp) as data URIs / local paths.
- [ ] Implement state-specific eye rendering (happy arcs, question tilt, dizzy `@ @`, sleeping `∪ ∪`, focused, normal) and physics (bounce, tilt, flame flicker, float) in JavaScript canvas.
- [ ] Verify prototype renders properly across hero (280pt), card (66pt), notch (22pt), and mini pill (13pt) preview slots.

---

### Task 3: Core Engine & Multi-Form Animation Logic

**Files:**
- `NotchBuddy/Sources/App/AstralHybridIdleAnimation.swift`

- [ ] Add `AstralHybridForm` enum:
  - `.ghost`: Idle, Sleeping, Working, Thinking, Searching
  - `.orb`: Finished
  - `.cube`: Question, Approval, Permission
  - `.wisp`: Error, Warning, RateLimit, Dizzy
- [ ] Add `AstralHybridState` mapping function `form(for state: BotState) -> AstralHybridForm` and `form(for action: MascotActionState) -> AstralHybridForm`.
- [ ] Expand `AstralHybridAssets` to load and cache `CGImage` for each form (`ghost`, `orb`, `cube`, `wisp`) at 480 and 240 resolution.
- [ ] Expand `AstralHybridMotion`:
  - `bounceY(at:amp:) -> Double` (cheerful hop with elastic squash for Orb)
  - `tiltAngle(at:maxAngle:) -> Double` (curious lateral tilt for Cube)
  - `flickerOffset(at:amp:) -> (dx: Double, dy: Double)` (high-frequency flame vibration for Wisp)
  - `searchGazeX(at:) -> Double` (smooth scanning sine sweep for Searching)
- [ ] Expand `AstralHybridRenderer`:
  - Draw body of the appropriate form.
  - Draw expressive eyes tailored to state:
    - Normal (looking at cursor, blinking)
    - Sleeping (`∪ ∪` arcs)
    - Happy (`^ ^` arcs with upward arch)
    - Questioning (curious tilt, asymmetric eye height)
    - Dizzy / Error (spiral `@ @` or crossed alert eyes)
    - Focused / Searching (narrowed or panning capsules)
  - Support custom image overrides for testing.

---

### Task 4: Connect into App Views & Xcode Resources

**Files:**
- `NotchBuddy/Sources/App/AstralHybridIdleView.swift`
- `NotchBuddy/Sources/App/BotCanvasView.swift`
- `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterHostView.swift`
- `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj`

- [ ] Rename/extend `AstralHybridIdleView` to `AstralHybridView(state:isPaused:lookX:lookY:)` supporting all `BotState` values.
- [ ] In `BotCanvasView.swift`:
  - Remove the branch that delegates non-idle states to `ShapeshifterHostView`.
  - For `MascotSettings.selectedMascot == .shapeshifter`, render `AstralHybridHostView` for ALL states (`idle`, `working`, `thinking`, `searching`, `finished`, `approval`, `question`, `error`, `sleeping`, etc.).
  - In `MiniBotCanvasView`: render `AstralHybridView` for all states at `CGSize(width: 13, height: 13)`.
- [ ] In `ShapeshifterHostView.swift`: bridge `ShapeshifterExpandedView` and `ShapeshifterCompactView` to `AstralHybridView`.
- [ ] Update `project.pbxproj` with file references for the 6 new PNG assets in `AstralHybrid`.

---

### Task 5: Tests and Verification

**Files:**
- `tests/FlowHubTestStubs.swift`
- `tests/AstralHybridIdleTests.swift`
- `scripts/test-astral-hybrid.sh`

- [ ] Fix missing `AskQuestion` and `TelegramEvent` type definitions in `tests/FlowHubTestStubs.swift`.
- [ ] Update `tests/AstralHybridIdleTests.swift` to verify:
  - Form resolution for every `BotState` and `MascotActionState`.
  - Math for `bounceY`, `tiltAngle`, `flickerOffset`, and `searchGazeX`.
  - Rendering of every form (`ghost`, `orb`, `cube`, `wisp`) across all states without crash.
  - Memory footprint and asset caching.
- [ ] Run `bash scripts/test-astral-hybrid.sh` and ensure 0 failures.
- [ ] Run `bash scripts/test-all-mascot.sh` and ensure all 7 verification suites pass with 0 failures.
