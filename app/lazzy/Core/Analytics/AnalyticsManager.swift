import Foundation
import os

/// Lazzy's small product-analytics facade backed by the in-house Desperate SDK.
///
/// This deliberately emits only product signals and coarse app metadata. Prompts,
/// file paths, tool arguments, and account details never leave the app through
/// this service.
final class AnalyticsManager {
  static let shared = AnalyticsManager()

  private let client = AnalyticsLite.shared
  private let logger = Logger(subsystem: "app.getlazzy", category: "analytics")
  private let userDefaults: UserDefaults
  private let sessionID: String
  private var isConfigured = false

  private enum Key {
    static let anonymousID = "desperate_analytics_anonymous_id"
  }

  private init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
    self.sessionID = UUID().uuidString
  }

  /// Configures analytics once during app startup.
  func configure() {
    guard !isConfigured else { return }

    guard let analyticsWriteKey = AppConfiguration.analyticsWriteKey, !analyticsWriteKey.isEmpty else {
      logger.notice("Analytics is disabled for this build.")
      return
    }

    client.configure(apiKey: analyticsWriteKey, maxBatchSize: 25)
    isConfigured = true
    logger.notice("Desperate analytics configured for the current app bundle.")
  }

  /// Sends a product event immediately. Lazzy produces low-volume, meaningful
  /// signals, so immediate delivery avoids losing a single launch or error
  /// event when a menu-bar-only app is closed before its buffer fills.
  func logEvent(_ event: String, properties: [String: Any]? = nil) {
    guard isConfigured else { return }

    let analyticsEvent = AnalyticsEvent(
      type: event,
      userAnonID: anonymousID,
      sessionID: sessionID,
      metadata: makeMetadata(properties)
    )

    Task {
      do {
        _ = try await client.send(analyticsEvent)
      } catch {
        logger.error("Failed to send analytics event \(event, privacy: .public): \(error.localizedDescription, privacy: .private)")
      }
    }
  }

  func trackAppLaunch() {
    let bundle = Bundle.main
    let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    let previousVersion = userDefaults.string(forKey: "last_version")

    var properties: [String: Any] = [
      "app_version": version,
      "build": build,
      "platform": "macos",
    ]
    if let previousVersion, previousVersion != version {
      properties["previous_version"] = previousVersion
    }

    logEvent("app_launched", properties: properties)
    userDefaults.set(version, forKey: "last_version")
  }

  private var anonymousID: String {
    if let id = userDefaults.string(forKey: Key.anonymousID), !id.isEmpty {
      return id
    }

    let id = UUID().uuidString
    userDefaults.set(id, forKey: Key.anonymousID)
    return id
  }

  private func makeMetadata(_ properties: [String: Any]?) -> AnalyticsMetadata {
    guard let properties else { return [:] }

    return properties.reduce(into: [:]) { metadata, entry in
      guard let value = analyticsValue(from: entry.value) else { return }
      metadata[entry.key] = value
    }
  }

  private func analyticsValue(from value: Any) -> AnalyticsValue? {
    switch value {
    case let value as String:
      return .string(value)
    case let value as Bool:
      return .bool(value)
    case let value as Int:
      return .int(value)
    case let value as Double:
      return .double(value)
    case let value as Float:
      return .double(Double(value))
    case let value as NSNumber:
      return .double(value.doubleValue)
    case _ as NSNull:
      return .null
    default:
      logger.debug("Dropped unsupported analytics property type.")
      return nil
    }
  }
}
