import Foundation
import Supabase

/// Manages analytics event logging to Supabase
class AnalyticsManager {
  static let shared = AnalyticsManager()

  private init() {}

  /// Log an event to Supabase
  /// - Parameters:
  ///   - event: The name of the event (e.g., "app_launched", "error")
  ///   - properties: Optional dictionary of properties to include
  func logEvent(_ event: String, properties: [String: Any]? = nil) {
    Task {
      do {
        // AuthManager.shared.supabase is not optional in current implementation
        let client = AuthManager.shared.supabase

        // DTO initialization might throw if JSON serialization fails
        let dto = try AnalyticsEventDTO(
          user_id: AuthManager.shared.currentUser?.id,
          event_type: event,
          properties: properties
        )

        try await client.from("events").insert(dto).execute()
        print("📊 Logged event: \(event)")
      } catch {
        print("❌ Failed to log event '\(event)': \(error)")
      }
    }
  }
}

// MARK: - DTOs

struct AnalyticsEventDTO: Codable {
  let user_id: UUID?
  let event_type: String
  let properties: AnyJSON
  let created_at: Date?

  init(user_id: UUID?, event_type: String, properties: [String: Any]?) throws {
    self.user_id = user_id
    self.event_type = event_type
    self.created_at = Date()

    if let properties = properties {
      // Convert [String: Any] to AnyJSON via JSONSerialization -> Data -> Decoder
      // This ensures we handle all types supported by JSON (String, Number, Bool, Array, Object, Null)
      let data = try JSONSerialization.data(withJSONObject: properties)
      self.properties = try JSONDecoder().decode(AnyJSON.self, from: data)
    } else {
      self.properties = .object([:])
    }
  }
}
