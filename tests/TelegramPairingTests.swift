import Foundation
func runTelegramPairingTests() {
  let now = Date()
  let nonce = TelegramPairing.nonce()
  let chat = TelegramChat(id: 42, userId: 7, username: "alice", type: .private)
  switch TelegramPairing.accept(start: "/start \(nonce)", expectedNonce: nonce, expectedUserId: 7, chat: chat, now: now) { case .success(let p): precondition(p.chatId == 42 && p.userId == 7); case .failure: preconditionFailure() }
  let group = TelegramChat(id: -1, userId: 7, username: nil, type: .group)
  precondition(TelegramPairing.accept(start: "/start \(nonce)", expectedNonce: nonce, expectedUserId: 7, chat: group, now: now) == .failure(.notPrivateChat))
  let wrong = TelegramChat(id: 43, userId: 8, username: "other", type: .private)
  let nonce2 = TelegramPairing.nonce()
  precondition(TelegramPairing.accept(start: "/start \(nonce2)", expectedNonce: nonce2, expectedUserId: 7, chat: wrong, now: now) == .failure(.wrongUser))
  let nonce3 = TelegramPairing.nonce()
  precondition(TelegramPairing.accept(start: "/start \(nonce3)", expectedNonce: nonce3, expectedUserId: 7, chat: chat, now: now.addingTimeInterval(601)) == .failure(.expired))
  print("TelegramPairingTests: PASS")
}
