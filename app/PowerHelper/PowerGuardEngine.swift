import Foundation

protocol PowerGuardBackend {
  func sleepIsDisabled() throws -> Bool
  func setSleepDisabled(_ disabled: Bool) throws
}

protocol PowerGuardJournal {
  func hasPendingChange() throws -> Bool
  func recordPendingChange() throws
  func clearPendingChange() throws
}

/// Owns only changes that this helper recorded before requesting them.
/// All operations are serialized by the helper's service queue.
final class PowerGuardEngine {
  private let backend: PowerGuardBackend
  private let journal: PowerGuardJournal
  private(set) var leases = Set<UUID>()
  private(set) var ownsChange = false

  init(backend: PowerGuardBackend, journal: PowerGuardJournal) {
    self.backend = backend
    self.journal = journal
  }

  func recover() throws {
    guard try journal.hasPendingChange() else { return }
    if try backend.sleepIsDisabled() {
      try backend.setSleepDisabled(false)
      guard try !backend.sleepIsDisabled() else { throw PowerGuardError.restoreFailed }
    }
    try journal.clearPendingChange()
    ownsChange = false
  }

  func acquire(_ id: UUID) throws {
    guard !leases.contains(id) else { return }
    if leases.isEmpty {
      try recover()
      if try !backend.sleepIsDisabled() {
        try journal.recordPendingChange()
        do {
          try backend.setSleepDisabled(true)
          guard try backend.sleepIsDisabled() else { throw PowerGuardError.enableFailed }
          ownsChange = true
        } catch {
          // The command can fail after changing the setting. Leave the journal
          // in place unless recovery proves that sleep was restored.
          do { try recover() } catch { throw PowerGuardError.restoreFailed }
          throw error
        }
      }
    }
    leases.insert(id)
  }

  func release(_ id: UUID) throws {
    guard leases.remove(id) != nil else { return }
    guard leases.isEmpty else { return }
    try restoreOwnedChange()
  }

  func releaseAll() throws {
    leases.removeAll()
    try restoreOwnedChange()
  }

  func retryRecovery() throws {
    guard leases.isEmpty else { return }
    try recover()
  }

  private func restoreOwnedChange() throws {
    try recover()
  }
}

enum PowerGuardError: LocalizedError {
  case enableFailed, restoreFailed, invalidJournal, unreadablePowerState, commandFailed

  var errorDescription: String? {
    switch self {
    case .enableFailed: return "macOS did not enable keep awake."
    case .restoreFailed: return "Detach could not restore the previous sleep setting."
    case .invalidJournal: return "The keep-awake recovery record is unreadable."
    case .unreadablePowerState: return "Detach could not read the Mac's sleep setting."
    case .commandFailed: return "macOS could not change the sleep setting."
    }
  }
}
