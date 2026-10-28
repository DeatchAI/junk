import AppKit
import Combine
import Foundation
import ServiceManagement

/// A single saved preference, active only while real agent runs are working.
@MainActor final class KeepAwakeController: ObservableObject {
  private static let preferenceKey = "keep_mac_awake_while_agents_work"
  @Published private(set) var isEnabled: Bool
  @Published private(set) var isKeepingAwake = false
  @Published private(set) var message: String?

  private let service = SMAppService.daemon(plistName: KeepAwakeServiceIdentity.plistName)
  private var cancellables = Set<AnyCancellable>()
  private var connection: NSXPCConnection?
  private var notifier: KeepAwakeNotifier?
  private var heartbeat: Timer?
  private var connectionTimeout: DispatchWorkItem?
  private var operation = UUID()
  private var hasWorkingRuns = false
  private var isSuspended = false

  init(runStore: DetachedRunStore) {
    isEnabled = UserDefaults.standard.bool(forKey: Self.preferenceKey)
    runStore.$runs
      .map(KeepAwakeWorkPolicy.isWorking)
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] working in
        self?.hasWorkingRuns = working
        self?.reconcile()
      }
      .store(in: &cancellables)
    NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.reconcile() }
      .store(in: &cancellables)
  }

  func setEnabled(_ enabled: Bool) {
    isEnabled = enabled
    UserDefaults.standard.set(enabled, forKey: Self.preferenceKey)
    message = nil
    if enabled { prepareService() }
    reconcile()
  }

  func resume() {
    isSuspended = false
    reconcile()
  }

  func suspend() {
    isSuspended = true
    release()
  }

  private func prepareService() {
    guard service.status == .notRegistered else {
      if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
      return
    }
    do {
      try service.register()
      if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    } catch {
      if service.status == .requiresApproval {
        SMAppService.openSystemSettingsLoginItems()
        return
      }
      isEnabled = false
      UserDefaults.standard.set(false, forKey: Self.preferenceKey)
      message = "Could not enable keep awake: \(error.localizedDescription)"
    }
  }

  private func reconcile() {
    guard isEnabled, !isSuspended else { release(); return }
    switch service.status {
    case .enabled:
      if message == "Allow Detach in Login Items to enable keep awake." { message = nil }
    case .requiresApproval:
      release()
      message = "Allow Detach in Login Items to enable keep awake."
      return
    case .notRegistered:
      release()
      if message == nil { message = "Keep awake is not available. Turn it off and on to try again." }
      return
    default:
      release()
      message = "Keep awake is unavailable on this Mac."
      return
    }
    guard hasWorkingRuns else { release(); return }
    guard connection == nil else { return }
    acquire()
  }

  private func acquire() {
    guard let requirement = KeepAwakeServiceIdentity.helperRequirement else {
      message = "Keep awake requires a signed Detach build."
      return
    }
    let id = UUID()
    operation = id
    let connection = NSXPCConnection(machServiceName: KeepAwakeServiceIdentity.machService, options: .privileged)
    let notifier = KeepAwakeNotifier { [weak self] reason in
      Task { @MainActor in self?.connectionFailed(id: id, message: reason) }
    }
    connection.exportedInterface = NSXPCInterface(with: KeepAwakeClientProtocol.self)
    connection.exportedObject = notifier
    connection.remoteObjectInterface = NSXPCInterface(with: KeepAwakeHelperProtocol.self)
    connection.setCodeSigningRequirement(requirement)
    connection.invalidationHandler = { [weak self] in
      Task { @MainActor in self?.connectionFailed(id: id, message: "Keep awake disconnected.") }
    }
    connection.interruptionHandler = { [weak self] in
      Task { @MainActor in self?.connectionFailed(id: id, message: "Keep awake was interrupted.") }
    }
    self.notifier = notifier
    self.connection = connection
    connection.resume()
    let timeout = DispatchWorkItem { [weak self] in
      Task { @MainActor in self?.connectionFailed(id: id, message: "Keep awake did not start.") }
    }
    connectionTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)
    guard let helper = proxy(for: connection, id: id) else {
      connectionFailed(id: id, message: "Keep awake is unavailable.")
      return
    }
    helper.acquire { [weak self] error in
      Task { @MainActor in
        guard let self, self.operation == id else { return }
        self.connectionTimeout?.cancel()
        self.connectionTimeout = nil
        if let error { self.connectionFailed(id: id, message: error); return }
        self.message = nil
        self.isKeepingAwake = true
        self.startHeartbeat(id: id)
      }
    }
  }

  private func startHeartbeat(id: UUID) {
    heartbeat?.invalidate()
    let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
      guard let controller = self else { return }
      Task { @MainActor in controller.sendHeartbeat(id: id) }
    }
    RunLoop.main.add(timer, forMode: .common)
    heartbeat = timer
  }

  private func sendHeartbeat(id: UUID) {
    guard operation == id, let connection, let helper = proxy(for: connection, id: id) else { return }
    helper.heartbeat { [weak self] error in
      guard let error else { return }
      Task { @MainActor in self?.connectionFailed(id: id, message: error) }
    }
  }

  private func proxy(for connection: NSXPCConnection, id: UUID) -> KeepAwakeHelperProtocol? {
    connection.remoteObjectProxyWithErrorHandler { [weak self] error in
      Task { @MainActor in self?.connectionFailed(id: id, message: error.localizedDescription) }
    } as? KeepAwakeHelperProtocol
  }

  private func release() {
    connectionTimeout?.cancel()
    connectionTimeout = nil
    heartbeat?.invalidate()
    heartbeat = nil
    isKeepingAwake = false
    guard let connection else { return }
    let releaseID = UUID()
    operation = releaseID
    self.connection = nil
    notifier = nil
    let helper = connection.remoteObjectProxyWithErrorHandler { _ in connection.invalidate() } as? KeepAwakeHelperProtocol
    guard let helper else { connection.invalidate(); return }
    helper.release { [weak self] error in
      connection.invalidate()
      guard let error else { return }
      Task { @MainActor in
        guard let self, self.operation == releaseID else { return }
        self.message = error
      }
    }
  }

  private func connectionFailed(id: UUID, message: String) {
    guard operation == id else { return }
    release()
    self.message = message
  }
}

private final class KeepAwakeNotifier: NSObject, KeepAwakeClientProtocol {
  private let onStop: (String) -> Void
  init(onStop: @escaping (String) -> Void) { self.onStop = onStop }
  func keepAwakeStopped(reason: String) { onStop(reason) }
}
