import Foundation

struct AgentToast: Equatable, Sendable {
    let pillId: String
    let message: String
    let colorHex: String
    var timestamp: Date = Date()
}
