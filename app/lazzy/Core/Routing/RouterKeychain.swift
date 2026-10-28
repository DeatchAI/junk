import Foundation
import Security

/// App-owned routing credentials are never advertised through the agent secret vault.
enum RouterKeychain {
  private static let service = "app.getlazzy.auto-router"
  private static let account = "jev-api-key"
  private static var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
  }

  static func read() throws -> String? {
    var request = query
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8)
    else { throw RouterError.unavailable("Could not read the Jev key from Keychain.") }
    return key
  }

  static func save(_ key: String) throws {
    let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty, key.count <= 4096, !key.contains(where: { $0.isWhitespace })
    else { throw RouterError.unavailable("Enter a valid Jev API key.") }
    let values: [String: Any] = [kSecValueData as String: Data(key.utf8)]
    let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
    if status == errSecItemNotFound {
      var item = query.merging(values) { _, new in new }
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess
      else { throw RouterError.unavailable("Could not save the Jev key in Keychain.") }
    } else if status != errSecSuccess {
      throw RouterError.unavailable("Could not update the Jev key in Keychain.")
    }
  }

  static func remove() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound
    else { throw RouterError.unavailable("Could not remove the Jev key from Keychain.") }
  }
}
