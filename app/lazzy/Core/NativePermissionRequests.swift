import ApplicationServices
import CoreGraphics

/// First-use prompts are limited to one attempt per feature in this app session.
@MainActor enum NativePermissionRequests {
  private static var requestedAccessibility = false
  private static var requestedScreenCapture = false

  static func requestAccessibility() {
    guard !requestedAccessibility, !AXIsProcessTrusted() else { return }
    requestedAccessibility = true
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
  }

  static func requestScreenCapture() {
    guard !requestedScreenCapture, !CGPreflightScreenCaptureAccess() else { return }
    requestedScreenCapture = true
    CGRequestScreenCaptureAccess()
  }
}
