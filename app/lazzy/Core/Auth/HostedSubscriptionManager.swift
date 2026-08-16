import AppKit
import Auth
import Combine
import Foundation

struct HostedSubscriptionPlan: Decodable, Identifiable {
  let id: String
  let displayName: String
  let monthlyPriceCents: Int
  /// The server keeps the Kie allowance as its equivalent Detach balance.
  /// This is only used to calculate the percentage shown in the UI.
  let monthlyCredits: Int
}

struct HostedSubscriptionSummary: Decodable {
  let id: String
  let planId: String
  let displayName: String
  let status: String
  let currentPeriodEnd: String
  let cancelAtPeriodEnd: Bool
}

struct HostedCreditBalance: Decodable {
  let available: String
  let reserved: String
  let amountDue: String

  var availableDecimal: Decimal? {
    Decimal(string: available, locale: Locale(identifier: "en_US_POSIX"))
  }
}

private struct HostedSubscriptionState: Decodable {
  let plans: [HostedSubscriptionPlan]
  let subscription: HostedSubscriptionSummary?
  let credits: HostedCreditBalance
}

private struct HostedSubscriptionActionResponse: Decodable {
  let checkoutURL: URL?
  let portalURL: URL?
}

@MainActor
final class HostedSubscriptionManager: ObservableObject {
  static let shared = HostedSubscriptionManager()

  @Published private(set) var plans: [HostedSubscriptionPlan] = []
  @Published private(set) var subscription: HostedSubscriptionSummary?
  @Published private(set) var credits: HostedCreditBalance?
  @Published private(set) var isLoading = false
  @Published private(set) var errorMessage: String?

  private init() {
    NotificationCenter.default.addObserver(
      forName: .detachHostedCreditsDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { await self?.refreshAfterCheckout() }
    }
  }

  var isAvailable: Bool {
    AuthManager.shared.isAuthenticated
  }

  var hasHostedCredits: Bool {
    guard let available = credits?.available else { return false }
    return Decimal(
      string: available,
      locale: Locale(identifier: "en_US_POSIX")
    ).map { $0 > 0 } ?? false
  }

  var canUseHostedAI: Bool {
    isAvailable && hasHostedCredits
  }

  var hasReservedCredits: Bool {
    decimalValue(credits?.reserved) > 0
  }

  var hasAmountDue: Bool {
    decimalValue(credits?.amountDue) > 0
  }

  var activePlan: HostedSubscriptionPlan? {
    guard let planId = subscription?.planId else { return nil }
    return plans.first { $0.id == planId }
  }

  var availableCreditProgress: Double? {
    guard let available = credits?.availableDecimal,
      let monthlyCredits = activePlan?.monthlyCredits,
      monthlyCredits > 0
    else { return nil }

    let ratio = NSDecimalNumber(decimal: available).doubleValue / Double(monthlyCredits)
    return min(max(ratio, 0), 1)
  }

  var availableCreditPercentage: Int? {
    guard let progress = availableCreditProgress else { return nil }
    return Int((progress * 100).rounded())
  }

  private func decimalValue(_ value: String?) -> Decimal {
    guard let value else { return 0 }
    return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) ?? 0
  }

  func refresh() async {
    guard isAvailable else {
      plans = []
      subscription = nil
      credits = nil
      errorMessage = nil
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      let state: HostedSubscriptionState = try await request(method: "GET")
      plans = state.plans
      subscription = state.subscription
      credits = state.credits
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// Polar confirms the payment and writes credits asynchronously. Keep the
  /// app honest, but give that signed webhook a short window to arrive before
  /// leaving the customer on an apparently stale plan.
  func refreshAfterCheckout() async {
    for attempt in 0..<5 {
      await refresh()
      if hasHostedCredits { return }
      guard attempt < 4 else { return }
      try? await Task.sleep(for: .seconds(2))
    }
  }

  func startCheckout(planId: String) async {
    await performAction(["action": "checkout", "plan": planId]) { response in
      guard let url = response.checkoutURL else {
        throw HostedSubscriptionError.invalidResponse
      }
      NSWorkspace.shared.open(url)
    }
  }

  func openCustomerPortal() async {
    await performAction(["action": "portal"]) { response in
      guard let url = response.portalURL else {
        throw HostedSubscriptionError.invalidResponse
      }
      NSWorkspace.shared.open(url)
    }
  }

  private func performAction(
    _ body: [String: String],
    completion: (HostedSubscriptionActionResponse) throws -> Void
  ) async {
    guard isAvailable else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let response: HostedSubscriptionActionResponse = try await request(method: "POST", body: body)
      try completion(response)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func request<Response: Decodable>(
    method: String,
    body: [String: String]? = nil
  ) async throws -> Response {
    guard let accessToken = AuthManager.shared.session?.accessToken else {
      throw HostedSubscriptionError.signInRequired
    }
    let origin = AppConfiguration.hostedControlPlaneURL
    let url = origin.appending(path: "api/v1/subscriptions")
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(body)
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw HostedSubscriptionError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      let error = try? JSONDecoder().decode(HostedSubscriptionAPIError.self, from: data)
      throw HostedSubscriptionError.service(error?.error.message ?? "Unable to reach Detach Cloud subscriptions.")
    }
    return try JSONDecoder().decode(Response.self, from: data)
  }
}

private struct HostedSubscriptionAPIError: Decodable {
  struct Details: Decodable { let message: String }
  let error: Details
}

private enum HostedSubscriptionError: LocalizedError {
  case signInRequired
  case invalidResponse
  case service(String)

  var errorDescription: String? {
    switch self {
    case .signInRequired: return "Sign in to manage your Detach Cloud plan."
    case .invalidResponse: return "The Detach Cloud subscription service returned an invalid response."
    case .service(let message): return message
    }
  }
}

extension Notification.Name {
  static let detachHostedCreditsDidChange = Notification.Name("detach.hostedCreditsDidChange")
}
