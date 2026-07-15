import Foundation

enum Mode {
  case dev
  case prod
}

/// Configuration for the local Detach runtime connection
enum ServerConfig {
  static let mode = Mode.prod

  /// Fallback port in case dynamic selection fails
  private static let defaultPort = 3847

  /// Updated when the server successfully binds to a port
  private static var overridePort: Int?

  /// Tracks whether the local server is ready to accept HTTP/WS connections
  private(set) static var isServerReady = false

  /// Current port the client should connect to
  static var port: Int {
    overridePort ?? defaultPort
  }

  /// WebSocket URL
  static var wsURL: URL {
    URL(string: "ws://localhost:\(port)")!
  }

  /// Path to the local runtime binary.
  ///
  /// Detach prefers the new v2 runtime. The legacy Lazzy server remains as a
  /// fallback while the migration is in progress.
  static var serverBinaryPath: String? {
    if let bundledDetach = Bundle.main.path(forResource: "detach-runtime", ofType: nil) {
      return bundledDetach
    }

    if let developmentDetach = developmentRuntimePath() {
      return developmentDetach
    }

    return Bundle.main.path(forResource: "lazzy-server", ofType: nil)
  }

  static func launchArguments(for serverPath: String) -> [String] {
    let binaryName = URL(fileURLWithPath: serverPath).lastPathComponent
    guard binaryName == "lazzy-server" else {
      return []
    }

    return [
      "--google-key=\(APISecrets.googleAPIKey)",
      "--openai-key=\(APISecrets.openAIKey)",
      "--composio-key=\(APISecrets.composioKey)",
      "--aigateway-key=\(APISecrets.aigatewayKey)",
      "--supabase-url=\(APISecrets.supabaseURL)",
      "--supabase-key=\(APISecrets.supabaseKey)",
    ]
  }

  private static func developmentRuntimePath() -> String? {
    #if DEBUG
      let constantsFile = URL(fileURLWithPath: #filePath)
      let projectRoot = constantsFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
      let candidate = projectRoot
        .appendingPathComponent("server-v2")
        .appendingPathComponent("detach-runtime")
        .path

      return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
    #else
      return nil
    #endif
  }

  /// Record the port chosen at runtime to avoid conflicts
  static func updatePort(_ port: Int) {
    overridePort = port
  }

  /// Mark the server as ready to accept connections
  static func markServerReady() {
    isServerReady = true
    // Post notification for any listeners waiting on server readiness
    NotificationCenter.default.post(name: .serverDidBecomeReady, object: nil)
  }

  /// Reset server ready state (for restart scenarios)
  static func markServerNotReady() {
    isServerReady = false
  }
}

extension Notification.Name {
  static let serverDidBecomeReady = Notification.Name("serverDidBecomeReady")
}

/// Model configuration (matches server)
enum AIConfig {
  static let defaultModel = "gemini-2.5-flash"
  static let temperature = 0.7
  static let topP = 0.95
  static let topK = 40
  static let maxOutputTokens = 8192
}
