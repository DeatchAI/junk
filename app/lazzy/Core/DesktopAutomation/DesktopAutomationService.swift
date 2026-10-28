import AppKit
import ApplicationServices
import CoreGraphics

@MainActor final class DesktopAutomationService {
  static let shared = DesktopAutomationService()
  var sessions: [String: DesktopSession] = [:]
  var endedSessions: [String: Date] = [:]
  var appLeases: [pid_t: String] = [:]
  var globalInputOwner: String?
  var stopHandlers: [String: () -> Void] = [:]
  let indicator = DesktopControlIndicator()
  let mutationCommands: Set<String> = ["desktop.click", "desktop.type", "desktop.key", "desktop.scroll",
    "desktop.drag", "desktop.select_text", "desktop.set_value", "desktop.perform_action", "desktop.activate_app", "desktop.open_app"]

  func execute(command: String, payload: [String: Any]) async throws -> Any {
    if command == "desktop.status" { return status() }
    if command == "desktop.list_apps" { return listApplications() }
    guard let id = string(payload["_sessionId"]), !id.isEmpty else {
      throw DesktopAutomationError("An active task is required.", code: "session_required")
    }
    if command == "desktop.end_session" { endSession(id); return ["ended": true] }
    // Bound abandoned state, without evicting an in-flight operation.
    for (key, value) in sessions where !value.busy && Date().timeIntervalSince(value.lastUsed) > 1800 {
      sessions.removeValue(forKey: key)
    }
    guard endedSessions[id] == nil else { throw DesktopAutomationError("The task was stopped.", code: "cancelled") }
    let session = sessions[id] ?? DesktopSession(id: id)
    sessions[id] = session
    guard !session.busy else { throw DesktopAutomationError("This task has an operation in progress.", code: "task_busy") }
    try checkSession(session, payload)
    session.busy = true
    session.lastUsed = Date()
    defer { session.busy = false; if session.cancelled { sessions.removeValue(forKey: id) } }
    if command == "desktop.open_app" { return try await openApplication(payload, session: session) }
    if command == "desktop.list_windows" { return try listWindows(payload, session: session) }
    if ["desktop.snapshot", "desktop.observe", "desktop.screenshot", "desktop.wait"].contains(command) {
      return try await observeCommand(command, payload: payload, session: session)
    }
    guard mutationCommands.contains(command) else { throw DesktopAutomationError("Unknown macOS command: \(command)") }
    try requireAccessibility()
    let observation = try checkedObservation(session, payload: payload)
    let pid = observation.application.processIdentifier
    guard appLeases[pid] == nil else {
      throw DesktopAutomationError("Another task is controlling this app. Retry after it finishes.", code: "app_busy")
    }
    appLeases[pid] = id
    defer { appLeases.removeValue(forKey: pid); indicator.hide(session: id) }
    try yieldToHuman(observation, global: bool(payload["allowForeground"]) == true)
    indicator.show(app: observation.application.localizedName ?? "App", session: id) { [weak self] in
      let handler = self?.stopHandlers[id]; self?.endSession(id); handler?()
    }
    try checkSession(session, payload)
    let before = observation.nodes
    let action = try await perform(command, payload: payload, observation: observation, session: session)
    try checkSession(session, payload)
    var result = action
    let timeout = min(max(double(payload["waitMs"]) ?? 500, 0), 3000)
    let deadline = Date().addingTimeInterval(timeout / 1000)
    var after: [String: Any] = [:]
    repeat {
      try await Task.sleep(for: .milliseconds(60))
      try checkSession(session, payload)
      after = try snapshotFor(observation.application, window: observation.window, session: session,
        maxDepth: 12, maxElements: 500, diff: false)
      if !nodesEqual(before, session.observation?.nodes ?? []) { break }
    } while Date() < deadline
    let changed = !nodesEqual(before, session.observation?.nodes ?? [])
    var verified = false
    if let expected = action["expectedValue"] as? String,
      let ref = action["verificationRef"] as? String, let element = observation.elements[ref] {
      verified = stringAttribute(kAXValueAttribute as CFString, from: element) == expected
    }
    result.removeValue(forKey: "expectedValue")
    result.removeValue(forKey: "verificationRef")
    result["inputDelivered"] = true
    result["uiChanged"] = changed
    result["effectVerified"] = verified
    result["verification"] = verified ? "requested_value_confirmed" : changed ? "ui_changed" : "effect_not_verified"
    result["observation"] = after
    result["hint"] = verified || changed ? NSNull() : "No UI change was observed. Inspect the target before retrying; input may have been ignored."
    return result
  }

  func checkSession(_ session: DesktopSession, _ payload: [String: Any]) throws {
    guard !session.cancelled, !Task.isCancelled else {
      throw DesktopAutomationError("The task was stopped.", code: "cancelled")
    }
    if let deadline = double(payload["_deadline"]), Date().timeIntervalSince1970 > deadline {
      throw DesktopAutomationError("The operation expired before execution.", code: "deadline_exceeded")
    }
  }

  func endSession(_ id: String) {
    endedSessions[id] = Date()
    if endedSessions.count > 2000 {
      for (key, date) in endedSessions where Date().timeIntervalSince(date) > 3600 { endedSessions.removeValue(forKey: key) }
    }
    guard let session = sessions[id] else { return }
    session.cancelled = true
    session.observation = nil
    session.previousNodes = []
    indicator.hide(session: id)
    stopHandlers.removeValue(forKey: id)
    if !session.busy { sessions.removeValue(forKey: id) }
  }

  func status() -> [String: Any] {
    ["accessibilityGranted": AXIsProcessTrusted(), "screenRecordingGranted": CGPreflightScreenCaptureAccess(),
      "frontmostApplication": NSWorkspace.shared.frontmostApplication.map(applicationInfo) ?? [:],
      "capabilities": ["windowObservations", "taskIsolation", "backgroundInput", "verifiedEditing", "localOCR", "drag", "selection"],
      "permissionHelp": ["accessibility": "Enable Accessibility for Detach in System Settings > Privacy & Security.",
        "screenRecording": "Enable Screen & System Audio Recording for Detach in System Settings > Privacy & Security."]]
  }

  func listApplications() -> [String: Any] {
    ["applications": NSWorkspace.shared.runningApplications
      .filter { !$0.isTerminated && $0.activationPolicy != .prohibited && $0.localizedName != nil }
      .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }.map(applicationInfo)]
  }

  func nodesEqual(_ left: [[String: Any]], _ right: [[String: Any]]) -> Bool {
    func normalized(_ nodes: [[String: Any]]) -> [[String: Any]] {
      nodes.map { $0.filter { !["ref", "parentRef"].contains($0.key) } }
    }
    return NSArray(array: normalized(left)).isEqual(to: normalized(right))
  }
}
