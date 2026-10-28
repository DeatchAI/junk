import Foundation

private final class FakePower: PowerGuardBackend {
  private let lock = NSLock()
  private var value = false
  func sleepIsDisabled() throws -> Bool { lock.lock(); defer { lock.unlock() }; return value }
  func setSleepDisabled(_ disabled: Bool) throws { lock.lock(); value = disabled; lock.unlock() }
}

private final class FakeJournal: PowerGuardJournal {
  var pending = false
  func hasPendingChange() throws -> Bool { pending }
  func recordPendingChange() throws { pending = true }
  func clearPendingChange() throws { pending = false }
}

private final class FakeClient: NSObject, KeepAwakeClientProtocol {
  func keepAwakeStopped(reason: String) {}
}

@main struct PowerGuardXPCTests {
  static func main() throws {
    if CommandLine.arguments.contains("--expect-rejected") {
      try verifyUnauthorizedClientIsRejected()
      return
    }
    let power = FakePower(), journal = FakeJournal()
    let service = PowerGuardService(backend: power, journal: journal, safetyCheck: { nil }, monitor: false)
    let listener = NSXPCListener.anonymous()
    listener.delegate = service
    listener.resume()
    let first = try connect(to: listener.endpoint)
    let second = try connect(to: listener.endpoint)

    try call(first) { proxy, done in proxy.acquire(reply: done) }
    try call(second) { proxy, done in proxy.acquire(reply: done) }
    let acquired = try power.sleepIsDisabled()
    precondition(acquired)
    try call(first) { proxy, done in proxy.release(reply: done) }
    let retained = try power.sleepIsDisabled()
    precondition(retained, "One disconnected task must not release another")
    first.invalidate()
    second.invalidate()
    let deadline = Date().addingTimeInterval(5)
    while try power.sleepIsDisabled(), Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
    let restored = try !power.sleepIsDisabled()
    precondition(restored, "Disconnect must restore the previous setting")
    listener.invalidate()
    withExtendedLifetime(service) {}
    print("Signed XPC connections preserve concurrent leases and restore on disconnect")
  }

  private static func verifyUnauthorizedClientIsRejected() throws {
    let power = FakePower(), journal = FakeJournal()
    let service = PowerGuardService(backend: power, journal: journal, safetyCheck: { nil }, monitor: false)
    let listener = NSXPCListener.anonymous()
    listener.delegate = service
    listener.resume()
    let connection = try connect(to: listener.endpoint, verifyPeer: false)
    do {
      try call(connection) { proxy, done in proxy.acquire(reply: done) }
      preconditionFailure("A differently signed client must be rejected")
    } catch {
      precondition((error as NSError).code == 3, "The untrusted client must be rejected without timing out")
    }
    let changed = try power.sleepIsDisabled()
    precondition(!changed, "An untrusted client cannot change the sleep setting")
    connection.invalidate()
    listener.invalidate()
    withExtendedLifetime(service) {}
    print("A differently signed client cannot acquire a lease")
  }

  private static func connect(to endpoint: NSXPCListenerEndpoint, verifyPeer: Bool = true) throws -> NSXPCConnection {
    guard let requirement = KeepAwakeServiceIdentity.appRequirement else {
      throw NSError(domain: "KeepAwakeTest", code: 1)
    }
    let connection = NSXPCConnection(listenerEndpoint: endpoint)
    connection.remoteObjectInterface = NSXPCInterface(with: KeepAwakeHelperProtocol.self)
    connection.exportedInterface = NSXPCInterface(with: KeepAwakeClientProtocol.self)
    connection.exportedObject = FakeClient()
    if verifyPeer { connection.setCodeSigningRequirement(requirement) }
    connection.resume()
    return connection
  }

  private static func call(_ connection: NSXPCConnection,
    _ action: (KeepAwakeHelperProtocol, @escaping (String?) -> Void) -> Void) throws {
    let semaphore = DispatchSemaphore(value: 0)
    var failure: String?
    guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
      failure = error.localizedDescription
      semaphore.signal()
    }) as? KeepAwakeHelperProtocol else { throw NSError(domain: "KeepAwakeTest", code: 2) }
    action(proxy) { error in failure = error; semaphore.signal() }
    guard semaphore.wait(timeout: .now() + 5) == .success else {
      throw NSError(domain: "KeepAwakeTest", code: 4,
        userInfo: [NSLocalizedDescriptionKey: "XPC request timed out"])
    }
    if let failure {
      throw NSError(domain: "KeepAwakeTest", code: 3,
        userInfo: [NSLocalizedDescriptionKey: failure])
    }
  }
}
