import Foundation

// MARK: - Standalone Test Doubles for Compilation

#if !APPSTORE
final class KeychainStore: @unchecked Sendable {
    static let shared = KeychainStore()
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    func get(_ key: String) -> String? {
        lock.withLock { storage[key] }
    }

    func set(_ key: String, value: String) {
        lock.withLock { storage[key] = value }
    }

    func remove(_ key: String) {
        _ = lock.withLock { storage.removeValue(forKey: key) }
    }

    func clear() {
        lock.withLock { storage.removeAll() }
    }
}

enum Keychain {
    static func load(key: String) -> String? {
        KeychainStore.shared.get(key)
    }
}
#endif

final class TestTokenStore: TelegramTokenStore, @unchecked Sendable {
    private var storedToken: String?
    private let lock = NSLock()

    init(token: String? = nil) {
        self.storedToken = token
    }

    func getToken() -> String? {
        lock.withLock { storedToken }
    }

    func setToken(_ token: String) {
        lock.withLock { storedToken = token }
    }

    func removeToken() {
        lock.withLock { storedToken = nil }
    }
}

// MARK: - Test Runner

@main
@MainActor
struct TelegramSettingsTestRunner {
    static func main() async {
        print("Running TelegramSettingsTests...")

        await testEnabledAndNotificationFlagsRoundTrip()
        await testClearRemovesTokenAndPairingMetadata()
        await testSerializedSettingsNeverContainsToken()
        await testStatusProjectionPropertiesAndMasking()
        await testPairingLinkFormatting()
        await testRepairClearsPairingKeepsToken()

        print("TelegramSettingsTests: ALL TESTS PASSED ✅")
    }

