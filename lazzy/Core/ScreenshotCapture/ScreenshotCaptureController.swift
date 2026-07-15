import AppKit
import Foundation
import SwiftUI

/// Controller for capturing screenshot regions
/// Shows fullscreen overlay with crosshair cursor for region selection
class ScreenshotCaptureController: NSObject {

  private var overlayWindow: NSWindow?
  private var overlayView: ScreenshotOverlayNSView?

  // Callback with captured image (nil if cancelled)
  var onScreenshotCaptured: ((NSImage?) -> Void)?

  // MARK: - Public API

  /// Start the screenshot capture process
  func startCapture(completion: @escaping (NSImage?) -> Void) {
    self.onScreenshotCaptured = completion
    showOverlay()
  }

  /// Cancel the capture
  func cancelCapture() {
    hideOverlay()
    onScreenshotCaptured?(nil)
  }

  // MARK: - Overlay Window

  private func showOverlay() {
    // Get the main screen bounds
    guard let screen = NSScreen.main else {
      onScreenshotCaptured?(nil)
      return
    }

    let screenFrame = screen.frame

    // Create fullscreen borderless window
    let window = NSWindow(
      contentRect: screenFrame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    window.level = .screenSaver  // Above everything
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = false
    window.ignoresMouseEvents = false
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    // Create the overlay view
    let overlay = ScreenshotOverlayNSView(frame: screenFrame)
    overlay.onRegionSelected = { [weak self] rect in
      self?.captureRegion(rect)
    }
    overlay.onCancelled = { [weak self] in
      self?.cancelCapture()
    }

    window.contentView = overlay
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    // Force set crosshair cursor immediately after window appears
    DispatchQueue.main.async {
      NSCursor.crosshair.set()
    }

    self.overlayWindow = window
    self.overlayView = overlay

    print("📸 Screenshot capture started - crosshair cursor active")
  }

  private func hideOverlay() {
    // Reset cursor back to arrow
    NSCursor.arrow.set()
    overlayWindow?.orderOut(nil)
    overlayWindow = nil
    overlayView = nil
    print("📸 Screenshot capture ended")
  }

  // MARK: - Capture

  private func captureRegion(_ rect: CGRect) {
    hideOverlay()

    // Small delay to let overlay disappear
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      guard let self = self else { return }

      guard let screen = NSScreen.main else {
        self.onScreenshotCaptured?(nil)
        return
      }

      // Minimum size check
      guard rect.width >= 10 && rect.height >= 10 else {
        print("📸 Selection too small, cancelling")
        self.onScreenshotCaptured?(nil)
        return
      }

      // Convert to screen coordinates (flip Y for screencapture)
      let screenHeight = screen.frame.height
      let captureRect = CGRect(
        x: rect.origin.x,
        y: screenHeight - rect.origin.y - rect.height,
        width: rect.width,
        height: rect.height
      )

      // Create temp file for screenshot
      let tempDir = FileManager.default.temporaryDirectory
      let timestamp = ISO8601DateFormatter().string(from: Date())
        .replacingOccurrences(of: ":", with: "-")
      let tempFile = tempDir.appendingPathComponent("screenshot-\(timestamp).png")

      // Use macOS screencapture command with region
      // -x: no sound, -r: don't add drop shadow, -R: capture specific region
      let regionArg =
        "\(Int(captureRect.origin.x)),\(Int(captureRect.origin.y)),\(Int(captureRect.width)),\(Int(captureRect.height))"

      let task = Process()
      task.launchPath = "/usr/sbin/screencapture"
      task.arguments = ["-x", "-R", regionArg, tempFile.path]

      do {
        try task.run()
        task.waitUntilExit()

        if task.terminationStatus == 0 {
          if let image = NSImage(contentsOf: tempFile) {
            print("📸 Screenshot captured: \(Int(rect.width))x\(Int(rect.height))")
            self.onScreenshotCaptured?(image)

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempFile)
          } else {
            print("❌ Failed to load captured screenshot")
            self.onScreenshotCaptured?(nil)
          }
        } else {
          print("❌ screencapture failed with status: \(task.terminationStatus)")
          self.onScreenshotCaptured?(nil)
        }
      } catch {
        print("❌ Failed to run screencapture: \(error)")
        self.onScreenshotCaptured?(nil)
      }
    }
  }
}

