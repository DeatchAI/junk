import Combine
import Foundation
import LocalAuthentication

enum SecretAccessOutcome: String, Codable {
  case used
  case denied
  case failed

  var title: String {
    switch self {
    case .used: return "Used"
    case .denied: return "Not approved"
    case .failed: return "Could not use"
    }
  }
}

struct SecretAccessRecord: Codable, Identifiable, Equatable {
  let id: UUID
  let timestamp: Date
  let credentialId: String
  let credentialLabel: String
  let origin: String
  let action: String
  let outcome: SecretAccessOutcome
  let runId: String?
  let conversationId: String?
}

/// Append-only, encrypted history of credential-use attempts.
/// It deliberately excludes usernames, passwords, tokens, and error strings.
@MainActor
final class SecretAccessAudit: ObservableObject {
  static let shared = SecretAccessAudit()

  @Published private(set) var records: [SecretAccessRecord] = []
  private let store = EncryptedSecretStore.shared
  private let recordName = "access-history-v1"

  private init() {
    do {
      records = try store.load([SecretAccessRecord].self, named: recordName) ?? []
    } catch {
      // A damaged audit file must not prevent access to credentials. New events
      // are retained in memory and will replace it after the next successful save.
      records = []
    }
  }

  func record(
    credential: SecretCredential,
    origin: String,
    outcome: SecretAccessOutcome,
    runId: String?,
    conversationId: String?
  ) {
    let entry = SecretAccessRecord(
      id: UUID(),
      timestamp: .now,
      credentialId: credential.id,
      credentialLabel: credential.label,
      origin: origin,
      action: "Browser sign-in",
      outcome: outcome,
      runId: runId,
      conversationId: conversationId
    )
    records.insert(entry, at: 0)
    try? store.save(records, named: recordName)
  }

  func outcome(for error: Error) -> SecretAccessOutcome {
    let nsError = error as NSError
    guard nsError.domain == LAError.errorDomain else { return .failed }
    switch LAError.Code(rawValue: nsError.code) {
    case .userCancel, .appCancel, .systemCancel:
      return .denied
    default:
      return .failed
    }
  }
}
