import Foundation

/// Selects the trust boundary for this build. Open-source builds default to
/// self-hosted; the commercial release injects `hosted` and its web origin at
/// build time through Info.plist substitutions.
enum DetachDistributionMode: String {
  case selfHosted = "self_hosted"
  case hosted
}

enum DistributionConfiguration {
  static let mode: DetachDistributionMode = {
    let rawValue = Bundle.main.object(forInfoDictionaryKey: "DETACH_DISTRIBUTION_MODE") as? String
    let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return DetachDistributionMode(rawValue: value ?? "") ?? .selfHosted
  }()

  static let hostedControlPlaneURL: URL? = {
    guard mode == .hosted,
      let value = Bundle.main.object(forInfoDictionaryKey: "DETACH_HOSTED_CONTROL_PLANE_URL") as? String,
      let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
      url.scheme == "https",
      url.host != nil
    else {
      return nil
    }
    return url
  }()
}
