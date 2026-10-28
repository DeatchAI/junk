import Foundation
import Security

enum KeepAwakeServiceIdentity {
  static let machService = "app.getlazzy.keep-awake"
  static let plistName = "app.getlazzy.keep-awake.plist"
  static var appRequirement: String? { requirement(for: "app.getlazzy") }
  static var helperRequirement: String? { requirement(for: "app.getlazzy.keep-awake-helper") }

  private static func requirement(for identifier: String) -> String? {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
    var info: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
      let values = info as? [String: Any], let team = values[kSecCodeInfoTeamIdentifier as String] as? String,
      team.count == 10, team.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) else { return nil }
    return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
  }
}

@objc protocol KeepAwakeHelperProtocol {
  func acquire(reply: @escaping (String?) -> Void)
  func heartbeat(reply: @escaping (String?) -> Void)
  func release(reply: @escaping (String?) -> Void)
}

@objc protocol KeepAwakeClientProtocol {
  func keepAwakeStopped(reason: String)
}
