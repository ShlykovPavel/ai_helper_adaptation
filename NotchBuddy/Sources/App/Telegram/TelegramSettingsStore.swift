import Foundation
import Combine

// MARK: - Token Store Protocol & Default Keychain Implementation

protocol TelegramTokenStore: AnyObject, Sendable {
    func getToken() -> String?
    func setToken(_ token: String)
    func removeToken()
}

final class DefaultTelegramTokenStore: TelegramTokenStore {
    private let key = "telegram-bot-token"

    func getToken() -> String? {
        KeychainStore.shared.get(key) ?? Keychain.load(key: key)
    }

    func setToken(_ token: String) {
        KeychainStore.shared.set(key, value: token)
    }

    func removeToken() {
        KeychainStore.shared.remove(key)
    }
}

// MARK: - Status Projection

struct TelegramStatusProjection: Equatable, Sendable {
    let isTokenConfigured: Bool
    let isEnabled: Bool
    let isPaired: Bool
    let pairedBotUsername: String?
    let pairedChatId: Int64?
    let pairedUserId: Int64?
    let connectionStatus: TelegramConnectionStatus

    init(
        isTokenConfigured: Bool,
        isEnabled: Bool,
        isPaired: Bool,
        pairedBotUsername: String?,
        pairedChatId: Int64?,
        pairedUserId: Int64?,
        connectionStatus: TelegramConnectionStatus = .idle
    ) {
        self.isTokenConfigured = isTokenConfigured
        self.isEnabled = isEnabled
        self.isPaired = isPaired
        self.pairedBotUsername = pairedBotUsername
        self.pairedChatId = pairedChatId
        self.pairedUserId = pairedUserId
        self.connectionStatus = connectionStatus
    }

    var maskedChatId: String? {
        guard let id = pairedChatId else { return nil }
        let str = String(id)
        if str.count <= 4 { return str }
        return "\(str.prefix(2))...\(str.suffix(2))"
    }
}

// MARK: - TelegramSettingsStore

@MainActor
final class TelegramSettingsStore: ObservableObject {
    static let shared = TelegramSettingsStore()

    enum Keys {
        static let enabled = "telegram.enabled"
        static let notifyFinished = "telegram.notifyFinished"
        static let notifyQuestions = "telegram.notifyQuestions"
        static let notifyApprovals = "telegram.notifyApprovals"
        static let pairedChatId = "telegram.pairedChatId"
        static let pairedUserId = "telegram.pairedUserId"
        static let pairedBotUsername = "telegram.pairedBotUsername"
        static let pairingNonce = "telegram.pairingNonce"
        static let pairingExpiresAt = "telegram.pairingExpiresAt"
        static let expectedUserId = "telegram.expectedUserId"
    }

    private let defaults: UserDefaults
    private let tokenStore: any TelegramTokenStore
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var settings: TelegramSettings
    @Published private(set) var hasToken: Bool = false
    @Published var connectionStatus: TelegramConnectionStatus = .idle

