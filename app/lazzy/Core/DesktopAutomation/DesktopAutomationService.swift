import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
final class DesktopAutomationService {
  private var elementRegistry: [String: AXUIElement] = [:]
  private var snapshotGeneration = 0

  func execute(command: String, payload: [String: Any]) async throws -> Any {
    switch command {
    case "desktop.status":
      return status()
    case "desktop.list_apps":
      return listApplications()
    case "desktop.list_windows":
      return try listWindows(payload)
    case "desktop.activate_app":
      return try activateApplication(payload)
    case "desktop.open_app":
      return try await openApplication(payload)
    case "desktop.snapshot":
      return try snapshot(payload)
    case "desktop.screenshot":
      return try await screenshot(payload)
    case "desktop.click":
      return try click(payload)
    case "desktop.type":
      return try typeText(payload)
    case "desktop.key":
      return try pressKey(payload)
    case "desktop.scroll":
      return try scroll(payload)
    default:
      throw DesktopAutomationError("Unknown macOS command: \(command)")
    }
  }

  private func status() -> [String: Any] {
    let frontmost = NSWorkspace.shared.frontmostApplication
    return [
      "accessibilityGranted": AXIsProcessTrusted(),
      "screenRecordingGranted": CGPreflightScreenCaptureAccess(),
      "frontmostApplication": frontmost.map(applicationInfo) ?? NSNull(),
      "capabilities": [
        "accessibilitySnapshot",
        "applicationActivation",
        "mouseInput",
        "keyboardInput",
        "scrollInput",
        "screenCapture",
      ],
      "permissionHelp": [
        "accessibility": "Detach menu > Grant Accessibility Permission, or System Settings > Privacy & Security > Accessibility.",
        "screenRecording": "Detach menu > Grant Screen Recording Permission, or System Settings > Privacy & Security > Screen & System Audio Recording.",
      ],
    ]
  }

  private func listApplications() -> [String: Any] {
    let applications = NSWorkspace.shared.runningApplications
      .filter { !$0.isTerminated && $0.activationPolicy != .prohibited && $0.localizedName != nil }
      .sorted {
        if $0.isActive != $1.isActive { return $0.isActive }
        return ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending
      }
      .map(applicationInfo)

    return ["applications": applications]
  }

  private func listWindows(_ payload: [String: Any]) throws -> [String: Any] {
    try requireAccessibility()
    let application = try resolveRunningApplication(payload)
    let appElement = AXUIElementCreateApplication(application.processIdentifier)
    AXUIElementSetMessagingTimeout(appElement, 2)
    let windows = elementsAttribute(kAXWindowsAttribute as CFString, from: appElement)

    return [
      "application": applicationInfo(application),
      "windows": windows.enumerated().map { index, element in
        var result = elementSummary(element)
        result["index"] = index
        return result
      },
    ]
  }

  private func activateApplication(_ payload: [String: Any]) throws -> [String: Any] {
    let application = try resolveRunningApplication(payload)
    if application.isHidden { application.unhide() }
    let activated = application.activate(options: [.activateAllWindows])
    guard activated else {
      throw DesktopAutomationError("macOS could not activate \(application.localizedName ?? "the requested app").")
    }
    return ["activated": true, "application": applicationInfo(application)]
  }

