import Foundation
import Security

enum RemoteMachineTokenVault {
  private static let service = "app.getlazzy.remote-runtime"

  static func token(machineID: UUID) throws -> String {
    let query = baseQuery(machineID: machineID)
    var request = query
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &item)
    if status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) {
      return value
    }
    guard status == errSecItemNotFound else { throw RemoteMachineError.ssh("Detach could not access the saved remote-machine key.") }

    let value = UUID().uuidString.replacingOccurrences(of: "-", with: "")
      + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    var add = query
    add[kSecValueData as String] = Data(value.utf8)
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
      throw RemoteMachineError.ssh("Detach could not save a secure key for this machine.")
    }
    return value
  }

  static func remove(machineID: UUID) throws {
    let status = SecItemDelete(baseQuery(machineID: machineID) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw RemoteMachineError.ssh("Detach could not remove the saved key for this machine.")
    }
  }

  private static func baseQuery(machineID: UUID) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: machineID.uuidString,
    ]
  }
}
