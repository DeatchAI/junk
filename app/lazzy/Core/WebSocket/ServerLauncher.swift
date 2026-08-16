import Combine
import Darwin
import Foundation

/// Manages launching and stopping the local Detach runtime binary.
class ServerLauncher: ObservableObject {

  @Published private(set) var isRunning = false
  @Published private(set) var lastError: String?

  private var serverProcess: Process?
  private var startTask: Task<Void, Never>?
  private let readinessTimeout: TimeInterval = 10

  // MARK: - Lifecycle

  deinit {
    stop()
  }

  // MARK: - Server Control

  var onServerReady: (() -> Void)?

  /// Start the server binary
  func start() {
    guard !isRunning else { return }

    guard let serverPath = ServerConfig.serverBinaryPath else {
      print("⚠️ Detach runtime binary not found.")
      print("   Build it with: cd server-v2 && bun run build")
      onServerReady?()
      return
    }

    startTask?.cancel()
    startTask = Task.detached { [weak self] in
      guard let self else { return }
      do {
        let port = try self.availableLoopbackPort()
        try await self.launch(serverPath: serverPath, port: port)
      } catch is CancellationError {
        // Expected on stop during startup
      } catch {
        await MainActor.run {
          self.lastError = error.localizedDescription
          self.isRunning = false
          self.serverProcess = nil
        }
        print("❌ Failed to start server: \(error.localizedDescription)")
      }
    }
  }

  /// Stop the server
  func stop() {
    startTask?.cancel()
    startTask = nil

    guard let process = serverProcess else {
      isRunning = false
      ServerConfig.markServerNotReady()
      return
    }

    terminateProcess(process)
    serverProcess = nil
    isRunning = false
    ServerConfig.markServerNotReady()

    print("🛑 Server stopped")
  }

  /// Restart the server
  func restart() {
    stop()
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: 250_000_000)
      self?.start()
    }
  }
}

// MARK: - Private helpers

extension ServerLauncher {

  fileprivate enum ServerLaunchError: LocalizedError {
    case notReady

    var errorDescription: String? {
      switch self {
      case .notReady:
        return "Server did not become ready in time"
      }
    }
  }

  fileprivate func launch(serverPath: String, port: UInt16) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: serverPath)
    process.currentDirectoryPath = URL(fileURLWithPath: serverPath).deletingLastPathComponent().path

    process.arguments = ServerConfig.launchArguments(for: serverPath)

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    // Capture output for debugging
    outputPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if let string = String(data: data, encoding: .utf8), !string.isEmpty {
        #if DEBUG
        print("🟢 SERVER OUT: \(string.trimmingCharacters(in: .whitespacesAndNewlines))")
        #endif
      }
    }

    errorPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if let string = String(data: data, encoding: .utf8), !string.isEmpty {
        #if DEBUG
        print("🔴 SERVER ERR: \(string.trimmingCharacters(in: .whitespacesAndNewlines))")
        #endif
      }
    }

    var environment = ProcessInfo.processInfo.environment
    environment["PORT"] = "\(port)"
    environment["DETACH_RUNTIME_TOKEN"] = ServerConfig.runtimeToken
    environment["DETACH_HOSTED_CONTROL_PLANE_URL"] = AppConfiguration.hostedControlPlaneURL.absoluteString
    if let openCodeURL = Bundle.main.url(forResource: "opencode", withExtension: nil) {
      environment["DETACH_OPENCODE_PATH"] = openCodeURL.path
    } else {
      environment.removeValue(forKey: "DETACH_OPENCODE_PATH")
    }
    process.environment = environment

    process.terminationHandler = { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.isRunning = false
        self.serverProcess = nil
      }
    }

    // Publish the chosen port so the client connects to the right endpoint
    await MainActor.run {
      ServerConfig.updatePort(Int(port))
    }

    do {
      try BrowserExtensionInstaller.prepare(
        port: port,
        runtimeToken: ServerConfig.runtimeToken
      )
      try process.run()

      await MainActor.run {
        self.serverProcess = process
      }

      try Task.checkCancellation()

      // Wait for readiness without blocking UI
      try await waitForServerReady(port: Int(port))

      await MainActor.run {
        serverProcess = process
        isRunning = true
        lastError = nil
        ServerConfig.markServerReady()
        self.onServerReady?()
      }

      print("🚀 Detach runtime started on port \(port) from: \(serverPath)")
    } catch {
      process.terminate()
      throw error
    }
  }

  fileprivate func waitForServerReady(port: Int) async throws {
    let deadline = Date().addingTimeInterval(readinessTimeout)
    while Date() < deadline {
      try Task.checkCancellation()
      if await isAcceptingConnections(port: port) {
        return
      }
      try await Task.sleep(nanoseconds: 150_000_000)
    }
    throw ServerLaunchError.notReady
  }

  fileprivate func isAcceptingConnections(port: Int) async -> Bool {
    var components = URLComponents()
    components.scheme = "ws"
    components.host = "127.0.0.1"
    components.port = port
    components.path = "/"
    components.queryItems = [URLQueryItem(name: "token", value: ServerConfig.runtimeToken)]
    guard let url = components.url else { return false }
    let session = URLSession(configuration: .ephemeral)
    let task = session.webSocketTask(with: url)
    task.resume()

    let responded = await withCheckedContinuation { continuation in
      task.sendPing { error in
        continuation.resume(returning: error == nil)
      }
    }

    task.cancel(with: .goingAway, reason: nil)
    return responded
  }

  nonisolated fileprivate func availableLoopbackPort() throws -> UInt16 {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw ServerLaunchError.notReady }
    defer { Darwin.close(descriptor) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bindResult == 0 else { throw ServerLaunchError.notReady }

    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        getsockname(descriptor, $0, &length)
      }
    }
    guard nameResult == 0 else { throw ServerLaunchError.notReady }
    return UInt16(bigEndian: address.sin_port)
  }

  fileprivate func terminateProcess(_ process: Process) {
    // Try SIGINT first so the server can run its shutdown handler.
    if process.isRunning {
      process.interrupt()
      if waitForExit(process, timeout: 2.0) { return }
    }

    // Fallback to SIGTERM.
    if process.isRunning {
      process.terminate()
      if waitForExit(process, timeout: 2.0) { return }
    }

    // Last resort: SIGKILL.
    if process.isRunning {
      _ = kill(process.processIdentifier, SIGKILL)
      _ = waitForExit(process, timeout: 1.0)
    }
  }

  fileprivate func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.05)
    }
    return !process.isRunning
  }
}
