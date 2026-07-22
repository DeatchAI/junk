import Combine
import Foundation
import LocalAuthentication
import Security

struct SecretCredential: Codable, Identifiable, Equatable {
  let id: String
  var label: String
  var username: String
  var origin: String
  var createdAt: Date

  var maskedUsername: String {
    guard !username.isEmpty else { return "Hidden account" }
    if let at = username.firstIndex(of: "@") {
      let prefix = username[..<at]
      return "\(prefix.prefix(1))•••@\(username[username.index(after: at)...])"
    }
    return "\(username.prefix(1))•••"
  }
}

enum SecretVaultError: LocalizedError {
  case notFound
  case keychain(OSStatus)
  case invalidImport(String)

  var errorDescription: String? {
    switch self {
    case .notFound: return "Credential not found."
    case .keychain(let status): return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain operation failed (\(status))."
    case .invalidImport(let message): return message
    }
  }
}

struct SecretCSVImportPreview: Identifiable, Equatable {
  let id: UUID
  let fileName: String
  let totalRows: Int
  let importableCount: Int
  let duplicateCount: Int
  let skippedCount: Int
  let sampleLabels: [String]
}

struct SecretCSVImportResult: Equatable {
  let importedCount: Int
  let duplicateCount: Int
  let skippedCount: Int
}

/// Stores values only in the macOS Keychain. Metadata is encrypted before disk storage.
@MainActor
final class SecretVault: ObservableObject {
  static let shared = SecretVault()

  @Published private(set) var credentials: [SecretCredential] = []
  private let service = "com.lazzy.secrets.credentials"
  private let encryptedMetadataName = "credential-metadata-v1"
  private let legacyMetadataKey = "detach.secretCredentialMetadata.v1"
  private let encryptedStore = EncryptedSecretStore.shared
  private var pendingImports: [UUID: [PendingImportCredential]] = [:]

  private init() { loadMetadata() }

