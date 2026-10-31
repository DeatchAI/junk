import AppKit
import ApplicationServices

enum PollUIError: LocalizedError {
  case unavailable(String)
  case screenLocked
  var errorDescription: String? {
    switch self {
    case .unavailable(let message): return message
    case .screenLocked: return "Unlock this Mac to send native Messages polls."
    }
  }
}

/// Accessibility identifies controls; pointer input uses their current frames, never recorded coordinates.
@MainActor
final class PollAccessibility {
  let app: NSRunningApplication
  let root: AXUIElement
  var canContinue: () -> Bool = { true }
  var trace: (String) -> Void = { _ in }
  private var hasActivated = false
  private var pinnedWindow: AXUIElement?

  static var isScreenLocked: Bool {
    (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true
  }

  init() throws {
    guard !Self.isScreenLocked else { throw PollUIError.screenLocked }
    guard AXIsProcessTrusted() else {
      throw PollUIError.unavailable("Allow the app running this script in System Settings > Privacy & Security > Accessibility.")
    }
    guard let running = NSWorkspace.shared.runningApplications.first(where: {
      ["com.apple.MobileSMS", "com.apple.iChat"].contains($0.bundleIdentifier ?? "")
    }) else { throw PollUIError.unavailable("Open Messages first.") }
    app = running
    root = AXUIElementCreateApplication(running.processIdentifier)
    AXUIElementSetMessagingTimeout(root, 2)
  }

  func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
    return result
  }

  func string(_ element: AXUIElement, _ key: String) -> String {
    value(element, key) as? String ?? ""
  }

  func children(_ element: AXUIElement) -> [AXUIElement] {
    value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
  }

  func isMessageComposer(_ element: AXUIElement) -> Bool {
    string(element, kAXIdentifierAttribute) == "messageBodyField" ||
      [kAXTextAreaRole, kAXTextFieldRole].contains(string(element, kAXRoleAttribute)) &&
      ["Add comment or Send", "iMessage"].contains(string(element, kAXPlaceholderValueAttribute))
  }

  func descendants(_ element: AXUIElement, excluding identifiers: Set<String> = []) -> [AXUIElement] {
    var result: [AXUIElement] = []
    func visit(_ node: AXUIElement, depth: Int) {
      guard depth < 30, result.count < 4_000, !result.contains(where: { CFEqual($0, node) }) else { return }
      if identifiers.contains(string(node, kAXIdentifierAttribute)) { return }
      result.append(node)
      for child in children(node) { visit(child, depth: depth + 1) }
    }
    visit(element, depth: 0)
    return result
  }

  private func element(_ owner: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let raw = value(owner, attribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
    return unsafeBitCast(raw, to: AXUIElement.self)
  }

  private func applicationWindows() -> [AXUIElement] {
    children(root).filter { string($0, kAXRoleAttribute) == kAXWindowRole }
  }

  private func isWindow(_ candidate: AXUIElement, in windows: [AXUIElement]) -> Bool {
    windows.contains { CFEqual($0, candidate) }
  }

  private func focusedWindow(in windows: [AXUIElement]) -> AXUIElement? {
    if let focused = element(root, kAXFocusedWindowAttribute), isWindow(focused, in: windows) {
      return focused
    }
    let flagged = windows.filter { value($0, kAXFocusedAttribute) as? Bool == true }
    return flagged.count == 1 ? flagged[0] : nil
  }

  func window() throws -> AXUIElement {
    let openWindows = applicationWindows()
    guard !openWindows.isEmpty else {
      throw PollUIError.unavailable("Messages has no conversation window ready yet.")
    }
    if let pinnedWindow {
      guard isWindow(pinnedWindow, in: openWindows) else {
        throw PollUIError.unavailable("The verified Messages conversation window was closed.")
      }
      return pinnedWindow
    }
    if let focused = focusedWindow(in: openWindows) { return focused }
    if let main = element(root, kAXMainWindowAttribute), isWindow(main, in: openWindows) { return main }
    let mainWindows = openWindows.filter { value($0, kAXMainAttribute) as? Bool == true }
    if mainWindows.count == 1 { return mainWindows[0] }
    if openWindows.count == 1 { return openWindows[0] }

    // Messages may keep settings and secondary chats open together. Prefer
    // the only window exposing its actual composer while AX focus is changing.
    let composerWindows = openWindows.filter { window in
      descendants(window, excluding: ["TranscriptCollectionView", "ConversationList"]).contains {
        isMessageComposer($0)
      }
    }
    if composerWindows.count == 1 { return composerWindows[0] }
    throw PollUIError.unavailable("Messages has multiple windows and did not expose which conversation is active. Bring the paired chat to the front and retry.")
  }

  func pinWindow(_ window: AXUIElement) throws {
    guard isWindow(window, in: applicationWindows()) else {
      throw PollUIError.unavailable("The Messages conversation changed before it could be verified.")
    }
    pinnedWindow = window
  }

  func unpinWindow() { pinnedWindow = nil }

  func controls() throws -> [AXUIElement] {
    descendants(try window(), excluding: ["TranscriptCollectionView", "ConversationList"])
  }

  func unique(_ nodes: [AXUIElement], description: String,
    matching predicate: (AXUIElement) -> Bool) throws -> AXUIElement {
    let matches = nodes.filter(predicate)
    guard matches.count == 1 else {
      throw PollUIError.unavailable("Expected one \(description); found \(matches.count). No action taken.")
    }
    return matches[0]
  }

  func button(_ description: String, in nodes: [AXUIElement]? = nil) throws -> AXUIElement {
    try unique(nodes ?? controls(), description: "'\(description)' button") {
      self.string($0, kAXRoleAttribute) == kAXButtonRole &&
        self.string($0, kAXDescriptionAttribute) == description
    }
  }

  func press(_ element: AXUIElement) throws {
    try checkpoint()
    guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
      throw PollUIError.unavailable("Messages did not accept the Accessibility press.")
    }
  }

