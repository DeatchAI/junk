import Foundation
import Security

enum CursorProviderKeychain {
  private static let service = "app.getlazzy.cursor-provider"
  private static let account = "cursor-api-key"
  private static var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service,
     kSecAttrAccount as String: account]
  }

  static func read() throws -> String? {
    var request = query
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data,
      let key = String(data: data, encoding: .utf8) else {
      throw CursorProviderKeychainError.unavailable("Could not read the Cursor API key from Keychain.")
    }
    return key
  }

  static func save(_ value: String) throws {
    let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty, key.count <= 4096, !key.contains(where: \.isWhitespace) else {
      throw CursorProviderKeychainError.invalidKey
    }
    let values: [String: Any] = [kSecValueData as String: Data(key.utf8)]
    let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
    if status == errSecItemNotFound {
      var item = query.merging(values) { _, new in new }
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
        throw CursorProviderKeychainError.unavailable("Could not save the Cursor API key in Keychain.")
      }
    } else if status != errSecSuccess {
      throw CursorProviderKeychainError.unavailable("Could not update the Cursor API key in Keychain.")
    }
  }

  static func remove() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw CursorProviderKeychainError.unavailable("Could not remove the Cursor API key from Keychain.")
    }
  }
}

enum CursorProviderKeychainError: LocalizedError {
  case invalidKey
  case unavailable(String)

  var errorDescription: String? {
    switch self {
    case .invalidKey: "Enter a valid Cursor API key."
    case .unavailable(let message): message
    }
  }
}
