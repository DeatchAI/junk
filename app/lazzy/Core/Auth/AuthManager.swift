import AppKit
import Auth
import Combine
import Foundation
import Supabase

@MainActor
class AuthManager: ObservableObject {
  static let shared = AuthManager()

  let supabase = SupabaseClient(
    supabaseURL: URL(string: AppConfiguration.supabaseURL)!,
    supabaseKey: AppConfiguration.supabasePublishableKey,
    options: SupabaseClientOptions(
      auth: .init(
        emitLocalSessionAsInitialSession: true
      )
    )
  )

  @Published var session: Session?
  @Published var userProfile: UserProfile?
  @Published var usage: UserUsage?
  @Published var isLoading = false
  @Published var lastError: String?
  @Published var isReady = false  // True once initial session check is complete
  private var lastUsageFetch: Date?
  private var isOAuthInProgress = false
  private var oauthCallbackContinuation: CheckedContinuation<URL, Error>?

  private enum OAuthError: LocalizedError {
    case browserUnavailable

    var errorDescription: String? {
      switch self {
      case .browserUnavailable:
        return "Unable to open your default browser."
      }
    }
  }

  var currentUser: User? {
    session?.user
  }

  var isAuthenticated: Bool {
    session != nil
  }

  var planType: SubscriptionPlanType {
    userProfile?.planType ?? .free
  }

  var isPro: Bool {
    planType.isPaid
  }

  init() {
    Task {
      await checkSession()
      observeSession()
    }
  }

  func checkSession() async {
    self.session = try? await supabase.auth.session
    // Fetch user profile after getting session
    if session != nil {
      await fetchUserProfile()
    }
    await MainActor.run {
      self.isReady = true
      print("✅ AuthManager ready (session: \(session != nil ? "active" : "none"))")
    }
  }

  /// Fetches the user's profile from Supabase including their plan_type
  func fetchUserProfile() async {
    guard let userId = session?.user.id else { return }

    do {
      let profile: UserProfile =
        try await supabase
        .from("profiles")
        .select()
        .eq("id", value: userId.uuidString)
        .single()
        .execute()
        .value

      await MainActor.run {
        self.userProfile = profile
        print("📋 User profile loaded: \(profile.planType.displayName) plan")

        // Sync profile to local server via HTTP
        Task {
          await self.syncProfileToServer()
          self.usage = nil
        }
      }
    } catch {
      print("❌ Failed to fetch user profile: \(error)")
    }
  }

  /// Force refresh the user profile (call after potential plan change)
  func refreshProfile() async {
    await fetchUserProfile()
  }

  func observeSession() {
    Task {
      for await (event, session) in supabase.auth.authStateChanges {
        print("🔐 Auth state changed: \(event)")
        self.session = session

        // Fetch profile when user signs in
        if session != nil {
          await fetchUserProfile()
        } else {
          self.userProfile = nil
        }
      }
    }
  }

  func signInWithOAuth(provider: Auth.Provider) async {
    isLoading = true
    lastError = nil
    isOAuthInProgress = true
    defer {
      isOAuthInProgress = false
      isLoading = false
    }

    do {
      let session = try await supabase.auth.signInWithOAuth(
        provider: provider,
        redirectTo: URL(string: "lazzy://login-callback")
      ) { [weak self] url in
        guard let self else { throw OAuthError.browserUnavailable }
        return try await self.openOAuthURLInBrowser(url)
      }

      self.session = session
      print("✅ Authenticated via OAuth")
    } catch {
      lastError = error.localizedDescription
      print("❌ OAuth error: \(error)")
      AnalyticsManager.shared.logEvent(
        "auth_error", properties: ["method": "oauth", "error": error.localizedDescription])
    }
  }

  func signInWithMagicLink(email: String) async {
    isLoading = true
    lastError = nil
    do {
      try await supabase.auth.signInWithOTP(
        email: email,
        redirectTo: URL(string: "lazzy://login-callback")
      )
    } catch {
      lastError = error.localizedDescription
      print("❌ Magic Link error: \(error)")
      AnalyticsManager.shared.logEvent(
        "auth_error", properties: ["method": "magic_link", "error": error.localizedDescription])
    }
    isLoading = false
  }

  /// Opens OAuth in the user's normal browser profile, then lets the app
  /// return the custom-scheme callback to Supabase for the PKCE exchange.
  private func openOAuthURLInBrowser(_ url: URL) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      oauthCallbackContinuation = continuation

