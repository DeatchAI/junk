import AppKit
import ApplicationServices

@MainActor final class DesktopSession {
  let id: String
  var observation: DesktopObservation?
  var previousNodes: [[String: Any]] = []
  var busy = false
  var cancelled = false
  var lastUsed = Date()
  init(id: String) { self.id = id }
}

@MainActor final class DesktopObservation {
  let id = UUID().uuidString
  let application: NSRunningApplication
  let window: AXUIElement
  let windowID: CGWindowID?
  let windowFrame: CGRect
  let createdAt = Date()
  var elements: [String: AXUIElement] = [:]
  var nodes: [[String: Any]] = []
  var screenshotSize: CGSize?
  var screenshotID: String?
  var ocrRegions: [[String: Any]] = []
  var traversalTruncated = false

  init(application: NSRunningApplication, window: AXUIElement, windowID: CGWindowID?, frame: CGRect) {
    self.application = application
    self.window = window
    self.windowID = windowID
    self.windowFrame = frame
  }
}

struct DesktopAutomationError: LocalizedError {
  let code: String
  let message: String
  init(_ message: String, code: String = "desktop_error") { self.message = message; self.code = code }
  var errorDescription: String? { "\(code): \(message)" }
}

/// Geometry and UTF-16 selection rules are shared by actions and focused tests.
enum DesktopGeometry {
  static func mapPixel(_ point: CGPoint, image: CGSize, window: CGRect) throws -> CGPoint {
    guard image.width > 0, image.height > 0, point.x.isFinite, point.y.isFinite,
      point.x >= 0, point.y >= 0, point.x < image.width, point.y < image.height
    else { throw DesktopAutomationError("Coordinates are outside the observed image.", code: "invalid_coordinates") }
    return CGPoint(x: window.minX + point.x * window.width / image.width,
      y: window.minY + point.y * window.height / image.height)
  }

  static func replacingSelection(in text: String, range: NSRange, with inserted: String) throws -> String {
    let value = text as NSString
    guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
      range.location <= value.length, range.length <= value.length - range.location
    else { throw DesktopAutomationError("The text selection changed. Inspect the field again.", code: "stale_selection") }
    guard let swiftRange = Range(range, in: text),
      (swiftRange.lowerBound == text.endIndex || text.indices.contains(swiftRange.lowerBound)),
      (swiftRange.upperBound == text.endIndex || text.indices.contains(swiftRange.upperBound)) else {
      throw DesktopAutomationError("Selection splits a Unicode character.", code: "invalid_selection")
    }
    return value.replacingCharacters(in: range, with: inserted)
  }
}
