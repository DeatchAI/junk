import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision

extension DesktopAutomationService {
  func observeCommand(_ command: String, payload: [String: Any], session: DesktopSession) async throws -> [String: Any] {
    try requireAccessibility()
    let app = try targetApplication(payload, session: session)
    let window = try resolveWindow(payload, app: app, session: session)
    let deadline = Date().addingTimeInterval(Double(clampedInt(payload["timeoutMs"], defaultValue: 2000, range: 0...10000)) / 1000)
    var result: [String: Any] = [:]
    repeat {
      try checkSession(session, payload)
      result = try snapshotFor(app, window: window, session: session,
        maxDepth: clampedInt(payload["maxDepth"], defaultValue: 12, range: 1...32),
        maxElements: clampedInt(payload["maxElements"], defaultValue: 500, range: 1...1500),
        diff: bool(payload["diff"]) == true && command != "desktop.wait")
      if command != "desktop.wait" { break }
      if let text = string(payload["text"]), let nodes = session.observation?.nodes,
        nodes.contains(where: { node in ["title", "value", "description"].contains { (node[$0] as? String)?.contains(text) == true } }) {
        result["matched"] = true; break
      }
      if Date() >= deadline { result["matched"] = false; break }
      try await Task.sleep(for: .milliseconds(100))
    } while true
    let includeImage = command == "desktop.screenshot" || (command == "desktop.observe" && bool(payload["includeScreenshot"]) != false)
    if includeImage, let observation = session.observation {
      if !CGPreflightScreenCaptureAccess(), command == "desktop.observe", bool(payload["includeScreenshot"]) == nil {
        result["screenshotUnavailable"] = "Screen Recording permission is missing; accessibility inspection remains available."
      } else {
        let capture = try await captureWindow(observation, maxWidth: clampedInt(payload["maxWidth"], defaultValue: 1600, range: 320...3840),
          ocr: bool(payload["ocr"]) == true)
        try checkSession(session, payload)
        guard session.observation === observation else {
          throw DesktopAutomationError("Observation changed during capture.", code: "stale_observation")
        }
        result.merge(capture) { _, new in new }
      }
    }
    return result
  }

  func captureWindow(_ observation: DesktopObservation, maxWidth: Int, ocr: Bool) async throws -> [String: Any] {
    guard CGPreflightScreenCaptureAccess() else {
      NativePermissionRequests.requestScreenCapture()
      throw DesktopAutomationError("Enable Screen Recording for Detach, then retry.", code: "permission_missing")
    }
    guard let id = observation.windowID else {
      throw DesktopAutomationError("Cannot uniquely map the accessibility window to a capture window.", code: "window_unavailable")
    }
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    guard let window = content.windows.first(where: { $0.windowID == id && $0.owningApplication?.processID == observation.application.processIdentifier }) else {
      throw DesktopAutomationError("The observed window is no longer capturable.", code: "window_unavailable")
    }
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let config = SCStreamConfiguration()
    let nativeScale = NSScreen.screens.first(where: { $0.frame.intersects(window.frame) })?.backingScaleFactor ?? 2
    let scale = min(nativeScale, CGFloat(maxWidth) / max(window.frame.width, 1))
    config.width = max(1, Int((window.frame.width * scale).rounded()))
    config.height = max(1, Int((window.frame.height * scale).rounded()))
    config.showsCursor = false
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    guard frame(of: observation.window) == observation.windowFrame else {
      throw DesktopAutomationError("Window moved or resized during capture. Observe again.", code: "stale_window")
    }
    guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
      throw DesktopAutomationError("Could not encode the window screenshot.")
    }
    let screenshotID = UUID().uuidString
    observation.screenshotID = screenshotID
    observation.screenshotSize = CGSize(width: image.width, height: image.height)
    var result: [String: Any] = ["screenshotId": screenshotID, "width": image.width, "height": image.height,
      "mimeType": "image/png", "imageBase64": png.base64EncodedString(),
      "coordinateMap": ["space": "image_pixels_top_left", "originX": observation.windowFrame.minX,
        "originY": observation.windowFrame.minY, "scaleX": observation.windowFrame.width / CGFloat(image.width),
        "scaleY": observation.windowFrame.height / CGFloat(image.height)]]
    if ocr {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = false
      try VNImageRequestHandler(cgImage: image).perform([request])
      let regions: [[String: Any]] = (request.results ?? []).prefix(200).compactMap { item in
        guard let text = item.topCandidates(1).first else { return nil }
        let bounds = item.boundingBox
        return ["text": String(text.string.prefix(500)), "confidence": text.confidence,
          "frame": ["x": bounds.minX * CGFloat(image.width), "y": (1 - bounds.maxY) * CGFloat(image.height),
            "width": bounds.width * CGFloat(image.width), "height": bounds.height * CGFloat(image.height)]]
      }
      observation.ocrRegions = regions
      result["ocrRegions"] = regions
      result["ocrNote"] = "Local text recognition only; verify the screenshot before coordinate actions."
    }
    return result
  }
}
