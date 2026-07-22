import Foundation

struct UserUsage: Codable {
  let creditsUsed: Double
  let creditLimit: Int
  let planType: String
  let nextResetDate: String  // ISO8601 string

  var usageProgress: Double {
    guard creditLimit > 0 else { return 0 }
    return min(creditsUsed / Double(creditLimit), 1.0)
  }

  var remainingCredits: Double {
    max(Double(creditLimit) - creditsUsed, 0)
  }

  var formattedResetDate: String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: nextResetDate) {
      let displayFormatter = DateFormatter()
      displayFormatter.dateStyle = .medium
      displayFormatter.timeStyle = .none
      return displayFormatter.string(from: date)
    }
    return nextResetDate
  }
}
