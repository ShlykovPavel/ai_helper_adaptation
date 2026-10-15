import Foundation

enum TelegramChatType: String, Codable, Equatable, Sendable { case `private` = "private", group, supergroup, channel }
struct TelegramChat: Codable, Equatable, Sendable { let id: Int64; let userId: Int64; let username: String?; let type: TelegramChatType }
struct TelegramPair: Equatable, Sendable { let chatId: Int64; let userId: Int64; let username: String? }
enum PairingError: Equatable, Error, Sendable { case invalidStart, invalidNonce, notPrivateChat, wrongUser, expired }

enum TelegramPairing {
    private static let lock = NSLock(); private static var issued: [String: Date] = [:]
    static func nonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16); _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let n = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        lock.lock(); issued[n] = Date(); lock.unlock(); return n
    }
    static func accept(start: String, expectedNonce: String, expectedUserId: Int64, chat: TelegramChat, now: Date) -> Result<TelegramPair, PairingError> {
        guard chat.type == .private else { return .failure(.notPrivateChat) }
        guard chat.userId == expectedUserId else { return .failure(.wrongUser) }
        let parts = start.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == "/start" else { return .failure(.invalidStart) }
        guard parts[1] == expectedNonce else { return .failure(.invalidNonce) }
        lock.lock(); issued = issued.filter { now.timeIntervalSince($0.value) < 600 }; let issuedAt = issued.removeValue(forKey: expectedNonce); lock.unlock()
        guard let issuedAt, now.timeIntervalSince(issuedAt) < 600 else { return .failure(.expired) }
        return .success(TelegramPair(chatId: chat.id, userId: chat.userId, username: chat.username))
    }
}
