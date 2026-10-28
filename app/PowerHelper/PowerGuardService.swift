import Darwin
import Foundation

final class PowerGuardService: NSObject, NSXPCListenerDelegate {
  private let queue = DispatchQueue(label: "app.getlazzy.keep-awake.guard")
  private let engine: PowerGuardEngine
  private let backend: PowerGuardBackend
  private let safetyCheck: () -> String?
  private var connections: [UUID: NSXPCConnection] = [:]
  private var lastHeartbeat: [UUID: TimeInterval] = [:]
  private var recoveryError: String?
  private var timer: DispatchSourceTimer?
  private var terminationSources: [DispatchSourceSignal] = []
  private var idleSince = ProcessInfo.processInfo.systemUptime

  init(backend: PowerGuardBackend = SystemPowerBackend(),
    journal: PowerGuardJournal = SystemPowerGuardJournal(),
    safetyCheck: @escaping () -> String? = PowerSafety.stopReason, monitor: Bool = true) {
    self.backend = backend
    self.engine = PowerGuardEngine(backend: backend, journal: journal)
    self.safetyCheck = safetyCheck
    super.init()
    queue.sync {
      do { try engine.recover() }
      catch { recoveryError = error.localizedDescription }
    }
    if monitor {
      let timer = DispatchSource.makeTimerSource(queue: queue)
      timer.schedule(deadline: .now() + 5, repeating: 5)
      timer.setEventHandler { [weak self] in self?.checkSafety() }
      timer.resume()
      self.timer = timer
      installTerminationHandlers()
    }
  }

  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
    guard let requirement = KeepAwakeServiceIdentity.appRequirement else { return false }
    connection.setCodeSigningRequirement(requirement)
    let id = UUID()
    let client = PowerGuardClient(id: id, service: self)
    connection.exportedInterface = NSXPCInterface(with: KeepAwakeHelperProtocol.self)
    connection.exportedObject = client
    connection.remoteObjectInterface = NSXPCInterface(with: KeepAwakeClientProtocol.self)
    connection.invalidationHandler = { [weak self] in self?.disconnect(id) }
    connection.interruptionHandler = { [weak self] in self?.disconnect(id) }
    queue.sync { connections[id] = connection }
    connection.resume()
    return true
  }

  func acquire(_ id: UUID, reply: @escaping (String?) -> Void) {
    queue.async {
      guard self.connections[id] != nil else { reply("The keep-awake connection was lost."); return }
      if let reason = self.safetyCheck() { reply(reason); return }
      do {
        try self.engine.acquire(id)
        self.recoveryError = nil
        self.lastHeartbeat[id] = ProcessInfo.processInfo.systemUptime
        reply(nil)
      } catch {
        self.recoveryError = error.localizedDescription
        reply(error.localizedDescription)
      }
    }
  }

  func heartbeat(_ id: UUID, reply: @escaping (String?) -> Void) {
    queue.async {
      guard self.engine.leases.contains(id) else {
        reply(self.recoveryError ?? "Keep awake stopped.")
        return
      }
      self.lastHeartbeat[id] = ProcessInfo.processInfo.systemUptime
      reply(nil)
    }
  }

  func release(_ id: UUID, reply: @escaping (String?) -> Void) {
    queue.async {
      self.lastHeartbeat.removeValue(forKey: id)
      do {
        try self.engine.release(id)
        self.recoveryError = nil
        reply(nil)
      } catch {
        self.recoveryError = error.localizedDescription
        reply(error.localizedDescription)
      }
    }
  }

  private func disconnect(_ id: UUID) {
    queue.async {
      self.connections.removeValue(forKey: id)
      self.lastHeartbeat.removeValue(forKey: id)
      do { try self.engine.release(id) }
      catch { self.recoveryError = error.localizedDescription }
      if self.connections.isEmpty { self.idleSince = ProcessInfo.processInfo.systemUptime }
    }
  }

  private func checkSafety() {
    if engine.leases.isEmpty {
      do { try engine.retryRecovery(); recoveryError = nil }
      catch { recoveryError = error.localizedDescription }
      if recoveryError == nil, connections.isEmpty, ProcessInfo.processInfo.systemUptime - idleSince >= 15 {
        exit(0)
      }
      return
    }
    let now = ProcessInfo.processInfo.systemUptime
    let expired = engine.leases.filter { now - (lastHeartbeat[$0] ?? 0) > 45 }
    for id in expired { stop(id, reason: "Detach stopped responding.") }
    if !engine.leases.isEmpty {
      do {
        if try !backend.sleepIsDisabled() {
          for id in Array(engine.leases) { stop(id, reason: "macOS allowed the Mac to sleep.") }
        }
      } catch {
        for id in Array(engine.leases) { stop(id, reason: "Detach could not verify the sleep setting.") }
      }
    }
    if let reason = safetyCheck() {
      for id in Array(engine.leases) { stop(id, reason: reason) }
    }
  }

  private func stop(_ id: UUID, reason: String) {
    lastHeartbeat.removeValue(forKey: id)
    var message = reason
    do { try engine.release(id) }
    catch { recoveryError = error.localizedDescription; message += " " + error.localizedDescription }
    (connections[id]?.remoteObjectProxy as? KeepAwakeClientProtocol)?.keepAwakeStopped(reason: message)
  }

  private func installTerminationHandlers() {
    for value in [SIGTERM, SIGINT] {
      signal(value, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: value, queue: queue)
      source.setEventHandler { [weak self] in
        do {
          try self?.engine.releaseAll()
          exit(0)
        } catch {
          NSLog("Keep-awake recovery failed: %@", error.localizedDescription)
          exit(1)
        }
      }
      source.resume()
      terminationSources.append(source)
    }
  }
}

private final class PowerGuardClient: NSObject, KeepAwakeHelperProtocol {
  private let id: UUID
  private weak var service: PowerGuardService?

  init(id: UUID, service: PowerGuardService) { self.id = id; self.service = service }

  func acquire(reply: @escaping (String?) -> Void) {
    guard let service else { reply("Keep awake is unavailable."); return }
    service.acquire(id, reply: reply)
  }
  func heartbeat(reply: @escaping (String?) -> Void) {
    guard let service else { reply("Keep awake is unavailable."); return }
    service.heartbeat(id, reply: reply)
  }
  func release(reply: @escaping (String?) -> Void) {
    guard let service else { reply("Keep awake is unavailable."); return }
    service.release(id, reply: reply)
  }
}
