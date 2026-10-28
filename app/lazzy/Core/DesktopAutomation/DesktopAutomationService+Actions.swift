import AppKit
import ApplicationServices

extension DesktopAutomationService {
  func perform(_ command: String, payload: [String: Any], observation: DesktopObservation,
    session: DesktopSession) async throws -> [String: Any] {
    if command == "desktop.activate_app" {
      guard bool(payload["allowForeground"]) == true else {
        throw DesktopAutomationError("Activation requires allowForeground:true.", code: "foreground_required")
      }
      guard globalInputOwner == nil else { throw DesktopAutomationError("Another task is using foreground input.", code: "desktop_busy") }
      globalInputOwner = session.id
      defer { globalInputOwner = nil }
      try await activateTarget(observation)
      return ["method": "foreground_activation"]
    }
    if command == "desktop.type" || command == "desktop.set_value" {
      return try editText(payload, observation: observation, replace: command == "desktop.set_value" || bool(payload["replace"]) == true)
    }
    if command == "desktop.select_text" { return try selectText(payload, observation: observation) }
    if command == "desktop.perform_action" {
      let target = try element(payload, observation: observation)
      guard let action = string(payload["action"]), !action.isEmpty else { throw DesktopAutomationError("action is required") }
      var names: CFArray?
      AXUIElementCopyActionNames(target, &names)
      guard (names as? [String] ?? []).contains(action), AXUIElementPerformAction(target, action as CFString) == .success else {
        throw DesktopAutomationError("The element does not expose this action, or it failed.", code: "action_failed")
      }
      return ["method": "accessibility_action", "action": action]
    }
    if command == "desktop.click", let ref = string(payload["ref"]),
      let target = try? element(["ref": ref], observation: observation), (string(payload["button"]) ?? "left") == "left",
      clampedInt(payload["clickCount"], defaultValue: 1, range: 1...3) == 1,
      AXUIElementPerformAction(target, kAXPressAction as CFString) == .success {
      return ["method": "accessibility_press"]
    }
    let foreground = bool(payload["allowForeground"]) == true
    defer { if globalInputOwner == session.id { globalInputOwner = nil } }
    if foreground {
      guard globalInputOwner == nil else { throw DesktopAutomationError("Another task is using foreground input.", code: "desktop_busy") }
      globalInputOwner = session.id
      try await activateTarget(observation)
    } else { try requireBackgroundWindow(observation) }
    try checkSession(session, payload)
    _ = try checkedObservation(session, payload: payload)
    try yieldToHuman(observation, global: foreground)
    let pid = observation.application.processIdentifier
    switch command {
    case "desktop.click":
      let point = try inputPoint(payload, observation: observation)
      let button = string(payload["button"]) ?? "left"
      guard ["left", "right"].contains(button) else { throw DesktopAutomationError("button must be left or right") }
      try sendClick(point, pid: pid, foreground: foreground, button: button,
        count: clampedInt(payload["clickCount"], defaultValue: 1, range: 1...3))
    case "desktop.key":
      guard let key = string(payload["key"])?.lowercased(), let code = keyCode(for: key) else {
        throw DesktopAutomationError("Unsupported key.")
      }
      let app = AXUIElementCreateApplication(pid)
      guard let focus = elementAttribute(kAXFocusedUIElementAttribute as CFString, from: app), !isSecureTextElement(focus) else {
        throw DesktopAutomationError("No non-secure focused control in the target app.", code: "input_target_required")
      }
      let modifiers = (payload["modifiers"] as? [String]) ?? []
      guard modifiers.allSatisfy({ ["command", "option", "control", "shift", "fn"].contains($0) }) else {
        throw DesktopAutomationError("Unsupported modifier.")
      }
      try sendKey(code, flags: eventFlags(modifiers), pid: pid, foreground: foreground,
        count: clampedInt(payload["repeat"], defaultValue: 1, range: 1...20))
    case "desktop.scroll":
      let point = try inputPoint(payload, observation: observation)
      guard let event = CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .privateState), units: .pixel,
        wheelCount: 2, wheel1: clampedInt32(double(payload["deltaY"]) ?? -400),
        wheel2: clampedInt32(double(payload["deltaX"]) ?? 0), wheel3: 0) else { throw DesktopAutomationError("Could not create scroll event.") }
      event.location = point
      post(event, pid: pid, foreground: foreground)
    case "desktop.drag":
      let start = try inputPoint(payload, observation: observation)
      var endPayload = payload
      endPayload["x"] = payload["endX"]; endPayload["y"] = payload["endY"]
      endPayload.removeValue(forKey: "ref")
      let end = try inputPoint(endPayload, observation: observation)
      try await sendDrag(start, end: end, pid: pid, foreground: foreground, session: session, payload: payload)
    default: throw DesktopAutomationError("Unknown action: \(command)")
    }
    return ["method": foreground ? "foreground_input" : "targeted_process_input", "foregroundUsed": foreground]
  }

  func inputPoint(_ payload: [String: Any], observation: DesktopObservation) throws -> CGPoint {
    if string(payload["ref"]) != nil {
      let target = try element(payload, observation: observation)
      guard let bounds = frame(of: target) else { throw DesktopAutomationError("Element has no clickable bounds.", code: "target_unavailable") }
      let point = CGPoint(x: bounds.midX, y: bounds.midY)
      guard observation.windowFrame.contains(point) else {
        throw DesktopAutomationError("Element is outside the observed window.", code: "target_outside_window")
      }
      return point
    }
    guard let x = double(payload["x"]), let y = double(payload["y"]),
      string(payload["screenshotId"]) == observation.screenshotID,
      observation.screenshotID != nil, let size = observation.screenshotSize else {
      throw DesktopAutomationError("Coordinates require screenshotId from this task's latest window screenshot.", code: "screenshot_required")
    }
    return try DesktopGeometry.mapPixel(CGPoint(x: x, y: y), image: size, window: observation.windowFrame)
  }

  func editText(_ payload: [String: Any], observation: DesktopObservation, replace: Bool) throws -> [String: Any] {
    let target = try element(payload, observation: observation)
    guard !isSecureTextElement(target), let text = string(payload["text"]) else {
      throw DesktopAutomationError("A text value and non-secure editable ref are required.", code: "secure_or_invalid_field")
    }
    var settable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(target, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue,
      let current = stringAttribute(kAXValueAttribute as CFString, from: target) else {
      throw DesktopAutomationError("This control does not support verified value editing. Use a targeted key operation.", code: "editing_unsupported")
    }
    let range: NSRange
    if replace { range = NSRange(location: 0, length: (current as NSString).length) }
    else {
      guard let value = attributeValue(kAXSelectedTextRangeAttribute as CFString, from: target),
        CFGetTypeID(value) == AXValueGetTypeID() else {
        throw DesktopAutomationError("Cannot read the insertion point. Select text or use set_value.", code: "selection_unavailable")
      }
      var selected = CFRange()
      guard AXValueGetValue(value as! AXValue, .cfRange, &selected) else { throw DesktopAutomationError("Cannot read selection.") }
      range = NSRange(location: selected.location, length: selected.length)
    }
    let next = try DesktopGeometry.replacingSelection(in: current, range: range, with: text)
    guard AXUIElementSetAttributeValue(target, kAXValueAttribute as CFString, next as CFString) == .success else {
      throw DesktopAutomationError("The field rejected the edit.", code: "editing_failed")
    }
    var caret = CFRange(location: range.location + (text as NSString).length, length: 0)
    if let value = AXValueCreate(.cfRange, &caret) { AXUIElementSetAttributeValue(target, kAXSelectedTextRangeAttribute as CFString, value) }
    return ["method": "accessibility_value", "characterCount": text.count, "expectedValue": next,
      "verificationRef": string(payload["ref"]) ?? ""]
  }

  func selectText(_ payload: [String: Any], observation: DesktopObservation) throws -> [String: Any] {
    let target = try element(payload, observation: observation)
    guard !isSecureTextElement(target), let text = string(payload["text"]), !text.isEmpty,
      let content = stringAttribute(kAXValueAttribute as CFString, from: target) else {
      throw DesktopAutomationError("A non-secure text ref and nonempty selection text are required.")
    }
    let value = content as NSString
    let range = value.range(of: text)
    guard range.location != NSNotFound else { throw DesktopAutomationError("Text not found.", code: "text_not_found") }
    let tail = range.location + range.length
    guard tail >= value.length || value.range(of: text, range: NSRange(location: tail, length: value.length - tail)).location == NSNotFound else {
      throw DesktopAutomationError("Text appears more than once; provide a longer unique span.", code: "ambiguous_selection")
    }
    var selection = CFRange(location: range.location, length: range.length)
    if string(payload["selectionType"]) == "cursor_before" { selection.length = 0 }
    if string(payload["selectionType"]) == "cursor_after" { selection.location += selection.length; selection.length = 0 }
    guard let raw = AXValueCreate(.cfRange, &selection),
      AXUIElementSetAttributeValue(target, kAXSelectedTextRangeAttribute as CFString, raw) == .success else {
      throw DesktopAutomationError("The field does not support selection.", code: "selection_unsupported")
    }
    return ["method": "accessibility_selection", "selectionLocation": selection.location, "selectionLength": selection.length]
  }

  func requireBackgroundWindow(_ observation: DesktopObservation) throws {
    let app = AXUIElementCreateApplication(observation.application.processIdentifier)
    guard let focused = elementAttribute(kAXFocusedWindowAttribute as CFString, from: app), CFEqual(focused, observation.window) else {
      throw DesktopAutomationError("Background input cannot target this app's other window. Use accessibility refs or explicitly allow foreground control.", code: "background_window_unavailable")
    }
  }

  func activateTarget(_ observation: DesktopObservation) async throws {
    let app = observation.application
    if app.isHidden { app.unhide() }
    guard app.activate(options: [.activateAllWindows]),
      AXUIElementPerformAction(observation.window, kAXRaiseAction as CFString) == .success else {
      throw DesktopAutomationError("Could not activate the selected window.", code: "activation_failed")
    }
    try await Task.sleep(for: .milliseconds(80))
    guard let liveSession = sessions.values.first(where: { $0.observation === observation }), !liveSession.cancelled else {
      throw DesktopAutomationError("Task stopped during activation.", code: "cancelled")
    }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
      let focused = elementAttribute(kAXFocusedWindowAttribute as CFString, from: root), CFEqual(focused, observation.window) else {
      throw DesktopAutomationError("Window activation is not confirmed. Observe and retry.", code: "focus_unconfirmed")
    }
  }

  func yieldToHuman(_ observation: DesktopObservation, global: Bool) throws {
    let sameApp = NSWorkspace.shared.frontmostApplication?.processIdentifier == observation.application.processIdentifier
    if sameApp || global {
      let recent = [CGEventType.keyDown, .leftMouseDown, .rightMouseDown, .mouseMoved, .scrollWheel]
        .map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }.min() ?? 100
      if recent < 0.8 { throw DesktopAutomationError("You are using this app. Agent control paused; retry when idle.", code: "user_active") }
    }
  }

  func openApplication(_ payload: [String: Any], session: DesktopSession) async throws -> [String: Any] {
    guard payload["bundleId"] != nil || payload["appName"] != nil else { throw DesktopAutomationError("Specify an installed app.") }
    if let app = findRunningApplication(payload) { return ["launched": false, "application": applicationInfo(app)] }
    guard let url = applicationURL(payload) else { throw DesktopAutomationError("Application not found.") }
    let config = NSWorkspace.OpenConfiguration(); config.activates = false
    let app: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
      NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
        if let app { continuation.resume(returning: app) }
        else { continuation.resume(throwing: error ?? DesktopAutomationError("Could not open app.")) }
      }
    }
    try checkSession(session, payload)
    return ["launched": true, "application": applicationInfo(app), "hint": "List windows, then observe the intended window."]
  }
}
