import AppKit
import Darwin
import Foundation

@MainActor
final class RemoteMachineRuntimeConnector {
  static let shared = RemoteMachineRuntimeConnector()

  private struct Tunnel {
    let process: Process
    let endpoint: RuntimeEndpoint
  }

  private var tunnels: [UUID: Tunnel] = [:]
  private var terminationObserver: NSObjectProtocol?

  private init() {
    terminationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification, object: nil, queue: .main
    ) { [weak self] _ in
      guard let connector = self else { return }
      Task { @MainActor in connector.disconnectAll() }
    }
  }

  deinit {
    if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
  }

  func disconnect(machineID: UUID) {
    guard let tunnel = tunnels.removeValue(forKey: machineID), tunnel.process.isRunning else { return }
    tunnel.process.terminate()
  }

  func disconnectAll() {
    for id in Array(tunnels.keys) { disconnect(machineID: id) }
  }

  func connect(to selection: RemoteWorkspaceSelection, forceReconnect: Bool = false) async throws -> RuntimeEndpoint {
    if let tunnel = tunnels[selection.machineID], tunnel.process.isRunning, !forceReconnect {
      if await Self.isEndpointHealthy(tunnel.endpoint) { return tunnel.endpoint }
      tunnel.process.terminate()
      tunnels.removeValue(forKey: selection.machineID)
    }
    if forceReconnect, let tunnel = tunnels.removeValue(forKey: selection.machineID), tunnel.process.isRunning {
      tunnel.process.terminate()
    }
    guard let machine = RemoteMachineStore.shared.machine(id: selection.machineID) else {
      throw RemoteMachineError.machineNotFound
    }

    let token = try RemoteMachineTokenVault.token(machineID: machine.id)
    let isReady = await RemoteSSHClient.runtimeIsReady(
      host: machine.host, port: machine.remotePort, token: token
    )
    if !isReady {
      let runtime = try await RemoteRuntimeArtifactProvider.artifact(for: machine.platform)
      try await RemoteSSHClient.upload(runtime: runtime, to: machine.host)
      try await RemoteSSHClient.ensureRuntime(host: machine.host, port: machine.remotePort, token: token)
    }

    let localPort = try Self.availableLoopbackPort()
    let process = try RemoteSSHClient.startTunnel(host: machine.host, localPort: localPort, remotePort: machine.remotePort)
    guard await Self.waitForTunnel(localPort: localPort, process: process) else {
      process.terminate()
      throw RemoteMachineError.tunnelUnavailable
    }

    let endpoint = RuntimeEndpoint(host: "127.0.0.1", port: localPort, token: token, machineID: machine.id)
    tunnels[machine.id] = Tunnel(process: process, endpoint: endpoint)
    let machineID = machine.id
    let processIdentifier = process.processIdentifier
    process.terminationHandler = { [weak self] _ in
      guard let connector = self else { return }
      Task { @MainActor in
        guard connector.tunnels[machineID]?.process.processIdentifier == processIdentifier else { return }
        connector.tunnels.removeValue(forKey: machineID)
      }
    }
    return endpoint
  }

  private static func waitForTunnel(localPort: Int, process: Process) async -> Bool {
    for _ in 0..<40 {
      if !process.isRunning { return false }
      if canConnectToLoopback(port: localPort) { return true }
      try? await Task.sleep(for: .milliseconds(200))
    }
    return false
  }

  private static func isEndpointHealthy(_ endpoint: RuntimeEndpoint) async -> Bool {
    var components = URLComponents()
    components.scheme = "http"; components.host = endpoint.host; components.port = endpoint.port
    components.path = "/"
    guard let url = components.url else { return false }
    var request = URLRequest(url: url, timeoutInterval: 3)
    request.setValue(endpoint.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      return (response as? HTTPURLResponse)?.statusCode == 200
    } catch {
      return false
    }
  }

  private static func canConnectToLoopback(port: Int) -> Bool {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { return false }
    defer { Darwin.close(descriptor) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(port).bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    return withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
      }
    }
  }

  private static func availableLoopbackPort() throws -> Int {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw RemoteMachineError.tunnelUnavailable }
    defer { Darwin.close(descriptor) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    let bound = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bound == 0 else { throw RemoteMachineError.tunnelUnavailable }
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let named = withUnsafeMutablePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        getsockname(descriptor, $0, &length)
      }
    }
    guard named == 0 else { throw RemoteMachineError.tunnelUnavailable }
    return Int(UInt16(bigEndian: address.sin_port))
  }
}

private enum RemoteRuntimeArtifactProvider {
  static func artifact(for platform: RemoteMachinePlatform) async throws -> URL {
    let filename = "detach-runtime-\(platform.rawValue)"
    if let bundled = Bundle.main.url(forResource: filename, withExtension: nil, subdirectory: "RemoteRuntimes") {
      return bundled
    }

    #if DEBUG
      let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
      let development = sourceRoot.appendingPathComponent("server-v2/remote-runtimes/\(filename)")
      if FileManager.default.isExecutableFile(atPath: development.path) { return development }
    #endif

    let cache = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Detach/RemoteRuntimes", isDirectory: true)
      .appendingPathComponent(filename)
    if FileManager.default.isExecutableFile(atPath: cache.path) { return cache }

    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let releasePath = version.map { "releases/download/v\($0)/\(filename)" } ?? "releases/latest/download/\(filename)"
    guard let url = URL(string: "https://github.com/DeatchAI/App/\(releasePath)") else {
      throw RemoteMachineError.runtimeArtifactUnavailable
    }
    do {
      let (temporary, response) = try await URLSession.shared.download(from: url)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw RemoteMachineError.runtimeArtifactUnavailable
      }
      try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: cache.path) { try FileManager.default.removeItem(at: cache) }
      try FileManager.default.copyItem(at: temporary, to: cache)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cache.path)
      return cache
    } catch let error as RemoteMachineError {
      throw error
    } catch {
      throw RemoteMachineError.runtimeArtifactUnavailable
    }
  }
}

