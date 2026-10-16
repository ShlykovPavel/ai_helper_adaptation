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
        let active = MascotSettings.selectedMascot
        check("Initial mascot is shapeshifter", active == .shapeshifter)
        MascotSettings.selectedMascot = .mochi
        check("Switched to mochi", MascotSettings.selectedMascot == .mochi)
        MascotSettings.selectedMascot = .shapeshifter
        check("Switched back to shapeshifter", MascotSettings.selectedMascot == .shapeshifter)

        print("ShapeshifterFacadeTests finished with \(failures) failures.")
        if failures > 0 { exit(1) }
    }
}
