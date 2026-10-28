import AppKit
import ApplicationServices

extension DesktopAutomationService {
  func requireAccessibility() throws {
    guard AXIsProcessTrusted() else {
      NativePermissionRequests.requestAccessibility()
      throw DesktopAutomationError(
        "Accessibility permission is required. Use Detach menu > Grant Accessibility Permission, then retry."
      )
    }
  }

  func resolveRunningApplication(_ payload: [String: Any]) throws -> NSRunningApplication {
    if let application = findRunningApplication(payload) { return application }
    let target = string(payload["bundleId"]) ?? string(payload["appName"]) ?? "the requested application"
    throw DesktopAutomationError("\(target) is not running. Use detach_macos_open_app first.")
  }

  func findRunningApplication(_ payload: [String: Any]) -> NSRunningApplication? {
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

  func applicationURL(_ payload: [String: Any]) -> URL? {
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

  func applicationInfo(_ application: NSRunningApplication) -> [String: Any] {
    [
      "pid": application.processIdentifier,
      "name": application.localizedName ?? "Unknown",
      "bundleId": application.bundleIdentifier ?? NSNull(),
      "active": application.isActive,
      "hidden": application.isHidden,
    ]
  }

  func elementSummary(_ element: AXUIElement) -> [String: Any] {
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

  func addStringAttribute(
    _ attribute: CFString,
    key: String,
    element: AXUIElement,
    maxLength: Int = 240,
    result: inout [String: Any]
  ) {
    guard let value = stringAttribute(attribute, from: element), !value.isEmpty else { return }
    result[key] = value.count <= maxLength ? value : String(value.prefix(maxLength)) + "…"
  }

  func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
    guard let value = attributeValue(attribute, from: element) else { return nil }
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number.stringValue }
    return nil
  }

  func boolAttribute(_ attribute: CFString, from element: AXUIElement) -> Bool? {
    guard let value = attributeValue(attribute, from: element) else { return nil }
    if let bool = value as? Bool { return bool }
    return (value as? NSNumber)?.boolValue
  }

  func elementsAttribute(_ attribute: CFString, from element: AXUIElement) -> [AXUIElement] {
    guard let value = attributeValue(attribute, from: element), CFGetTypeID(value) == CFArrayGetTypeID() else {
      return []
    }
    return (value as? [AXUIElement]) ?? []
  }

  func elementAttribute(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
    guard let value = attributeValue(attribute, from: element), CFGetTypeID(value) == AXUIElementGetTypeID() else {
      return nil
    }
    return (value as! AXUIElement)
  }

  func attributeValue(_ attribute: CFString, from element: AXUIElement) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
    return value
  }

  func frame(of element: AXUIElement) -> CGRect? {
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

}
