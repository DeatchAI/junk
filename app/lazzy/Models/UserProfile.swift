import Foundation

/// Subscription plan types matching Supabase enum
enum SubscriptionPlanType: String, Codable, CaseIterable {
  case free = "free"
  case pro = "pro"
  case proBYOK = "pro_byok"
  case lifetimeNoUpdates = "lifetime_no_updates"
  case lifetimeWithUpdates = "lifetime_with_updates"
  case business = "business"

  var displayName: String {
    switch self {
    case .free: return "Free"
    case .pro: return "Pro"
    case .proBYOK: return "Pro (BYOK)"
    case .lifetimeNoUpdates: return "Lifetime"
    case .lifetimeWithUpdates: return "Lifetime+"
    case .business: return "Business"
    }
  }

  var isPaid: Bool {
    self != .free
  }

  /// Whether BYOK feature is available for this plan
  var hasBYOKAccess: Bool {
    switch self {
    case .free: return false
    default: return true
    }
  }

  /// Whether BYOK is required (cannot use hosted keys)
  var requiresBYOK: Bool {
    switch self {
    case .proBYOK, .lifetimeNoUpdates, .lifetimeWithUpdates: return true
    default: return false
    }
  }

  /// Whether user has access to all AI models
  var hasAllModels: Bool {
    switch self {
    case .free, .proBYOK, .lifetimeNoUpdates, .lifetimeWithUpdates: return false
    default: return true
    }
  }
}

/// User profile from Supabase profiles table
struct UserProfile: Codable, Identifiable {
  let id: UUID
  var email: String?
  var planType: SubscriptionPlanType
  var creditUsage: Int?
  var lastUsageReset: Date?

  enum CodingKeys: String, CodingKey {
    case id
    case email
    case planType = "plan_type"
    case creditUsage = "usage_count"
    case lastUsageReset = "last_usage_reset"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    email = try container.decodeIfPresent(String.self, forKey: .email)

    // Handle plan_type as string
    let planTypeString = try container.decodeIfPresent(String.self, forKey: .planType) ?? "free"
    planType = SubscriptionPlanType(rawValue: planTypeString) ?? .free

    creditUsage = try container.decodeIfPresent(Int.self, forKey: .creditUsage)
    lastUsageReset = try container.decodeIfPresent(Date.self, forKey: .lastUsageReset)
  }
}
