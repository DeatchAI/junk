import Foundation
import Security

/// Separate from the agent secret vault, and excluded from Keychain synchronization and migration.
enum LicenseStore {
  private static var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "app.getlazzy.licensing",
      kSecAttrAccount as String: "access-state-v1",
      kSecAttrSynchronizable as String: false,
    ]
  }

  static func load() throws -> LicenseStoredState? {
    var request = query
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data,
      let value = try? JSONDecoder().decode(LicenseStoredState.self, from: data)
    else { throw LicenseError.storage }
    return value
  }

  static func save(_ state: LicenseStoredState) throws {
    let values: [String: Any] = [
      kSecValueData as String: try JSONEncoder().encode(state),
    ]
    let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
    if status == errSecItemNotFound {
      var item = query.merging(values) { _, new in new }
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess
      else { throw LicenseError.storage }
    } else if status != errSecSuccess {
      throw LicenseError.storage
    }
  }
}