  private func openApplication(_ payload: [String: Any]) async throws -> [String: Any] {
    if let running = findRunningApplication(payload) {
      if running.isHidden { running.unhide() }
      _ = running.activate(options: [.activateAllWindows])
      return ["launched": false, "application": applicationInfo(running)]
    }

    guard let url = applicationURL(payload) else {
      throw DesktopAutomationError("Application not found. Provide an installed appName or bundleId.")
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    let application = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<NSRunningApplication, Error>) in
      NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
        if let application {
          continuation.resume(returning: application)
        } else {
          continuation.resume(
            throwing: DesktopAutomationError(error?.localizedDescription ?? "macOS could not open the application."))
        }
      }
    }

    return ["launched": true, "application": applicationInfo(application)]
  }

  private func snapshot(_ payload: [String: Any]) throws -> [String: Any] {
    try requireAccessibility()
    let application = try resolveRunningApplication(payload)
    let maxDepth = clampedInt(payload["maxDepth"], defaultValue: 6, range: 1...12)
    let maxElements = clampedInt(payload["maxElements"], defaultValue: 350, range: 1...1000)
    let appElement = AXUIElementCreateApplication(application.processIdentifier)
    AXUIElementSetMessagingTimeout(appElement, 2)

    snapshotGeneration += 1
    elementRegistry.removeAll(keepingCapacity: true)
    var nodes: [[String: Any]] = []
    appendSnapshotNode(
      appElement,
      parentRef: nil,
      depth: 0,
      maxDepth: maxDepth,
      maxElements: maxElements,
      nodes: &nodes
    )

    return [
      "application": applicationInfo(application),
      "generation": snapshotGeneration,
      "elementCount": nodes.count,
      "truncated": nodes.count >= maxElements,
      "elements": nodes,
      "refNote": "Element refs are valid until the next detach_macos_snapshot call.",
    ]
  }

  private func appendSnapshotNode(
    _ element: AXUIElement,
    parentRef: String?,
    depth: Int,
    maxDepth: Int,
    maxElements: Int,
    nodes: inout [[String: Any]]
  ) {
    guard nodes.count < maxElements else { return }
    let ref = "ax\(snapshotGeneration)-\(nodes.count + 1)"
    elementRegistry[ref] = element

    var summary = elementSummary(element)
    summary["ref"] = ref
    summary["depth"] = depth
    if let parentRef { summary["parentRef"] = parentRef }
    nodes.append(summary)

    guard depth < maxDepth else { return }
    for child in elementsAttribute(kAXChildrenAttribute as CFString, from: element) {
      guard nodes.count < maxElements else { break }
      appendSnapshotNode(
        child,
        parentRef: ref,
        depth: depth + 1,
        maxDepth: maxDepth,
        maxElements: maxElements,
        nodes: &nodes
      )
    }
  }

  private func screenshot(_ payload: [String: Any]) async throws -> [String: Any] {
    guard CGPreflightScreenCaptureAccess() else {
      throw DesktopAutomationError(
        "Screen Recording permission is required. Use Detach menu > Grant Screen Recording Permission, then relaunch Detach if macOS asks."
      )
    }

    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    let requestedDisplayId = uint32(payload["displayId"])
    let mainDisplayId = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    let display = content.displays.first(where: { requestedDisplayId != nil && $0.displayID == requestedDisplayId })
      ?? content.displays.first(where: { mainDisplayId != nil && $0.displayID == mainDisplayId })
      ?? content.displays.first

    guard let display else {
      throw DesktopAutomationError("No capturable display is available.")
    }

    let maxWidth = clampedInt(payload["maxWidth"], defaultValue: 1600, range: 320...3840)
    let scale = min(1, Double(maxWidth) / Double(max(display.width, 1)))
    let width = max(1, Int((Double(display.width) * scale).rounded()))
    let height = max(1, Int((Double(display.height) * scale).rounded()))
    let filter = SCContentFilter(display: display, excludingWindows: [])
    let configuration = SCStreamConfiguration()
    configuration.width = width
    configuration.height = height
    configuration.showsCursor = bool(payload["showsCursor"]) ?? false

    let image = try await SCScreenshotManager.captureImage(
      contentFilter: filter,
      configuration: configuration
    )
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else {
      throw DesktopAutomationError("Could not encode the desktop screenshot.")
    }

    return [
      "displayId": display.displayID,
      "width": image.width,
      "height": image.height,
      "mimeType": "image/png",
      "imageBase64": data.base64EncodedString(),
    ]
  }

  private func click(_ payload: [String: Any]) throws -> [String: Any] {
    try requireAccessibility()
    let buttonName = string(payload["button"])?.lowercased() ?? "left"
    guard buttonName == "left" || buttonName == "right" else {
      throw DesktopAutomationError("button must be 'left' or 'right'.")
    }
    let clickCount = clampedInt(payload["clickCount"], defaultValue: 1, range: 1...3)

    if let ref = string(payload["ref"]) {
      let element = try element(for: ref)
      if buttonName == "left", clickCount == 1,
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
      {
        return ["clicked": true, "method": "accessibility", "ref": ref]
      }

      guard let frame = frame(of: element) else {
        throw DesktopAutomationError("The element \(ref) has no clickable frame.")
      }
      try postMouseClick(
        at: CGPoint(x: frame.midX, y: frame.midY),
        buttonName: buttonName,
        clickCount: clickCount
      )
      return ["clicked": true, "method": "coordinates", "ref": ref, "x": frame.midX, "y": frame.midY]
    }

    guard let x = double(payload["x"]), let y = double(payload["y"]) else {
      throw DesktopAutomationError("Provide a recent element ref or both x and y screen coordinates.")
    }
    try postMouseClick(at: CGPoint(x: x, y: y), buttonName: buttonName, clickCount: clickCount)
    return ["clicked": true, "method": "coordinates", "x": x, "y": y]
  }

  private func typeText(_ payload: [String: Any]) throws -> [String: Any] {
    try requireAccessibility()
    guard let text = string(payload["text"]) else {
      throw DesktopAutomationError("text is required.")
    }
    let replace = bool(payload["replace"]) ?? false
    let target: AXUIElement
    if let ref = string(payload["ref"]) {
      target = try element(for: ref)
      _ = AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    } else {
      target = try focusedElement()
    }

    guard !isSecureTextElement(target) else {
      throw DesktopAutomationError("Detach refuses to type into secure text fields.")
    }

    var settable = DarwinBoolean(false)
    if AXUIElementIsAttributeSettable(target, kAXValueAttribute as CFString, &settable) == .success,
      settable.boolValue
    {
      let existing = stringAttribute(kAXValueAttribute as CFString, from: target) ?? ""
      let nextValue = replace ? text : existing + text
      let result = AXUIElementSetAttributeValue(target, kAXValueAttribute as CFString, nextValue as CFString)
      if result == .success {
        return ["typed": true, "method": "accessibility", "characterCount": text.count]
      }
    }

    if replace { try postKey(code: 0, flags: .maskCommand, repeatCount: 1) }
    try postUnicodeText(text)
    return ["typed": true, "method": "keyboard", "characterCount": text.count]
  }

  private func pressKey(_ payload: [String: Any]) throws -> [String: Any] {
    try requireAccessibility()
    guard let key = string(payload["key"])?.lowercased(), let code = keyCode(for: key) else {
      throw DesktopAutomationError("Unsupported key. Use a letter, digit, or a named navigation key.")
    }
    if isPrintableKey(key), let focused = try? focusedElement(), isSecureTextElement(focused) {
      throw DesktopAutomationError("Detach refuses to type into secure text fields.")
    }
    let modifiers = (payload["modifiers"] as? [Any])?.compactMap(string) ?? []
    let flags = eventFlags(modifiers)
    let repeatCount = clampedInt(payload["repeat"], defaultValue: 1, range: 1...20)
    try postKey(code: code, flags: flags, repeatCount: repeatCount)
    return ["pressed": true, "key": key, "modifiers": modifiers, "repeat": repeatCount]
  }

  private func scroll(_ payload: [String: Any]) throws -> [String: Any] {
    try requireAccessibility()
    let deltaX = clampedInt32(double(payload["deltaX"]) ?? 0)
    let deltaY = clampedInt32(double(payload["deltaY"]) ?? -600)
    guard let event = CGEvent(
      scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState),
      units: .pixel,
      wheelCount: 2,
      wheel1: deltaY,
      wheel2: deltaX,
      wheel3: 0
    ) else {
      throw DesktopAutomationError("Could not create a scroll event.")
    }
    if let x = double(payload["x"]), let y = double(payload["y"]) {
      event.location = CGPoint(x: x, y: y)
    }
    event.post(tap: .cghidEventTap)
    return ["scrolled": true, "deltaX": deltaX, "deltaY": deltaY]
  }

  private func requireAccessibility() throws {
    guard AXIsProcessTrusted() else {
      throw DesktopAutomationError(
        "Accessibility permission is required. Use Detach menu > Grant Accessibility Permission, then retry."
      )
    }
  }

  private func resolveRunningApplication(_ payload: [String: Any]) throws -> NSRunningApplication {
    if let application = findRunningApplication(payload) { return application }
    let target = string(payload["bundleId"]) ?? string(payload["appName"]) ?? "the requested application"
    throw DesktopAutomationError("\(target) is not running. Use detach_macos_open_app first.")
  }

  private func findRunningApplication(_ payload: [String: Any]) -> NSRunningApplication? {
    let applications = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
    if let pid = int(payload["pid"]) {
      return applications.first(where: { $0.processIdentifier == pid_t(pid) })
    }
    if let bundleId = string(payload["bundleId"])?.lowercased() {
      return applications.first(where: { $0.bundleIdentifier?.lowercased() == bundleId })
    }
    if let appName = string(payload["appName"])?.lowercased() {
      return applications.first(where: {
        $0.localizedName?.lowercased() == appName
          || $0.bundleURL?.deletingPathExtension().lastPathComponent.lowercased() == appName
      })
    }
    return NSWorkspace.shared.frontmostApplication
  }

  private func applicationURL(_ payload: [String: Any]) -> URL? {
    if let bundleId = string(payload["bundleId"]),
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
    {
      return url
    }
    guard let name = string(payload["appName"]) else { return nil }
    let normalized = name.hasSuffix(".app") ? name : "\(name).app"
    let candidates = [
      URL(fileURLWithPath: "/Applications").appendingPathComponent(normalized),
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").appendingPathComponent(normalized),
      URL(fileURLWithPath: "/System/Applications").appendingPathComponent(normalized),
      URL(fileURLWithPath: "/System/Applications/Utilities").appendingPathComponent(normalized),
    ]
    return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
  }

  private func applicationInfo(_ application: NSRunningApplication) -> [String: Any] {
    [
      "pid": application.processIdentifier,
      "name": application.localizedName ?? "Unknown",
      "bundleId": application.bundleIdentifier ?? NSNull(),
      "active": application.isActive,
      "hidden": application.isHidden,
    ]
  }

  private func elementSummary(_ element: AXUIElement) -> [String: Any] {
    let role = stringAttribute(kAXRoleAttribute as CFString, from: element) ?? "AXUnknown"
    let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: element)
    let secure = subrole == (kAXSecureTextFieldSubrole as String)
    var result: [String: Any] = ["role": role]

    if let subrole { result["subrole"] = subrole }
    addStringAttribute(kAXTitleAttribute as CFString, key: "title", element: element, result: &result)
    addStringAttribute(kAXDescriptionAttribute as CFString, key: "description", element: element, result: &result)
    addStringAttribute(kAXIdentifierAttribute as CFString, key: "identifier", element: element, result: &result)
    if !secure {
      addStringAttribute(kAXValueAttribute as CFString, key: "value", element: element, maxLength: 500, result: &result)
    } else {
      result["secure"] = true
    }
    if let enabled = boolAttribute(kAXEnabledAttribute as CFString, from: element) { result["enabled"] = enabled }
    if let focused = boolAttribute(kAXFocusedAttribute as CFString, from: element) { result["focused"] = focused }
    if let frame = frame(of: element) {
      result["frame"] = ["x": frame.origin.x, "y": frame.origin.y, "width": frame.width, "height": frame.height]
    }

    var actionNames: CFArray?
    if AXUIElementCopyActionNames(element, &actionNames) == .success,
      let actions = actionNames as? [String], !actions.isEmpty
    {
      result["actions"] = actions
    }
    return result
  }

  private func addStringAttribute(
    _ attribute: CFString,
    key: String,
    element: AXUIElement,
    maxLength: Int = 240,
    result: inout [String: Any]
  ) {
    guard let value = stringAttribute(attribute, from: element), !value.isEmpty else { return }
    result[key] = value.count <= maxLength ? value : String(value.prefix(maxLength)) + "…"
  }

  private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
    guard let value = attributeValue(attribute, from: element) else { return nil }
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number.stringValue }
    return nil
  }

  private func boolAttribute(_ attribute: CFString, from element: AXUIElement) -> Bool? {
    guard let value = attributeValue(attribute, from: element) else { return nil }
    if let bool = value as? Bool { return bool }
    return (value as? NSNumber)?.boolValue
  }

  private func elementsAttribute(_ attribute: CFString, from element: AXUIElement) -> [AXUIElement] {
    guard let value = attributeValue(attribute, from: element), CFGetTypeID(value) == CFArrayGetTypeID() else {
      return []
    }
    return (value as? [AXUIElement]) ?? []
  }

  private func elementAttribute(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
    guard let value = attributeValue(attribute, from: element), CFGetTypeID(value) == AXUIElementGetTypeID() else {
      return nil
    }
    return (value as! AXUIElement)
  }

  private func attributeValue(_ attribute: CFString, from element: AXUIElement) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
    return value
  }

  private func frame(of element: AXUIElement) -> CGRect? {
    guard let positionValue = attributeValue(kAXPositionAttribute as CFString, from: element),
      let sizeValue = attributeValue(kAXSizeAttribute as CFString, from: element),
      CFGetTypeID(positionValue) == AXValueGetTypeID(),
      CFGetTypeID(sizeValue) == AXValueGetTypeID()
    else { return nil }

    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
      AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    else { return nil }
    return CGRect(origin: position, size: size)
  }

  private func element(for ref: String) throws -> AXUIElement {
    guard let element = elementRegistry[ref] else {
      throw DesktopAutomationError("Unknown or expired element ref '\(ref)'. Call detach_macos_snapshot again.")
    }
    return element
  }

  private func focusedElement() throws -> AXUIElement {
    guard let application = NSWorkspace.shared.frontmostApplication else {
      throw DesktopAutomationError("No frontmost application is available.")
    }
    let appElement = AXUIElementCreateApplication(application.processIdentifier)
    guard let element = elementAttribute(kAXFocusedUIElementAttribute as CFString, from: appElement) else {
      throw DesktopAutomationError("The frontmost application has no focused editable element.")
    }
    return element
  }

  private func isSecureTextElement(_ element: AXUIElement) -> Bool {
    stringAttribute(kAXSubroleAttribute as CFString, from: element) == (kAXSecureTextFieldSubrole as String)
  }

  private func postMouseClick(at point: CGPoint, buttonName: String, clickCount: Int) throws {
    let source = CGEventSource(stateID: .hidSystemState)
    let button: CGMouseButton = buttonName == "right" ? .right : .left
    let downType: CGEventType = buttonName == "right" ? .rightMouseDown : .leftMouseDown
    let upType: CGEventType = buttonName == "right" ? .rightMouseUp : .leftMouseUp

    for count in 1...clickCount {
      guard let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: point, mouseButton: button),
        let up = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: point, mouseButton: button)
      else { throw DesktopAutomationError("Could not create a mouse event.") }
      down.setIntegerValueField(.mouseEventClickState, value: Int64(count))
      up.setIntegerValueField(.mouseEventClickState, value: Int64(count))
      down.post(tap: .cghidEventTap)
      up.post(tap: .cghidEventTap)
    }
  }

  private func postUnicodeText(_ text: String) throws {
    let source = CGEventSource(stateID: .hidSystemState)
    let characters = Array(text.utf16)
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
    else { throw DesktopAutomationError("Could not create a keyboard event.") }

    characters.withUnsafeBufferPointer { buffer in
      down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
      up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
    }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
  }

  private func postKey(code: CGKeyCode, flags: CGEventFlags, repeatCount: Int) throws {
    let source = CGEventSource(stateID: .hidSystemState)
    for _ in 0..<repeatCount {
      guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
      else { throw DesktopAutomationError("Could not create a keyboard event.") }
      down.flags = flags
      up.flags = flags
      down.post(tap: .cghidEventTap)
      up.post(tap: .cghidEventTap)
    }
  }

  private func eventFlags(_ modifiers: [String]) -> CGEventFlags {
    modifiers.reduce(into: CGEventFlags()) { flags, modifier in
      switch modifier.lowercased() {
      case "command": flags.insert(.maskCommand)
      case "option": flags.insert(.maskAlternate)
      case "control": flags.insert(.maskControl)
      case "shift": flags.insert(.maskShift)
      case "fn": flags.insert(.maskSecondaryFn)
      default: break
      }
    }
  }

  private func keyCode(for key: String) -> CGKeyCode? {
    let codes: [String: CGKeyCode] = [
      "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8,
      "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
      "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
      "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33,
      "i": 34, "p": 35, "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39,
      "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
      "tab": 48, "space": 49, "`": 50, "delete": 51, "backspace": 51, "escape": 53,
      "esc": 53, "forward_delete": 117, "home": 115, "end": 119, "page_up": 116,
      "page_down": 121, "arrow_left": 123, "left": 123, "arrow_right": 124, "right": 124,
      "arrow_down": 125, "down": 125, "arrow_up": 126, "up": 126,
    ]
    return codes[key]
  }

  private func isPrintableKey(_ key: String) -> Bool {
    key.count == 1 || key == "space"
  }

  private func string(_ value: Any?) -> String? {
    value as? String
  }

  private func bool(_ value: Any?) -> Bool? {
    if let value = value as? Bool { return value }
    return (value as? NSNumber)?.boolValue
  }

  private func int(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    return (value as? NSNumber)?.intValue
  }

  private func uint32(_ value: Any?) -> UInt32? {
    guard let value = int(value), value >= 0, value <= Int(UInt32.max) else { return nil }
    return UInt32(value)
  }

  private func double(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    return (value as? NSNumber)?.doubleValue
  }

  private func clampedInt(_ value: Any?, defaultValue: Int, range: ClosedRange<Int>) -> Int {
    min(max(int(value) ?? defaultValue, range.lowerBound), range.upperBound)
  }

  private func clampedInt32(_ value: Double) -> Int32 {
    Int32(min(max(value.rounded(), Double(Int32.min)), Double(Int32.max)))
  }
}

private struct DesktopAutomationError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}
