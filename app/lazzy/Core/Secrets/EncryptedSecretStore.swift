import CryptoKit
import Foundation
import Security

/// Encrypts non-secret vault records before they reach the filesystem.
///
/// Credential values remain in the macOS Keychain. This store protects the
/// accompanying metadata and audit trail using AES-256-GCM. Its encryption key
/// is generated per Mac and stored only in that Mac's Keychain.
@MainActor
final class EncryptedSecretStore {
  static let shared = EncryptedSecretStore()

  private let keyService = "com.lazzy.secrets.encryption-key"
  private let keyAccount = "v1"
  private let directoryName = "Detach/Secrets"

  private init() {}

  func load<Value: Decodable>(_ type: Value.Type, named name: String) throws -> Value? {
    let url = try fileURL(named: name)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let sealed = try Data(contentsOf: url)
    let box = try AES.GCM.SealedBox(combined: sealed)
    let plaintext = try AES.GCM.open(box, using: encryptionKey())
    return try JSONDecoder().decode(Value.self, from: plaintext)
  }

  func save<Value: Encodable>(_ value: Value, named name: String) throws {
    let plaintext = try JSONEncoder().encode(value)
    let sealed = try AES.GCM.seal(plaintext, using: encryptionKey()).combined
    guard let sealed else { throw EncryptedSecretStoreError.encryptionFailed }
    try sealed.write(to: fileURL(named: name), options: [.atomic])
  }

  private func fileURL(named name: String) throws -> URL {
    let root = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = root.appendingPathComponent(directoryName, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    return directory.appendingPathComponent("\(name).sealed", isDirectory: false)
  }

  private func encryptionKey() throws -> SymmetricKey {
    var existing: CFTypeRef?
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keyService,
      kSecAttrAccount as String: keyAccount,
      kSecReturnData as String: true,
    ]
    let lookupStatus = SecItemCopyMatching(query as CFDictionary, &existing)
    if lookupStatus == errSecSuccess, let data = existing as? Data, data.count == 32 {
      return SymmetricKey(data: data)
    }
    guard lookupStatus == errSecItemNotFound else {
      throw EncryptedSecretStoreError.keychain(lookupStatus)
    }

    var keyMaterial = Data(count: 32)
    let randomStatus = keyMaterial.withUnsafeMutableBytes { buffer in
      SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
    }
    guard randomStatus == errSecSuccess else { throw EncryptedSecretStoreError.keychain(randomStatus) }

    let addQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keyService,
      kSecAttrAccount as String: keyAccount,
      kSecValueData as String: keyMaterial,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    if addStatus == errSecDuplicateItem { return try encryptionKey() }
    guard addStatus == errSecSuccess else { throw EncryptedSecretStoreError.keychain(addStatus) }
    return SymmetricKey(data: keyMaterial)
  }
}

enum EncryptedSecretStoreError: LocalizedError {
  case encryptionFailed
  case keychain(OSStatus)

  var errorDescription: String? {
    switch self {
    case .encryptionFailed: return "Could not encrypt secret data."
    case .keychain(let status): return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain operation failed (\(status))."
    }
  }
}
