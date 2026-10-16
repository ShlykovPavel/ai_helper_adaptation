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
