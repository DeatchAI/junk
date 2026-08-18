import AppKit
import ApplicationServices
import Combine
import Foundation

/// Detects selected text in any application using Accessibility API
class SelectionDetector: ObservableObject {

  @Published private(set) var selectedText: String = ""
  @Published private(set) var hasAccessibilityPermission = false

  init() {
    checkAccessibilityPermission()
  }

  // MARK: - Permissions

  func checkAccessibilityPermission() {
    hasAccessibilityPermission = AXIsProcessTrusted()
    if !hasAccessibilityPermission {
      print("⚠️ Accessibility permission not granted")
    }
  }

  func requestAccessibilityPermission() {
    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)

    // Check again after a delay (user needs to enable in System Preferences)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
      self?.checkAccessibilityPermission()
    }
  }

  // MARK: - Selection Detection

  /// Get currently selected text from the frontmost application
  func getSelectedText() -> String? {
    guard hasAccessibilityPermission else {
      print("❌ No accessibility permission")
      return nil
    }

    // Get the frontmost application
    guard let frontApp = NSWorkspace.shared.frontmostApplication else {
      return nil
    }

    // Don't try to access our own app via Accessibility API
    if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
      return nil
    }

    let pid = frontApp.processIdentifier
    let appElement = AXUIElementCreateApplication(pid)

    // Get focused element
    var focusedElement: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(
      appElement,
      kAXFocusedUIElementAttribute as CFString,
      &focusedElement
    )

    guard result == .success, let focused = focusedElement else {
      return nil
    }

    // Get selected text from focused element
    var selectedTextValue: CFTypeRef?
    let textResult = AXUIElementCopyAttributeValue(
      focused as! AXUIElement,
      kAXSelectedTextAttribute as CFString,
      &selectedTextValue
    )

    if textResult == .success, let text = selectedTextValue as? String, !text.isEmpty {
      selectedText = text
      print("📋 Selected text detected")
      return text
    }

    return nil
  }

  /// Try to get selected text using clipboard (fallback method)
  func getSelectedTextViaClipboard() -> String? {
    // Save current clipboard
    let pasteboard = NSPasteboard.general
    let previousItems = pasteboard.pasteboardItems?.compactMap { item -> String? in
      item.string(forType: .string)
    }

    // Clear and simulate Cmd+C
    pasteboard.clearContents()

    // Simulate Cmd+C
    let source = CGEventSource(stateID: .hidSystemState)

    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)  // 'c' key
    keyDown?.flags = .maskCommand
    keyDown?.post(tap: .cghidEventTap)

    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
    keyUp?.flags = .maskCommand
    keyUp?.post(tap: .cghidEventTap)

    // Wait a moment for clipboard to update
    Thread.sleep(forTimeInterval: 0.1)

    // Get new clipboard content
    let newText = pasteboard.string(forType: .string)

    // Restore previous clipboard
    pasteboard.clearContents()
    if let previous = previousItems?.first {
      pasteboard.setString(previous, forType: .string)
    }

    if let text = newText, !text.isEmpty {
      selectedText = text
      return text
    }

    return nil
  }
}
