import Foundation

private enum TestError: Error { case failed }

private final class FakePower: PowerGuardBackend {
  var disabled = false
  var changes: [Bool] = []
  var failAfterEnable = false
  var failRestore = false

  func sleepIsDisabled() throws -> Bool { disabled }
  func setSleepDisabled(_ value: Bool) throws {
    changes.append(value)
    if !value && failRestore { throw TestError.failed }
    disabled = value
    if value && failAfterEnable { throw TestError.failed }
  }
}

private final class FakeJournal: PowerGuardJournal {
  var pending = false
  var failRecord = false
  var invalid = false
  func hasPendingChange() throws -> Bool {
    if invalid { throw TestError.failed }
    return pending
  }
  func recordPendingChange() throws {
    if failRecord { throw TestError.failed }
    pending = true
  }
  func clearPendingChange() throws { pending = false }
}

@main struct PowerGuardTests {
  static func main() throws {
    try concurrentTasksKeepTheLeaseUntilTheLastFinishes()
    try existingSleepPolicyIsPreserved()
    try recoverySurvivesHelperRestart()
    try failedEnableDoesNotLeaveSleepDisabled()
    try failedRecoveryRemainsRetryable()
    try invalidOrUnwritableJournalFailsClosed()
    print("Keep-awake ownership, concurrent tasks, failure and restart recovery passed")
  }

  static func concurrentTasksKeepTheLeaseUntilTheLastFinishes() throws {
    let power = FakePower(), journal = FakeJournal()
    let engine = PowerGuardEngine(backend: power, journal: journal)
    let first = UUID(), second = UUID()
    try engine.acquire(first)
    try engine.acquire(second)
    precondition(power.disabled && journal.pending && power.changes == [true])
    try engine.release(first)
    precondition(power.disabled && journal.pending)
    try engine.release(second)
    precondition(!power.disabled && !journal.pending && power.changes == [true, false])
  }

  static func existingSleepPolicyIsPreserved() throws {
    let power = FakePower(), journal = FakeJournal()
    power.disabled = true
    let engine = PowerGuardEngine(backend: power, journal: journal)
    let id = UUID()
    try engine.acquire(id)
    try engine.release(id)
    precondition(power.disabled && power.changes.isEmpty && !journal.pending)
  }

  static func recoverySurvivesHelperRestart() throws {
    let power = FakePower(), journal = FakeJournal()
    let first = PowerGuardEngine(backend: power, journal: journal)
    try first.acquire(UUID())
    let restarted = PowerGuardEngine(backend: power, journal: journal)
    try restarted.recover()
    precondition(!power.disabled && !journal.pending)
  }

  static func failedEnableDoesNotLeaveSleepDisabled() throws {
    let power = FakePower(), journal = FakeJournal()
    power.failAfterEnable = true
    let engine = PowerGuardEngine(backend: power, journal: journal)
    do { try engine.acquire(UUID()); preconditionFailure("Expected enable to fail") }
    catch {}
    precondition(!power.disabled && !journal.pending && engine.leases.isEmpty)
  }

  static func failedRecoveryRemainsRetryable() throws {
    let power = FakePower(), journal = FakeJournal()
    let engine = PowerGuardEngine(backend: power, journal: journal)
    let id = UUID()
    try engine.acquire(id)
    power.failRestore = true
    do { try engine.release(id); preconditionFailure("Expected restore to fail") }
    catch {}
    precondition(power.disabled && journal.pending && engine.leases.isEmpty)
    power.failRestore = false
    try engine.retryRecovery()
    precondition(!power.disabled && !journal.pending)
  }

  static func invalidOrUnwritableJournalFailsClosed() throws {
    let power = FakePower(), journal = FakeJournal()
    let engine = PowerGuardEngine(backend: power, journal: journal)
    journal.invalid = true
    do { try engine.acquire(UUID()); preconditionFailure("Expected invalid journal to fail") }
    catch {}
    journal.invalid = false
    journal.failRecord = true
    do { try engine.acquire(UUID()); preconditionFailure("Expected journal write to fail") }
    catch {}
    precondition(!power.disabled && power.changes.isEmpty)
  }
}
