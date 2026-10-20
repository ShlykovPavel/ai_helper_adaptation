// Minimal stubs for standalone test compilation.
// NOT compiled in the app — only used by test-hub-page.sh, test-facade.sh and telegram tests
import Foundation
import SwiftUI
import AppKit
import Combine

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

final class KeychainStore: @unchecked Sendable {
    static let shared = KeychainStore()
    private var store: [String: String] = [:]
    func get(_ key: String) -> String? { store[key] }
    func set(_ key: String, value: String) { store[key] = value }
    func remove(_ key: String) { store.removeValue(forKey: key) }
}

enum Keychain {
    static func load(key: String) -> String? { nil }
}

struct ApprovalInfo: Sendable {
    var sessionId: String
    var tool: String
    var command: String
    var inputKey: String
    var pillId: String
    var id: UUID = UUID()
    var queueCount: Int = 1
    var projectName: String? = nil
}

struct AskQuestion: Sendable {}
struct TelegramEvent: Sendable {}

final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var pendingApproval: ApprovalInfo? = nil
    @Published var pendingQuestion: AskQuestion? = nil
}

final class HookServer: @unchecked Sendable {
    static let shared = HookServer()
    static let events = PassthroughSubject<TelegramEvent, Never>()
    var lastApprovalDecision: String?
    var lastApprovalId: UUID?
    var lastQuestionAnswers: [String: Any]?

    func sendApprovalDecision(_ decision: String, for id: UUID? = nil) {
        lastApprovalDecision = decision
        lastApprovalId = id
    }

    func sendQuestionAnswers(_ answers: [String: Any]) {
        lastQuestionAnswers = answers
    }

    func sendQuestionAsk() {}
}
