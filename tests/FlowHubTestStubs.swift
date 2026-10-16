// Minimal stubs for standalone FlowHub test compilation.
// NOT compiled in the app — only used by test-hub-page.sh and test-facade.sh
import Foundation
import SwiftUI
import AppKit

extension Color {
    init(hex: String) { self = .clear }
}

final class HubWindowState: ObservableObject {
    @Published var visible: Bool = false
    func watch(_ win: NSWindow) {}
}

private struct HubVisibleKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var hubVisible: Bool {
        get { self[HubVisibleKey.self] }
        set { self[HubVisibleKey.self] = newValue }
    }
}

final class FlowDictation: ObservableObject {
    struct Key { var label: String = "" }
    static let shared = FlowDictation()
    var isEnabled: Bool = false
    var trusted: Bool = false
    var key: Key = Key()
}

struct HubHomePage: View { var router: Any; var body: some View { EmptyView() } }
struct HubNotesPage: View { var body: some View { EmptyView() } }
struct HubInsightsPage: View { var body: some View { EmptyView() } }
struct HubDictionaryPage: View { var body: some View { EmptyView() } }
struct HubSnippetsPage: View { var body: some View { EmptyView() } }
struct HubStylesPage: View { var router: Any; var body: some View { EmptyView() } }
struct HubSettingsPage: View { var body: some View { EmptyView() } }
struct SettingsView: View { var embeddedSection: String; var body: some View { EmptyView() } }
struct HubLiveMochi: View { init(size: CGFloat) {}; var body: some View { EmptyView() } }
struct HubLiveMascot: View {
    var color = "#F5F6F8"
    var size: CGFloat = 28
    init(size: CGFloat = 28) { self.size = size }
    init(color: String = "#F5F6F8", size: CGFloat = 28) {
        self.color = color
        self.size = size
    }
    var body: some View { EmptyView() }
}

#if STANDALONE_CLI
enum HubPage: String, CaseIterable, Identifiable {
    case tunnelGuard
    var id: String { rawValue }
}

public enum HubMascotResolver {
    public static var isShapeshifterActive: Bool {
        return MascotSettings.selectedMascot == .shapeshifter
    }
}

struct HubHeroTheme {
    var colorHex: String
    var usesShapeshifterHero: Bool {
        MascotSettings.selectedMascot == .shapeshifter
    }
    static func of(_ page: HubPage) -> HubHeroTheme {
        switch page {
        case .tunnelGuard:
            return HubHeroTheme(colorHex: "#30D158")
        }
    }
}
#endif

struct HubHero<Trailing: View>: View {
    init(page: HubPage, title: String, subtitle: String?) where Trailing == EmptyView {}
    init(page: HubPage, title: String, subtitle: String?, @ViewBuilder trailing: () -> Trailing) {}
    var body: some View { EmptyView() }
}