    init(
        defaults: UserDefaults = .standard,
        tokenStore: (any TelegramTokenStore)? = nil
    ) {
        self.defaults = defaults
        self.tokenStore = tokenStore ?? DefaultTelegramTokenStore()
        let initialSettings = Self.readSettings(from: defaults)
        self.settings = initialSettings
        self.hasToken = (self.tokenStore.getToken()?.isEmpty == false)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                _ = self?.load()
            }
            .store(in: &cancellables)
    }

    // MARK: - Load & Save

    func load() -> TelegramSettings {
        let loaded = Self.readSettings(from: defaults)
        self.settings = loaded
        self.hasToken = (tokenStore.getToken()?.isEmpty == false)
        return loaded
    }

    func save(_ newSettings: TelegramSettings, token: String? = nil) {
        defaults.set(newSettings.enabled, forKey: Keys.enabled)
        defaults.set(newSettings.notifyFinished, forKey: Keys.notifyFinished)
        defaults.set(newSettings.notifyQuestions, forKey: Keys.notifyQuestions)
        defaults.set(newSettings.notifyApprovals, forKey: Keys.notifyApprovals)

        if let chatId = newSettings.pairedChatId {
            defaults.set(chatId, forKey: Keys.pairedChatId)
        } else {
            defaults.removeObject(forKey: Keys.pairedChatId)
        }

        if let userId = newSettings.pairedUserId {
            defaults.set(userId, forKey: Keys.pairedUserId)
        } else {
            defaults.removeObject(forKey: Keys.pairedUserId)
        }

        if let username = newSettings.pairedBotUsername {
            defaults.set(username, forKey: Keys.pairedBotUsername)
        } else {
            defaults.removeObject(forKey: Keys.pairedBotUsername)
        }

        if let token = token, !token.isEmpty {
            tokenStore.setToken(token)
        }

        self.settings = newSettings
        self.hasToken = (tokenStore.getToken()?.isEmpty == false)
    }

    // MARK: - Clear & Reset

    func clear() {
        defaults.removeObject(forKey: Keys.enabled)
        defaults.removeObject(forKey: Keys.notifyFinished)
        defaults.removeObject(forKey: Keys.notifyQuestions)
        defaults.removeObject(forKey: Keys.notifyApprovals)
        defaults.removeObject(forKey: Keys.pairedChatId)
        defaults.removeObject(forKey: Keys.pairedUserId)
        defaults.removeObject(forKey: Keys.pairedBotUsername)
        defaults.removeObject(forKey: Keys.pairingNonce)
        defaults.removeObject(forKey: Keys.pairingExpiresAt)
        defaults.removeObject(forKey: Keys.expectedUserId)

        tokenStore.removeToken()

        self.settings = TelegramSettings()
        self.hasToken = false
        self.connectionStatus = .idle
    }

    // MARK: - Pairing Helpers

    func savePairingNonce(_ nonce: String, expiresAt: Date = Date().addingTimeInterval(600)) {
        defaults.set(nonce, forKey: Keys.pairingNonce)
        defaults.set(expiresAt.timeIntervalSince1970, forKey: Keys.pairingExpiresAt)
    }

    func getPairingNonce() -> String? {
        defaults.string(forKey: Keys.pairingNonce)
    }

    func getPairingExpiresAt() -> Date? {
        guard defaults.object(forKey: Keys.pairingExpiresAt) != nil else { return nil }
        let interval = defaults.double(forKey: Keys.pairingExpiresAt)
        return Date(timeIntervalSince1970: interval)
    }

    func clearPairing() {
        defaults.removeObject(forKey: Keys.pairedChatId)
        defaults.removeObject(forKey: Keys.pairedUserId)
        defaults.removeObject(forKey: Keys.pairingNonce)
        defaults.removeObject(forKey: Keys.pairingExpiresAt)
        defaults.removeObject(forKey: Keys.expectedUserId)

        var current = load()
        current.pairedChatId = nil
        current.pairedUserId = nil
        self.settings = current
    }

    // MARK: - Pairing Link

    func pairingLink(nonce: String, botUsername: String) -> URL? {
        Self.pairingLink(nonce: nonce, botUsername: botUsername)
    }

    static func pairingLink(nonce: String, botUsername: String) -> URL? {
        let trimmedNonce = nonce.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBot = botUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNonce.isEmpty, !trimmedBot.isEmpty else { return nil }
        let cleanUsername = trimmedBot.hasPrefix("@") ? String(trimmedBot.dropFirst()) : trimmedBot
        guard !cleanUsername.isEmpty else { return nil }
        return URL(string: "https://t.me/\(cleanUsername)?start=\(trimmedNonce)")
    }

    // MARK: - Status Projection

    var statusProjection: TelegramStatusProjection {
        statusProjection(connectionStatus: self.connectionStatus)
    }

    var status: TelegramStatusProjection {
        statusProjection
    }

    func statusProjection(connectionStatus: TelegramConnectionStatus) -> TelegramStatusProjection {
        let s = load()
        let hasTok = (tokenStore.getToken()?.isEmpty == false)
        let isPaired = s.pairedChatId != nil && s.pairedUserId != nil
        return TelegramStatusProjection(
            isTokenConfigured: hasTok,
            isEnabled: s.enabled,
            isPaired: isPaired,
            pairedBotUsername: s.pairedBotUsername,
            pairedChatId: s.pairedChatId,
            pairedUserId: s.pairedUserId,
            connectionStatus: connectionStatus
        )
    }

    // MARK: - Internal Helper

    private static func readSettings(from defaults: UserDefaults) -> TelegramSettings {
        let enabled = defaults.bool(forKey: Keys.enabled)
        let notifyFinished = defaults.object(forKey: Keys.notifyFinished) as? Bool ?? true
        let notifyQuestions = defaults.object(forKey: Keys.notifyQuestions) as? Bool ?? true
        let notifyApprovals = defaults.object(forKey: Keys.notifyApprovals) as? Bool ?? true
        let pairedChatId = defaults.object(forKey: Keys.pairedChatId) as? Int64
            ?? (defaults.object(forKey: Keys.pairedChatId) as? NSNumber)?.int64Value
        let pairedUserId = defaults.object(forKey: Keys.pairedUserId) as? Int64
            ?? (defaults.object(forKey: Keys.pairedUserId) as? NSNumber)?.int64Value
        let pairedBotUsername = defaults.string(forKey: Keys.pairedBotUsername)

        return TelegramSettings(
            enabled: enabled,
            notifyFinished: notifyFinished,
            notifyQuestions: notifyQuestions,
            notifyApprovals: notifyApprovals,
            pairedChatId: pairedChatId,
            pairedUserId: pairedUserId,
            pairedBotUsername: pairedBotUsername
        )
    }
}
