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
