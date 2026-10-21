import Foundation

actor TelegramActionRegistry {
    private struct Entry { var action: TelegramAction; var consumed = false }
    private var entries: [String: Entry] = [:]
    private let clock: any TelegramClock
    private static let ttl: TimeInterval = 120
    init(clock: any TelegramClock = SystemTelegramClock()) { self.clock = clock }

    func insert(kind: TelegramActionKind, fingerprint: String, sessionId: String = "", chatId: Int64, userId: Int64, messageId: Int64 = 0, requestId: UUID? = nil) -> TelegramAction {
        prune(now: clock.now)
        while entries.count >= 64, let oldest = entries.min(by: { $0.value.action.expiresAt < $1.value.action.expiresAt }) { entries.removeValue(forKey: oldest.key) }
        let ref = Self.makeRef()
        let action = TelegramAction(ref: ref, kind: kind, fingerprint: fingerprint, sessionId: sessionId, expiresAt: clock.now.addingTimeInterval(Self.ttl), chatId: chatId, userId: userId, messageId: messageId, requestId: requestId)
        entries[ref] = Entry(action: action)
        return action
    }

    func consume(ref: String, chatId: Int64, userId: Int64, now: Date? = nil, fingerprint: String) -> TelegramActionResult {
        let instant = now ?? clock.now
        guard var entry = entries[ref] else { return .rejected(.unknown) }
        guard instant < entry.action.expiresAt else { entries.removeValue(forKey: ref); return .rejected(.expired) }
        guard entry.action.chatId == chatId && entry.action.userId == userId else { return .rejected(.unauthorized) }
        guard !entry.consumed else { return .rejected(.consumed) }
        if fingerprint != entry.action.fingerprint { return .rejected(.fingerprintMismatch) }
        entry.consumed = true; entries[ref] = entry
        return .accepted(entry.action)
    }

    private func prune(now: Date) { entries = entries.filter { $0.value.action.expiresAt > now && !$0.value.consumed } }
    private static func makeRef() -> String {
        var bytes = [UInt8](repeating: 0, count: 16); _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