    static func makeIsolatedStore() -> (store: TelegramSettingsStore, defaults: UserDefaults, tokenStore: TestTokenStore, suiteName: String) {
        let suiteName = "test.telegram.settings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create isolated UserDefaults with suite: \(suiteName)")
        }
        let tokenStore = TestTokenStore()
        let store = TelegramSettingsStore(defaults: defaults, tokenStore: tokenStore)
        return (store, defaults, tokenStore, suiteName)
    }

    static func cleanup(suiteName: String, defaults: UserDefaults) {
        defaults.removePersistentDomain(forName: suiteName)
    }

    static func testEnabledAndNotificationFlagsRoundTrip() async {
        let (store, defaults, tokenStore, suite) = makeIsolatedStore()
        defer { cleanup(suiteName: suite, defaults: defaults) }

        // 1. Initial state
        let initial = store.load()
        precondition(!initial.enabled, "Expected enabled to default to false")
        precondition(initial.notifyFinished, "Expected notifyFinished to default to true")
        precondition(initial.notifyQuestions, "Expected notifyQuestions to default to true")
        precondition(initial.notifyApprovals, "Expected notifyApprovals to default to true")
        precondition(initial.pairedChatId == nil, "Expected pairedChatId to default to nil")
        precondition(initial.pairedUserId == nil, "Expected pairedUserId to default to nil")
        precondition(initial.pairedBotUsername == nil, "Expected pairedBotUsername to default to nil")
        precondition(!store.statusProjection.isTokenConfigured, "Token should not be configured initially")

        // 2. Modify flags and save with token
        var modified = initial
        modified.enabled = true
        modified.notifyFinished = false
        modified.notifyQuestions = false
        modified.notifyApprovals = true
        let testToken = "123456789:ABC-DEF_ghi-JKL"
        store.save(modified, token: testToken)

        // 3. Verify in new store instance with same defaults & tokenStore
        let store2 = TelegramSettingsStore(defaults: defaults, tokenStore: tokenStore)
        let loaded = store2.load()
        precondition(loaded.enabled == true, "Round-trip enabled failed")
        precondition(loaded.notifyFinished == false, "Round-trip notifyFinished failed")
        precondition(loaded.notifyQuestions == false, "Round-trip notifyQuestions failed")
        precondition(loaded.notifyApprovals == true, "Round-trip notifyApprovals failed")
        precondition(tokenStore.getToken() == testToken, "Token was not stored in token store")
        precondition(store2.statusProjection.isTokenConfigured == true, "statusProjection.isTokenConfigured should be true")

        print("  - testEnabledAndNotificationFlagsRoundTrip: PASS")
    }

    static func testClearRemovesTokenAndPairingMetadata() async {
        let (store, defaults, tokenStore, suite) = makeIsolatedStore()
        defer { cleanup(suiteName: suite, defaults: defaults) }

        var settings = store.load()
        settings.enabled = true
        settings.pairedChatId = 987654321
        settings.pairedUserId = 123456789
        settings.pairedBotUsername = "my_coucou_bot"
        let testToken = "987654321:XYZ-SECRET-TOKEN"
        store.save(settings, token: testToken)
        store.savePairingNonce("pairing-nonce-abc", expiresAt: Date().addingTimeInterval(600))

        precondition(store.statusProjection.isPaired == true, "Expected store to report paired")
        precondition(store.statusProjection.isTokenConfigured == true, "Expected store to have token")
        precondition(defaults.string(forKey: "telegram.pairingNonce") == "pairing-nonce-abc", "Nonce should be set")

        // Clear everything
        store.clear()

        let cleared = store.load()
        precondition(!cleared.enabled, "Clear should reset enabled")
        precondition(cleared.pairedChatId == nil, "Clear should reset pairedChatId")
        precondition(cleared.pairedUserId == nil, "Clear should reset pairedUserId")
        precondition(cleared.pairedBotUsername == nil, "Clear should reset pairedBotUsername")
        precondition(defaults.object(forKey: "telegram.pairingNonce") == nil, "Clear should remove nonce")
        precondition(defaults.object(forKey: "telegram.pairingExpiresAt") == nil, "Clear should remove expiry")
        precondition(tokenStore.getToken() == nil, "Clear should remove token from token store")
        precondition(!store.statusProjection.isTokenConfigured, "Status projection should show no token")
        precondition(!store.statusProjection.isPaired, "Status projection should show not paired")

        print("  - testClearRemovesTokenAndPairingMetadata: PASS")
    }

    static func testSerializedSettingsNeverContainsToken() async {
        let (store, defaults, _, suite) = makeIsolatedStore()
        defer { cleanup(suiteName: suite, defaults: defaults) }

        let secretToken = "super-secret-bot-token-never-leak-987"
        let settings = TelegramSettings(
            enabled: true,
            notifyFinished: true,
            notifyQuestions: true,
            notifyApprovals: true,
            pairedChatId: 555666777,
            pairedUserId: 111222333,
            pairedBotUsername: "coucou_test_bot"
        )
        store.save(settings, token: secretToken)

        // Verify JSON serialization of TelegramSettings
        let encoder = JSONEncoder()
        let data = try! encoder.encode(settings)
        let jsonStr = String(data: data, encoding: .utf8)!

        precondition(!jsonStr.contains(secretToken), "Serialized settings leaked the raw token!")
        precondition(!jsonStr.contains("token"), "Serialized settings schema leaked token key!")

        // Verify isolated UserDefaults contains no trace of raw token
        let dict = defaults.dictionaryRepresentation()
        for (key, val) in dict where key.hasPrefix("telegram.") {
            let valStr = String(describing: val)
            precondition(!valStr.contains(secretToken), "UserDefaults key '\(key)' leaked secret token: \(valStr)")
        }

        print("  - testSerializedSettingsNeverContainsToken: PASS")
    }

    static func testStatusProjectionPropertiesAndMasking() async {
        let (store, defaults, _, suite) = makeIsolatedStore()
        defer { cleanup(suiteName: suite, defaults: defaults) }

        let secretToken = "token-for-status-check"
        var settings = store.load()
        settings.enabled = true
        settings.pairedChatId = 123456789
        settings.pairedUserId = 987654321
        settings.pairedBotUsername = "my_bot"
        store.save(settings, token: secretToken)

        let projection = store.statusProjection
        precondition(projection.isTokenConfigured == true)
        precondition(projection.isEnabled == true)
        precondition(projection.isPaired == true)
        precondition(projection.pairedBotUsername == "my_bot")
        precondition(projection.pairedChatId == 123456789)
        precondition(projection.pairedUserId == 987654321)
        precondition(projection.maskedChatId == "12...89", "Expected maskedChatId to be 12...89, got \(String(describing: projection.maskedChatId))")

        // Short ID masking check
        var shortSettings = settings
        shortSettings.pairedChatId = 42
        store.save(shortSettings, token: nil)
        precondition(store.statusProjection.maskedChatId == "42", "Short IDs should not be truncated")

        // Ensure status projection does not expose raw token via reflection
        let mirror = Mirror(reflecting: projection)
        for child in mirror.children {
            let childVal = String(describing: child.value)
            precondition(!childVal.contains(secretToken), "Status projection exposed token in property '\(child.label ?? "")'")
        }

        print("  - testStatusProjectionPropertiesAndMasking: PASS")
    }

    static func testPairingLinkFormatting() async {
        precondition(TelegramSettingsStore.pairingLink(nonce: "nonce123", botUsername: "coucoubot")?.absoluteString == "https://t.me/coucoubot?start=nonce123")
        precondition(TelegramSettingsStore.pairingLink(nonce: "nonce123", botUsername: "@coucoubot")?.absoluteString == "https://t.me/coucoubot?start=nonce123")
        precondition(TelegramSettingsStore.pairingLink(nonce: "", botUsername: "coucoubot") == nil)
        precondition(TelegramSettingsStore.pairingLink(nonce: "nonce123", botUsername: "") == nil)
        precondition(TelegramSettingsStore.pairingLink(nonce: "nonce123", botUsername: "@") == nil)

        let (store, defaults, _, suite) = makeIsolatedStore()
        defer { cleanup(suiteName: suite, defaults: defaults) }
        precondition(store.pairingLink(nonce: "nonce_inst", botUsername: "inst_bot")?.absoluteString == "https://t.me/inst_bot?start=nonce_inst")

        print("  - testPairingLinkFormatting: PASS")
    }

    static func testRepairClearsPairingKeepsToken() async {
        let (store, defaults, tokenStore, suite) = makeIsolatedStore()
        defer { cleanup(suiteName: suite, defaults: defaults) }

        var settings = store.load()
        settings.enabled = true
        settings.pairedChatId = 1111
        settings.pairedUserId = 2222
        settings.pairedBotUsername = "old_bot"
        let token = "token-to-keep"
        store.save(settings, token: token)
        store.savePairingNonce("old-nonce", expiresAt: Date().addingTimeInterval(600))

        precondition(store.statusProjection.isPaired == true)
        precondition(store.statusProjection.isTokenConfigured == true)

        // Clear pairing only (as in Re-pair flow)
        store.clearPairing()

        let reloaded = store.load()
        precondition(reloaded.pairedChatId == nil, "pairedChatId should be nil after clearPairing")
        precondition(reloaded.pairedUserId == nil, "pairedUserId should be nil after clearPairing")
        precondition(reloaded.pairedBotUsername == nil, "pairedBotUsername should be nil after clearPairing")
        precondition(defaults.object(forKey: "telegram.pairingNonce") == nil, "nonce should be cleared")
        precondition(tokenStore.getToken() == token, "Token must be preserved during re-pair")
        precondition(store.statusProjection.isTokenConfigured == true, "Token status should remain configured")
        precondition(!store.statusProjection.isPaired, "Pairing status should be false")

        print("  - testRepairClearsPairingKeepsToken: PASS")
    }
}