  /// Some SwiftUI controls advertise AXPress but do nothing. Locate the live control's frame instead.
  func click(_ element: AXUIElement) async throws {
    try await activate()
    guard let frame = try frame(element), let windowFrame = try self.frame(window()),
      frame.width > 0, frame.height > 0 else {
      throw PollUIError.unavailable("The named control is not visible inside the Messages window.")
    }
    // AX frames can extend past a clipped control when the window is narrow.
    // Click the visible portion so the same automation works at smaller sizes.
    let visibleFrame = frame.intersection(windowFrame)
    guard !visibleFrame.isNull, !visibleFrame.isEmpty else {
      throw PollUIError.unavailable("The named control is outside the visible Messages window.")
    }
    let point = CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
    let source = CGEventSource(stateID: .privateState)
    guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
      mouseCursorPosition: point, mouseButton: .left),
      let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
        mouseCursorPosition: point, mouseButton: .left) else {
      throw PollUIError.unavailable("Could not click the named Messages control.")
    }
    down.flags = []
    up.flags = []
    down.setIntegerValueField(.mouseEventClickState, value: 1)
    up.setIntegerValueField(.mouseEventClickState, value: 1)
    down.post(tap: .cgSessionEventTap)
    try? await Task.sleep(nanoseconds: 40_000_000)
    up.post(tap: .cgSessionEventTap)
    try checkpoint()
  }

  private func isFocused(_ element: AXUIElement) -> Bool {
    // Messages can expose the text editor through both a wrapper and an inner
    // AX object. AXFocused is authoritative even when those objects differ.
    if value(element, kAXFocusedAttribute) as? Bool == true { return true }
    guard let focused = value(root, kAXFocusedUIElementAttribute),
      CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
    return CFEqual(focused, element)
  }

  func focus(_ element: AXUIElement) async throws {
    try await focus(resolving: { element })
  }

  func focus(resolving field: () throws -> AXUIElement) async throws {
    try await activate()
    let initial = try field()
    AXUIElementSetAttributeValue(initial, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    do {
      try await wait("text field focus", seconds: 0.5) { try self.isFocused(field()) }
      trace("Focus verified through Accessibility")
      return
    } catch { try checkpoint() }
    // Resolving again matters: editing one choice can recreate every field.
    var lastFrame: CGRect?
    try await wait("poll layout to settle", stableFor: 0.25) {
      guard let current = try self.frame(field()) else { return false }
      defer { lastFrame = current }
      return current == lastFrame && current.width > 0 && current.height > 0
    }
    try await click(field())
    do {
      try await wait("text field focus") { try self.isFocused(field()) }
      trace("Focus verified through pointer input")
    } catch {
      let target = try field()
      let focused = value(root, kAXFocusedUIElementAttribute)
      let role = focused.flatMap { raw -> String? in
        guard CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return self.string(unsafeBitCast(raw, to: AXUIElement.self), kAXRoleAttribute)
      } ?? "none"
      trace("Focus failed: target=\(string(target, kAXRoleAttribute)), flagged=\(value(target, kAXFocusedAttribute) as? Bool ?? false), current=\(role)")
      throw error
    }
  }

  private func frame(_ node: AXUIElement) throws -> CGRect? {
    guard let position = value(node, kAXPositionAttribute), let size = value(node, kAXSizeAttribute),
      CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
      AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions) else { return nil }
    return CGRect(origin: point, size: dimensions)
  }

  func wait(_ description: String, seconds: TimeInterval = 4, stableFor: TimeInterval = 0.08,
    retryingTransientErrors: Bool = false, until ready: () throws -> Bool) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    var stableSince: Date?
    repeat {
      try checkpoint()
      let isReady: Bool
      do {
        isReady = try ready()
      } catch {
        try checkpoint()
        guard retryingTransientErrors else { throw error }
        isReady = false
      }
      if isReady {
        if stableSince == nil { stableSince = Date() }
        if Date().timeIntervalSince(stableSince!) >= stableFor { return }
      } else { stableSince = nil }
      try await Task.sleep(nanoseconds: 80_000_000)
    } while Date() < deadline
    throw PollUIError.unavailable("Timed out waiting for \(description). No automatic retry.")
  }

  func checkpoint() throws {
    try Task.checkCancellation()
    guard !Self.isScreenLocked else { throw PollUIError.screenLocked }
    guard canContinue() else { throw PollUIError.unavailable("This decision is no longer pending.") }
    if hasActivated {
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
        throw PollUIError.unavailable("Messages was interrupted. Review the decision on your Mac.")
      }
      if let pinnedWindow, let focused = focusedWindow(in: applicationWindows()), !CFEqual(focused, pinnedWindow) {
        throw PollUIError.unavailable("A different Messages window became active. Bring the verified conversation to the front and retry.")
      }
    }
  }

  func activate() async throws {
    try Task.checkCancellation()
    guard !Self.isScreenLocked else { throw PollUIError.screenLocked }
    guard canContinue() else { throw PollUIError.unavailable("This decision is no longer pending.") }
    if hasActivated { try checkpoint(); return }
    app.activate(options: [])
    try await wait("Messages to become active", stableFor: 0.25) {
      NSWorkspace.shared.frontmostApplication?.processIdentifier == self.app.processIdentifier
    }
    hasActivated = true
  }

  func key(_ code: CGKeyCode, flags: CGEventFlags = []) async throws {
    try checkpoint()
    let source = CGEventSource(stateID: .privateState)
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else {
      throw PollUIError.unavailable("Could not create the keyboard event.")
    }
    down.flags = flags
    up.flags = flags
    down.post(tap: .cgSessionEventTap)
    try? await Task.sleep(nanoseconds: 40_000_000)
    up.post(tap: .cgSessionEventTap)
    try checkpoint()
  }

  /// Real typing commits native field-change notifications that AXValue alone can miss.
  func type(_ text: String, into field: AXUIElement) async throws {
    try await type(text, resolving: { field })
  }

  func type(_ text: String, resolving field: () throws -> AXUIElement) async throws {
    try await focus(resolving: field)
    let selectionExpected = string(try field(), kAXValueAttribute).utf16.count
    try await key(0, flags: .maskCommand)
    try await wait("text selection") {
      let current = try field()
      guard self.isFocused(current), let raw = self.value(current, kAXSelectedTextRangeAttribute),
        CFGetTypeID(raw) == AXValueGetTypeID() else { return false }
      var range = CFRange()
      guard AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cfRange, &range) else { return false }
      return range.location == 0 && range.length == selectionExpected
    }
    if text.isEmpty {
      try await key(51)
      try await wait("cleared field") { try self.string(field(), kAXValueAttribute).isEmpty }
      return
    }
    let source = CGEventSource(stateID: .privateState)
    let utf16 = Array(text.utf16)
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
      throw PollUIError.unavailable("Could not type the poll text.")
    }
    down.flags = []
    up.flags = []
    utf16.withUnsafeBufferPointer { bytes in
      down.keyboardSetUnicodeString(stringLength: bytes.count, unicodeString: bytes.baseAddress)
      up.keyboardSetUnicodeString(stringLength: bytes.count, unicodeString: bytes.baseAddress)
    }
    down.post(tap: .cgSessionEventTap)
    try? await Task.sleep(nanoseconds: 40_000_000)
    up.post(tap: .cgSessionEventTap)
    try checkpoint()
    try await wait("typed field") { try self.string(field(), kAXValueAttribute) == text }
  }

  func sendReturn(to field: AXUIElement) async throws {
    try await activate()
    try await focus(field)
    try await key(36)
  }
}