      guard NSWorkspace.shared.open(url) else {
        oauthCallbackContinuation = nil
        continuation.resume(throwing: OAuthError.browserUnavailable)
        return
      }
    }
  }

  /// Completes the external-browser OAuth flow. Returning true also tells the
  /// app delegate not to process the one-time callback a second time.
  @discardableResult
  func handleOAuthCallback(_ url: URL) -> Bool {
    guard isOAuthInProgress else { return false }

    if let continuation = oauthCallbackContinuation {
      oauthCallbackContinuation = nil
      continuation.resume(returning: url)
    }
    return true
  }

  func handleDeeplink(_ url: URL) {
    print("🎯 AuthManager handling authentication callback")
    Task {
      do {
        // This exchanges the code for a session
        try await supabase.auth.session(from: url)
        print("✅ Authenticated via deep link")

        // Explicitly update session state on main thread
        let session = try? await supabase.auth.session
        await MainActor.run {
          self.session = session
          self.lastError = nil
          print("👤 Authentication session updated")
        }
      } catch {
        print("❌ Deep link auth error: \(error)")
        await MainActor.run {
          self.lastError = error.localizedDescription
          self.isLoading = false
          AnalyticsManager.shared.logEvent(
            "auth_error", properties: ["method": "deeplink", "error": error.localizedDescription])
        }
      }
    }
  }

  func signOut() async {
    isLoading = true
    // Remove both hosted-model and Composio control-plane credentials from the
    // bundled runtime before another account can use this app instance.
    await syncProfileToServer(clear: true)
    do {
      try await supabase.auth.signOut()
      self.session = nil
    } catch {
      lastError = error.localizedDescription
      print("❌ Sign out error: \(error)")
      AnalyticsManager.shared.logEvent(
        "auth_error", properties: ["method": "sign_out", "error": error.localizedDescription])
    }
    isLoading = false
  }

  /// Sends the signed-in session to the local Bun runtime over loopback. The
  /// runtime uses it to obtain scoped hosted-model and Composio sessions; it
  /// never forwards the Supabase token to an agent process.
  func syncProfileToServer(clear: Bool = false) async {
    let accessToken = session?.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clear || (accessToken != nil && !accessToken!.isEmpty) else { return }

    // Wait for server to be ready before making HTTP requests
    await waitForServerReady()

    let url = URL(string: "http://127.0.0.1:\(ServerConfig.port)/api/sync-profile")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    ServerConfig.authorize(&request)

    var body: [String: Any] = [:]
    if let accessToken, !accessToken.isEmpty {
      // This token is sent only over localhost to the child runtime. The
      // runtime exchanges it for scoped hosted-model and Composio sessions.
      body["accessToken"] = accessToken
    } else {
      body["accessToken"] = NSNull()
    }

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (_, response) = try await URLSession.shared.data(for: request)

      if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
        print("✅ User profile synced to local server via HTTP")
        await MainActor.run {
          NotificationCenter.default.post(name: .detachHostedProfileDidSync, object: nil)
        }
      } else {
        print("⚠️ Failed to sync profile to local server")
      }
    } catch {
      print("❌ Error syncing profile to local server: \(error)")
    }
  }

  /// Waits for the local server to be ready before making HTTP requests
  private func waitForServerReady() async {
    // If already ready, return immediately
    if ServerConfig.isServerReady {
      return
    }

    // In dev mode, assume server is running externally
    if ServerConfig.mode == .dev {
      return
    }

    // Wait for the notification with a timeout
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      var observer: NSObjectProtocol?

      // Set up a timeout
      let timeoutTask = DispatchWorkItem {
        if let obs = observer {
          NotificationCenter.default.removeObserver(obs)
        }
        print("⚠️ Server readiness timeout - proceeding anyway")
        continuation.resume()
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeoutTask)

      // Check again in case it became ready while setting up
      if ServerConfig.isServerReady {
        timeoutTask.cancel()
        continuation.resume()
        return
      }

      // Listen for the notification
      observer = NotificationCenter.default.addObserver(
        forName: .serverDidBecomeReady,
        object: nil,
        queue: .main
      ) { _ in
        timeoutTask.cancel()
        if let obs = observer {
          NotificationCenter.default.removeObserver(obs)
        }
        continuation.resume()
      }
    }
  }

  /// Fetches usage statistics from the local server
  func fetchUserUsage() async {
    guard let profile = userProfile else { return }

    // Throttle: don't fetch more than once every 30 seconds unless forced
    if let lastFetch = lastUsageFetch, Date().timeIntervalSince(lastFetch) < 30 {
      return
    }

    // Wait for server to be ready before making HTTP requests
    await waitForServerReady()

    let url = URL(
      string: "http://127.0.0.1:\(ServerConfig.port)/api/usage?userId=\(profile.id.uuidString)")!
    var request = URLRequest(url: url)
    ServerConfig.authorize(&request)

    do {
      let (data, response) = try await URLSession.shared.data(for: request)

      if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
        let usage = try JSONDecoder().decode(UserUsage.self, from: data)
        await MainActor.run {
          self.usage = usage
          self.lastUsageFetch = Date()
          print("📊 Usage statistics loaded: \(usage.creditsUsed)/\(usage.creditLimit) credits")
        }
      } else {
        print("⚠️ Failed to fetch usage from local server")
      }
    } catch {
      print("❌ Error fetching usage from local server: \(error)")
    }
  }
}

extension Notification.Name {
  static let detachHostedProfileDidSync = Notification.Name("detach.hostedProfileDidSync")
}
