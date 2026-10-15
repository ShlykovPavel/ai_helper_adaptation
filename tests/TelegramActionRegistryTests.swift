import Foundation
@main struct TelegramActionRegistryTests {
 static func main() async {
  let t = Date(timeIntervalSince1970: 1_000); let r = TelegramActionRegistry(clock: FixedClock(now: t))
  let a = await r.insert(kind: .approvalAllow, fingerprint: "fp", sessionId: "s", chatId: 10, userId: 20, messageId: 1)
  precondition(a.ref.count == 22 && !a.ref.contains("=") && !a.ref.contains("+") && !a.ref.contains("/"))
  let x1 = await r.consume(ref: a.ref, chatId: 99, userId: 20, now: t, fingerprint: "fp")
  let x2 = await r.consume(ref: a.ref, chatId: 10, userId: 20, now: t, fingerprint: "wrong")
  let x3 = await r.consume(ref: a.ref, chatId: 10, userId: 20, now: t, fingerprint: "fp")
  let x4 = await r.consume(ref: a.ref, chatId: 10, userId: 20, now: t, fingerprint: "fp")
  precondition(x1 == .rejected(.unauthorized)); precondition(x2 == .rejected(.fingerprintMismatch)); precondition(x3 == .accepted(a)); precondition(x4 == .rejected(.consumed))
  let b = await r.insert(kind: .questionSubmit, fingerprint: "q", sessionId: "s", chatId: 10, userId: 20, messageId: 1)
  let x5 = await r.consume(ref: b.ref, chatId: 10, userId: 20, now: t.addingTimeInterval(120), fingerprint: "q"); precondition(x5 == .rejected(.expired)); runTelegramPairingTests(); print("TelegramActionRegistryTests: PASS")
 }
}
