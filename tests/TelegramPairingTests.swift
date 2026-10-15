import Foundation
func runTelegramPairingTests() {
  let now = Date()
  let nonce = TelegramPairing.nonce()
  let chat = TelegramChat(id: 42, userId: 7, username: "alice", type: .private)
  switch TelegramPairing.accept(start: "/start \(nonce)", expectedNonce: nonce, chat: chat, now: now) { case .success(let p): precondition(p.chatId == 42 && p.userId == 7); case .failure: preconditionFailure() }
  let group = TelegramChat(id: -1, userId: 7, username: nil, type: .group)
  precondition(TelegramPairing.accept(start: "/start \(nonce)", expectedNonce: nonce, chat: group, now: now) == .failure(.notPrivateChat))
  precondition(TelegramPairing.accept(start: "/start wrong", expectedNonce: nonce, chat: chat, now: now) == .failure(.invalidNonce))
  precondition(TelegramPairing.accept(start: "/start \(nonce)", expectedNonce: nonce, chat: chat, now: now.addingTimeInterval(601)) == .failure(.expired))
  print("TelegramPairingTests: PASS")
}
