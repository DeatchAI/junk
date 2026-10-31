import Foundation

@MainActor
protocol MessagesPollSending: AnyObject {
  var hasAccess: Bool { get }
  func send(_ decision: MessagesPollDecision, chatID: Int, recipient: String,
    isPending: @escaping () -> Bool) async throws -> MessagesCreatedPoll
}

@MainActor
extension MessagesRPCTransport {
  func call(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
    try await withCheckedThrowingContinuation { continuation in
      request(method, params: params) { continuation.resume(with: $0) }
    }
  }
}

/// Only a proven, cleaned-up failure before Return permits the next queued poll.
/// Uncertain submissions are never automatically sent again.
enum MessagesPollSendFailure: LocalizedError {
  case notSubmitted(String)
  case needsReview(String)

  var requiresPause: Bool {
    if case .notSubmitted = self { return false }
    return true
  }

  var errorDescription: String? {
    switch self {
    case .notSubmitted(let reason), .needsReview(let reason): return reason
    }
  }
}
