import Foundation

/// These are public Polar identifiers. A merchant access token must never ship in the app.
enum LicenseConfiguration {
  static let organizationID = "42934185-1dd1-4b1b-be9c-aeeaa7cdca24"
  static let benefitID = "e80bbbc2-4dd5-496d-b1e5-75b972c433ac"
  static let checkoutURL = URL(string: "https://buy.polar.sh/polar_cl_U8ixd3G5N103IqzPexKeKnQ9FLAK7qobC1VRL0l8kxC")!
  static let portalURL = URL(string: "https://polar.sh/slappy/portal")!
  static let apiURL = URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/")!
  static let trialDuration: TimeInterval = 3 * 24 * 60 * 60
  static let offlineGrace: TimeInterval = 3 * 24 * 60 * 60
  static let revalidationInterval: TimeInterval = 6 * 60 * 60
}

struct PaidLicense: Codable, Sendable {
  let key: String
  let activationID: String?
  let organizationID: String
  let benefitID: String
  var validatedAt: Date
  let expiresAt: Date?
  var invalidated = false

  var matchesProduct: Bool {
    organizationID.caseInsensitiveCompare(LicenseConfiguration.organizationID) == .orderedSame
      && benefitID.caseInsensitiveCompare(LicenseConfiguration.benefitID) == .orderedSame
  }
}

struct LicenseStoredState: Codable, Sendable {
  var installationID = UUID().uuidString
  var trialStartedAt: Date?
  var lastObservedAt = Date()
  var license: PaidLicense?
}

enum LicenseError: LocalizedError, Sendable {
  case rejected(String)
  case unavailable
  case storage

  var errorDescription: String? {
    switch self {
    case .rejected(let message): return message
    case .unavailable: return "Polar couldn't be reached. Check your connection and try again."
    case .storage: return "Detach couldn't access its license in Keychain. Try again after unlocking your Mac."
    }
  }
}
