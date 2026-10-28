import AppKit
import ApplicationServices

extension DesktopAutomationService {
  func listWindows(_ payload: [String: Any], session: DesktopSession) throws -> [String: Any] {
    try requireAccessibility()
    let app = try targetApplication(payload, session: session)
    let windows = windowsFor(app)
    return ["application": applicationInfo(app), "windows": windows.map { window in
      var value = elementSummary(window)
      value["windowId"] = windowNumber(window, app: app).map { NSNumber(value: $0) } ?? NSNull()
      return value
    }]
  }

  func targetApplication(_ payload: [String: Any], session: DesktopSession) throws -> NSRunningApplication {
    if payload["pid"] == nil, payload["bundleId"] == nil, payload["appName"] == nil,
      let app = session.observation?.application, !app.isTerminated { return app }
    return try resolveRunningApplication(payload)
  }

  func windowsFor(_ app: NSRunningApplication) -> [AXUIElement] {
    let element = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(element, 0.3)
    return elementsAttribute(kAXWindowsAttribute as CFString, from: element)
  }

  func windowNumber(_ window: AXUIElement, app: NSRunningApplication) -> CGWindowID? {
    guard let bounds = frame(of: window),
      let entries = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else { return nil }
    let title = stringAttribute(kAXTitleAttribute as CFString, from: window)
    let matches = entries.filter { entry in
      guard (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier,
        let raw = entry[kCGWindowBounds as String] as? NSDictionary,
        let rect = CGRect(dictionaryRepresentation: raw)
      else { return false }
      return abs(rect.minX - bounds.minX) < 2 && abs(rect.minY - bounds.minY) < 2
        && abs(rect.width - bounds.width) < 2 && abs(rect.height - bounds.height) < 2
    }
    let titled = matches.filter { ($0[kCGWindowName as String] as? String) == title }
    let unique = titled.count == 1 ? titled : matches
    guard unique.count == 1 else { return nil }
    return (unique[0][kCGWindowNumber as String] as? NSNumber)?.uint32Value
  }

  func resolveWindow(_ payload: [String: Any], app: NSRunningApplication, session: DesktopSession) throws -> AXUIElement {
    let windows = windowsFor(app)
    if let id = uint32(payload["windowId"]) {
      guard let window = windows.first(where: { windowNumber($0, app: app) == id }) else {
        throw DesktopAutomationError("Window no longer belongs to this app. List windows again.", code: "window_not_found")
      }
      return window
    }
    if let old = session.observation, old.application.processIdentifier == app.processIdentifier,
      let window = windows.first(where: { CFEqual($0, old.window) }) { return window }
    if windows.count == 1 { return windows[0] }
    throw DesktopAutomationError("Choose windowId from list_windows; the app has \(windows.count) windows.", code: "window_required")
  }

  func checkedObservation(_ session: DesktopSession, payload: [String: Any]) throws -> DesktopObservation {
    guard let observation = session.observation else {
      throw DesktopAutomationError("Observe a target window first.", code: "observation_required")
    }
    let givenID = string(payload["observationId"])
    let ref = string(payload["ref"])
    guard (givenID == observation.id) || (givenID == nil && ref != nil && observation.elements[ref!] != nil) else {
      throw DesktopAutomationError("Observation belongs to another task or is stale. Observe again.", code: "stale_observation")
    }
    if let pid = int(payload["pid"]), pid != Int(observation.application.processIdentifier) {
      throw DesktopAutomationError("Observation targets another application.", code: "target_mismatch")
    }
    if payload["bundleId"] != nil || payload["appName"] != nil {
      guard findRunningApplication(payload)?.processIdentifier == observation.application.processIdentifier else {
        throw DesktopAutomationError("Observation targets another application.", code: "target_mismatch")
      }
    }
    if let windowID = uint32(payload["windowId"]), windowID != observation.windowID {
      throw DesktopAutomationError("Observation targets another window.", code: "target_mismatch")
    }
    guard Date().timeIntervalSince(observation.createdAt) < 120,
      !observation.application.isTerminated,
      windowsFor(observation.application).contains(where: { CFEqual($0, observation.window) }),
      let currentFrame = frame(of: observation.window), currentFrame == observation.windowFrame
    else { throw DesktopAutomationError("Window moved, resized or closed. Observe again.", code: "stale_window") }
    return observation
  }

  func snapshotFor(_ app: NSRunningApplication, window: AXUIElement, session: DesktopSession,
    maxDepth: Int, maxElements: Int, diff: Bool) throws -> [String: Any] {
    guard let bounds = frame(of: window) else {
      throw DesktopAutomationError("Window has no accessible bounds.", code: "window_unavailable")
    }
    let observation = DesktopObservation(application: app, window: window,
      windowID: windowNumber(window, app: app), frame: bounds)
    let previous = session.observation?.nodes ?? session.previousNodes
    var visited = Set<CFHashCode>()
    appendNode(window, parent: nil, depth: 0, maxDepth: maxDepth, maxElements: maxElements,
      observation: observation, visited: &visited)
    session.previousNodes = previous
    session.observation = observation
    var result: [String: Any] = ["observationId": observation.id, "application": applicationInfo(app),
      "windowId": observation.windowID.map { NSNumber(value: $0) } ?? NSNull(),
      "windowFrame": rectJSON(bounds), "capturedAt": ISO8601DateFormatter().string(from: observation.createdAt),
      "elementCount": observation.nodes.count, "truncated": observation.traversalTruncated || observation.nodes.count >= maxElements,
      "elements": observation.nodes, "refNote": "Refs belong to this task and observation. Use the refreshed observation after every action."]
    if diff, !previous.isEmpty {
      let changes = observation.nodes.enumerated().compactMap { index, node -> [String: Any]? in
        if index < previous.count, nodesEqual([previous[index]], [node]) { return nil }
        return node
      }
      result["changes"] = changes
      result["refMap"] = observation.nodes.enumerated().map { ["index": $0.offset, "ref": $0.element["ref"] ?? "", "identifier": $0.element["identifier"] ?? ""] }
      result["removedCount"] = max(0, previous.count - observation.nodes.count)
      // Keep a complete ref map available only when requested; changes carry fresh refs.
      result["elements"] = changes
      result["isDiff"] = true
    }
    return result
  }

  func appendNode(_ element: AXUIElement, parent: String?, depth: Int, maxDepth: Int, maxElements: Int,
    observation: DesktopObservation, visited: inout Set<CFHashCode>) {
    guard observation.nodes.count < maxElements, Date().timeIntervalSince(observation.createdAt) < 2 else {
      observation.traversalTruncated = true; return
    }
    guard visited.insert(CFHash(element)).inserted else { return }
    let ref = "\(observation.id):\(observation.nodes.count)"
    observation.elements[ref] = element
    var node = elementSummary(element)
    node["ref"] = ref; node["depth"] = depth
    if let parent { node["parentRef"] = parent }
    observation.nodes.append(node)
    guard depth < maxDepth else { return }
    var children = elementsAttribute(kAXChildrenAttribute as CFString, from: element)
    if children.isEmpty { children = elementsAttribute("AXVisibleChildren" as CFString, from: element) }
    if children.isEmpty { children = elementsAttribute("AXContents" as CFString, from: element) }
    for child in children {
      appendNode(child, parent: ref, depth: depth + 1, maxDepth: maxDepth, maxElements: maxElements,
        observation: observation, visited: &visited)
      if observation.nodes.count >= maxElements { break }
    }
  }

  func rectJSON(_ frame: CGRect) -> [String: Any] {
    ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
  }

  func element(_ payload: [String: Any], observation: DesktopObservation) throws -> AXUIElement {
    if let ref = string(payload["ref"]), let value = observation.elements[ref] {
      if CFEqual(value, observation.window) { return value }
      if let window = elementAttribute(kAXWindowAttribute as CFString, from: value), CFEqual(window, observation.window) { return value }
      var ancestor: AXUIElement? = value
      for _ in 0..<64 {
        guard let current = ancestor else { break }
        if CFEqual(current, observation.window) { return value }
        ancestor = elementAttribute(kAXParentAttribute as CFString, from: current)
      }
      throw DesktopAutomationError("Element was detached from the observed window. Observe again.", code: "stale_element")
    }
    throw DesktopAutomationError("A fresh element ref is required.", code: "stale_element")
  }

  func isSecureTextElement(_ element: AXUIElement) -> Bool {
    stringAttribute(kAXSubroleAttribute as CFString, from: element) == (kAXSecureTextFieldSubrole as String)
  }
}
