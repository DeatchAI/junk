import Foundation

struct PolarLicenseClient: Sendable {
  private struct License: Decodable {
    let id: String
    let organizationID: String
    let benefitID: String
    let status: String
    let expiresAt: Date?
    let limitActivations: Int?
    let activation: Activation?
    enum CodingKeys: String, CodingKey {
      case organizationID = "organization_id", benefitID = "benefit_id"
      case id, status, expiresAt = "expires_at", limitActivations = "limit_activations", activation
    }
  }

  private struct Activation: Decodable { let id: String }

  private struct ActivatedLicense: Decodable {
    let id: String
    let licenseKey: License
    enum CodingKeys: String, CodingKey { case id, licenseKey = "license_key" }
  }

  private var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { value in
      let container = try value.singleValueContainer()
      let text = try container.decode(String.self)
      let format = ISO8601DateFormatter()
      format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = format.date(from: text) { return date }
      format.formatOptions = [.withInternetDateTime]
      guard let date = format.date(from: text) else {
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Polar timestamp")
      }
      return date
    }
    return decoder
  }

  func unlock(key: String, previous: PaidLicense?, installationID: String) async throws -> PaidLicense {
    // Key rotation preserves the activation in Polar. Reuse that allocation with the new key.
    if let previous, previous.key != key, let activationID = previous.activationID {
      do {
        let license = try await check(key: key, activationID: activationID, installationID: installationID)
        return savedLicense(key: key, activationID: activationID, license: license)
      } catch let error as LicenseError {
        if case .rejected = error {
          throw LicenseError.rejected("This key doesn't match the saved Mac activation. Deactivate the saved key before using a different license.")
        }
        throw error
      }
    }
    // Reuse this Mac's allocation rather than consuming another activation on each launch.
    if let previous, previous.key == key, !previous.invalidated {
      return try await validate(previous, installationID: installationID)
    }
    var license = try await check(key: key, activationID: nil, installationID: installationID)
    var activationID: String?
    if (license.limitActivations ?? 0) > 0 {
      let data = try await request("activate", body: [
        "key": key, "organization_id": LicenseConfiguration.organizationID,
        "label": "Detach on Mac", "conditions": ["installation_id": installationID],
      ])
      let activated = try decoder.decode(ActivatedLicense.self, from: data)
      try checkProduct(activated.licenseKey)
      guard activated.licenseKey.id == license.id, UUID(uuidString: activated.id) != nil else {
        throw LicenseError.rejected("Polar returned an invalid Mac activation.")
      }
      activationID = activated.id
      license = activated.licenseKey
    }
    return savedLicense(key: key, activationID: activationID, license: license)
  }

  func validate(_ saved: PaidLicense, installationID: String) async throws -> PaidLicense {
    guard saved.matchesProduct else { throw LicenseError.rejected("This key isn't a Detach license.") }
    let license = try await check(key: saved.key, activationID: saved.activationID, installationID: installationID)
    if (license.limitActivations ?? 0) > 0, saved.activationID == nil {
      throw LicenseError.rejected("Activate this key on this Mac to continue.")
    }
    return savedLicense(key: saved.key, activationID: saved.activationID, license: license)
  }

  func deactivate(_ license: PaidLicense) async throws {
    guard let activationID = license.activationID else { return }
    _ = try await request("deactivate", body: [
      "key": license.key, "organization_id": LicenseConfiguration.organizationID,
      "activation_id": activationID,
    ])
  }

  private func check(key: String, activationID: String?, installationID: String) async throws -> License {
    var body: [String: Any] = [
      "key": key, "organization_id": LicenseConfiguration.organizationID,
      "benefit_id": LicenseConfiguration.benefitID,
    ]
    if let activationID {
      body["activation_id"] = activationID
      body["conditions"] = ["installation_id": installationID]
    }
    let data = try await request("validate", body: body)
    let license = try decoder.decode(License.self, from: data)
    try checkProduct(license)
    if let activationID, license.activation?.id != activationID {
      throw LicenseError.rejected("This Mac's license activation is no longer valid.")
    }
    return license
  }

  private func checkProduct(_ license: License) throws {
    guard license.status == "granted",
      license.organizationID.caseInsensitiveCompare(LicenseConfiguration.organizationID) == .orderedSame,
      license.benefitID.caseInsensitiveCompare(LicenseConfiguration.benefitID) == .orderedSame,
      license.expiresAt.map({ $0 > Date() }) ?? true
    else { throw LicenseError.rejected("This license is expired, revoked, or doesn't unlock Detach.") }
  }

  private func savedLicense(key: String, activationID: String?, license: License) -> PaidLicense {
    PaidLicense(key: key, activationID: activationID, organizationID: license.organizationID,
      benefitID: license.benefitID, validatedAt: Date(), expiresAt: license.expiresAt)
  }

  private func request(_ endpoint: String, body: [String: Any]) async throws -> Data {
    var request = URLRequest(url: LicenseConfiguration.apiURL.appendingPathComponent(endpoint))
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("2026-10", forHTTPHeaderField: "Polar-Version")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let data: Data
    let response: URLResponse
    do { (data, response) = try await URLSession.shared.data(for: request) }
    catch { throw LicenseError.unavailable }
    guard let response = response as? HTTPURLResponse, data.count < 1_000_000 else {
      throw LicenseError.unavailable
    }
    switch response.statusCode {
    case 200..<300: return data
    case 404 where endpoint == "deactivate": return Data()
    case 429, 500...599: throw LicenseError.unavailable
    case 403:
      throw LicenseError.rejected("This key can't be activated. Check its status and available Macs in the customer portal.")
    case 400, 401, 404, 422:
      throw LicenseError.rejected("This key or Mac activation is invalid. Check your Detach license in the customer portal.")
    default: throw LicenseError.unavailable
    }
  }
}
