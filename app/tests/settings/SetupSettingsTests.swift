import Foundation

@MainActor private final class LoginItemDouble: LoginItemService {
  var status = LoginItemStatus.disabled
  var registrations = 0
  var removals = 0
  var shouldFail = false
  var requiresApproval = false
  func register() throws {
    registrations += 1
    if shouldFail { throw NSError(domain: "fixture", code: 1) }
    status = requiresApproval ? .requiresApproval : .enabled
  }
  func unregister() throws {
    removals += 1
    if shouldFail { throw NSError(domain: "fixture", code: 1) }
    status = .disabled
  }
}

@main struct SetupSettingsTests {
  @MainActor static func main() async throws {
    let service = LoginItemDouble()
    let setting = LaunchAtLoginController(service: service)
    assert(!setting.isEnabled)
    setting.setEnabled(true)
    assert(service.registrations == 1 && setting.isEnabled)
    let relaunched = LaunchAtLoginController(service: service)
    assert(relaunched.isEnabled, "Relaunch reads macOS state rather than a stale saved preference")
    setting.setEnabled(false)
    assert(service.removals == 1 && !setting.isEnabled)
    service.shouldFail = true
    setting.setEnabled(true)
    assert(!setting.isEnabled && setting.error != nil, "Failed registration restores actual system state")
    service.shouldFail = false; service.requiresApproval = true
    setting.setEnabled(true)
    assert(setting.isEnabled && setting.needsApproval)
    service.status = .disabled
    setting.refresh()
    assert(!setting.isEnabled && !setting.needsApproval, "Changes outside Detach are reflected")

    assert(AgentReadiness.parse(agent: .codex, exitCode: 1, output: "Not logged in").state == .signInNeeded)
    assert(AgentReadiness.parse(agent: .codex, exitCode: 0, output: "Logged in using ChatGPT").state == .ready)
    assert(AgentReadiness.parse(agent: .codex, exitCode: 1, output: "Logged in using ChatGPT").state == .installed)
    assert(AgentReadiness.parse(agent: .claude, exitCode: 0, output: #"{"loggedIn":false}"#).state == .signInNeeded)
    assert(AgentReadiness.parse(agent: .claude, exitCode: 0, output: #"{"loggedIn":true}"#).state == .ready)
    assert(AgentReadiness.parse(agent: .fx, exitCode: 0, output: #"{"kind":"status","auth":"missing"}"#).state == .signInNeeded)
    assert(AgentReadiness.parse(agent: .opencode, exitCode: 0, output: "models available").state == .installed,
      "A model catalog does not prove sign-in")

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("detach-status-tests-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("fixture")
    try "#!/bin/sh\n[ \"$1 $2\" = \"login status\" ] || exit 2\nprintf 'Logged in using ChatGPT'\n"
      .write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let result = await AgentStatusProbe.check(.codex, executable: executable.path)
    assert(result.state == .ready, "Status check invokes only the read-only status command")
    try "#!/bin/sh\nexec /bin/sleep 30\n".write(to: executable, atomically: true, encoding: .utf8)
    let started = Date()
    let pending = Task { await AgentStatusProbe.check(.codex, executable: executable.path) }
    try await Task.sleep(nanoseconds: 100_000_000)
    pending.cancel()
    let cancelled = await pending.value
    assert(cancelled.state == .installed && Date().timeIntervalSince(started) < 2,
      "Cancelling setup terminates a hung status process promptly")
    print("Login registration, relaunch state, rollback, approval, and bounded read-only agent readiness passed")
  }
}