// MARK: - NSView for Overlay

/// Custom NSView for handling mouse events and drawing selection rectangle
class ScreenshotOverlayNSView: NSView {

  var onRegionSelected: ((CGRect) -> Void)?
  var onCancelled: (() -> Void)?

  private var selectionStart: NSPoint?
  private var selectionEnd: NSPoint?
  private var isSelecting = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setupView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupView()
  }

  private func setupView() {
    // Make the view accept first responder for key events
    // Use barely-visible background (0.01 alpha) to capture cursor events
    // Pure transparent won't receive cursor updates from macOS
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor

    // Enable cursor rects for this view
    addTrackingArea(
      NSTrackingArea(
        rect: bounds,
        options: [.activeAlways, .mouseMoved, .cursorUpdate, .mouseEnteredAndExited],
        owner: self,
        userInfo: nil
      ))
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    // Remove old tracking areas and add new one for current bounds
    for area in trackingAreas {
      removeTrackingArea(area)
    }
    addTrackingArea(
      NSTrackingArea(
        rect: bounds,
        options: [.activeAlways, .mouseMoved, .cursorUpdate, .mouseEnteredAndExited],
        owner: self,
        userInfo: nil
      ))
  }

  override func mouseEntered(with event: NSEvent) {
    NSCursor.crosshair.set()
  }

  override func cursorUpdate(with event: NSEvent) {
    NSCursor.crosshair.set()
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .crosshair)
  }

  override var acceptsFirstResponder: Bool { true }

  override func keyDown(with event: NSEvent) {
    // ESC to cancel
    if event.keyCode == 53 {
      onCancelled?()
    }
  }

  override func mouseDown(with event: NSEvent) {
    let location = convert(event.locationInWindow, from: nil)
    selectionStart = location
    selectionEnd = location
    isSelecting = true
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    guard isSelecting else { return }
    selectionEnd = convert(event.locationInWindow, from: nil)
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    guard isSelecting, let start = selectionStart, let end = selectionEnd else { return }
    isSelecting = false

    let rect = normalizedRect(from: start, to: end)
    onRegionSelected?(rect)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    // No dark overlay - just draw selection rectangle if selecting
    if isSelecting, let start = selectionStart, let end = selectionEnd {
      let selectionRect = normalizedRect(from: start, to: end)

      // Clear the selection area (make it fully visible)
      NSColor.clear.setFill()
      selectionRect.fill()

      // Draw border around selection
      let borderPath = NSBezierPath(rect: selectionRect)
      borderPath.lineWidth = 2
      NSColor.white.setStroke()
      borderPath.stroke()

      // Draw dashed inner border
      let dashPath = NSBezierPath(rect: selectionRect.insetBy(dx: 1, dy: 1))
      dashPath.lineWidth = 1
      dashPath.setLineDash([4, 4], count: 2, phase: 0)
      NSColor.systemBlue.setStroke()
      dashPath.stroke()

      // Draw size label
      let sizeText = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
      let attributes: [NSAttributedString.Key: Any] = [
        .font: AppFont.nsFont(size: 12),
        .foregroundColor: NSColor.white,
        .backgroundColor: NSColor.black.withAlphaComponent(0.7),
      ]
      let textSize = sizeText.size(withAttributes: attributes)
      let textRect = CGRect(
        x: selectionRect.maxX - textSize.width - 8,
        y: selectionRect.minY - textSize.height - 4,
        width: textSize.width + 8,
        height: textSize.height + 4
      )

      if textRect.minY > 0 {
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: textRect, xRadius: 3, yRadius: 3).fill()
        sizeText.draw(
          at: CGPoint(x: textRect.minX + 4, y: textRect.minY + 2), withAttributes: attributes)
      }
    }
    // No instructions overlay - keep it minimal with just crosshair cursor
  }

  private func normalizedRect(from start: NSPoint, to end: NSPoint) -> CGRect {
    let x = min(start.x, end.x)
    let y = min(start.y, end.y)
    let width = abs(end.x - start.x)
    let height = abs(end.y - start.y)
    return CGRect(x: x, y: y, width: width, height: height)
  }
}