  func add(label: String, username: String, password: String, origin: String) throws {
    let credential = SecretCredential(id: UUID().uuidString, label: label, username: username, origin: normalizedOrigin(origin), createdAt: .now)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: credential.id,
      kSecAttrLabel as String: credential.label,
      kSecValueData as String: Data(password.utf8),
    ]
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else { throw SecretVaultError.keychain(status) }
    credentials.append(credential)
    do {
      try persistMetadata()
    } catch {
      credentials.removeAll { $0.id == credential.id }
      SecItemDelete(query as CFDictionary)
      throw error
    }
  }

  func remove(_ credential: SecretCredential) {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: credential.id]
    SecItemDelete(query as CFDictionary)
    credentials.removeAll { $0.id == credential.id }
    try? persistMetadata()
  }

  /// Reads an Apple Passwords CSV locally and keeps the raw values in memory only
  /// until the user confirms import. Nothing from the export crosses a socket.
  func previewApplePasswordsCSV(at url: URL) throws -> SecretCSVImportPreview {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let data = try Data(contentsOf: url)
    guard data.count <= 25_000_000 else { throw SecretVaultError.invalidImport("This export is too large to import safely.") }
    guard let text = String(data: data, encoding: .utf8) else { throw SecretVaultError.invalidImport("The export must be a UTF-8 CSV file.") }

    let rows = CSVParser.parse(text)
    guard let header = rows.first else { throw SecretVaultError.invalidImport("The CSV file is empty.") }
    let headerMap = Dictionary(uniqueKeysWithValues: header.enumerated().map { (normalizedHeader($0.element), $0.offset) })
    guard let urlIndex = headerMap["url"], let usernameIndex = headerMap["username"], let passwordIndex = headerMap["password"] else {
      throw SecretVaultError.invalidImport("Expected URL, Username, and Password columns from Apple Passwords.")
    }
    let titleIndex = headerMap["title"] ?? headerMap["name"]
    let pendingID = UUID()
    var pending: [PendingImportCredential] = []
    var duplicates = 0
    var skipped = 0
    var seen = Set<String>()

    for row in rows.dropFirst() {
      guard let rawURL = row[safe: urlIndex], let username = row[safe: usernameIndex], let password = row[safe: passwordIndex], !rawURL.isEmpty, !password.isEmpty else {
        skipped += 1
        continue
      }
      let origin = normalizedOrigin(rawURL.hasPrefix("http") ? rawURL : "https://\(rawURL)")
      guard origin.hasPrefix("http") else { skipped += 1; continue }
      let key = "\(origin)\u{0}\(username.lowercased())"
      guard !seen.contains(key), !credentials.contains(where: { "\($0.origin)\u{0}\($0.username.lowercased())" == key }) else {
        duplicates += 1
        continue
      }
      seen.insert(key)
      let title = titleIndex.flatMap { row[safe: $0] }.flatMap { $0.isEmpty ? nil : $0 } ?? URL(string: origin)?.host ?? origin
      pending.append(PendingImportCredential(label: title, username: username, password: password, origin: origin))
    }

    pendingImports[pendingID] = pending
    return SecretCSVImportPreview(
      id: pendingID,
      fileName: url.lastPathComponent,
      totalRows: max(rows.count - 1, 0),
      importableCount: pending.count,
      duplicateCount: duplicates,
      skippedCount: skipped,
      sampleLabels: pending.prefix(3).map(\.label)
    )
  }

  func commitImport(_ preview: SecretCSVImportPreview) throws -> SecretCSVImportResult {
    guard let pending = pendingImports.removeValue(forKey: preview.id) else { throw SecretVaultError.invalidImport("This import preview expired. Choose the CSV again.") }
    var imported = 0
    var skipped = preview.skippedCount
    for item in pending {
      do {
        try add(label: item.label, username: item.username, password: item.password, origin: item.origin)
        imported += 1
      } catch SecretVaultError.keychain(let status) where status == errSecDuplicateItem {
        skipped += 1
      }
    }
    return SecretCSVImportResult(importedCount: imported, duplicateCount: preview.duplicateCount, skippedCount: skipped)
  }

  func discardImport(_ preview: SecretCSVImportPreview?) {
    guard let preview else { return }
    pendingImports.removeValue(forKey: preview.id)
  }

  func search(query: String, origin: String?) -> [[String: String]] {
    let needle = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let expectedOrigin = origin.map(normalizedOrigin)
    return credentials.filter { credential in
      let haystack = "\(credential.label) \(credential.origin) \(credential.username)".lowercased()
      return (needle.isEmpty || haystack.contains(needle)) && (expectedOrigin == nil || credential.origin == expectedOrigin)
    }.map {
      ["id": $0.id, "label": $0.label, "username": $0.maskedUsername, "origin": $0.origin]
    }
  }

  func authorizeBrowserCredential(
    id: String,
    origin: String,
    runId: String? = nil,
    conversationId: String? = nil
  ) async throws -> (username: String, password: String) {
    guard let credential = credentials.first(where: { $0.id == id && $0.origin == normalizedOrigin(origin) }) else { throw SecretVaultError.notFound }
    do {
      try await authenticate(reason: "Allow Detach to sign in to \(credential.origin)")
      let password = try password(for: credential)
      SecretAccessAudit.shared.record(credential: credential, origin: credential.origin, outcome: .used, runId: runId, conversationId: conversationId)
      return (credential.username, password)
    } catch {
      SecretAccessAudit.shared.record(
        credential: credential,
        origin: credential.origin,
        outcome: SecretAccessAudit.shared.outcome(for: error),
        runId: runId,
        conversationId: conversationId
      )
      throw error
    }
  }

  private func password(for credential: SecretCredential) throws -> String {
    var item: CFTypeRef?
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: credential.id,
      kSecReturnData as String: true,
    ]
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else { throw SecretVaultError.keychain(status) }
    return value
  }

  private func authenticate(reason: String) async throws {
    let context = LAContext()
    context.localizedCancelTitle = "Cancel"
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      throw error ?? SecretVaultError.invalidImport("Touch ID or your Mac password is unavailable.")
    }
    try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
  }

  private func normalizedOrigin(_ raw: String) -> String {
    guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
    return "\(scheme)://\(host)\(url.port.map { ":\($0)" } ?? "")"
  }

  private func loadMetadata() {
    if let decoded = try? encryptedStore.load([SecretCredential].self, named: encryptedMetadataName) {
      credentials = decoded
      return
    }
    // One-time migration from the previous release. The legacy value is erased
    // only after its encrypted replacement is written successfully.
    guard let data = UserDefaults.standard.data(forKey: legacyMetadataKey), let decoded = try? JSONDecoder().decode([SecretCredential].self, from: data) else { return }
    credentials = decoded
    if (try? persistMetadata()) != nil {
      UserDefaults.standard.removeObject(forKey: legacyMetadataKey)
    }
  }

  private func persistMetadata() throws {
    try encryptedStore.save(credentials, named: encryptedMetadataName)
  }
}

private struct PendingImportCredential {
  let label: String
  let username: String
  let password: String
  let origin: String
}

private enum CSVParser {
  static func parse(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var quoted = false
    var index = text.startIndex
    while index < text.endIndex {
      let character = text[index]
      if character == "\"" {
        let next = text.index(after: index)
        if quoted, next < text.endIndex, text[next] == "\"" { field.append("\""); index = next }
        else { quoted.toggle() }
      } else if character == ",", !quoted {
        row.append(field); field = ""
      } else if (character == "\n" || character == "\r"), !quoted {
        if character == "\r", text.index(after: index) < text.endIndex, text[text.index(after: index)] == "\n" { index = text.index(after: index) }
        row.append(field); rows.append(row); row = []; field = ""
      } else {
        field.append(character)
      }
      index = text.index(after: index)
    }
    if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
    return rows
  }
}

private func normalizedHeader(_ value: String) -> String {
  value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\u{feff}", with: "").lowercased()
}

private extension Array {
  subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
