import AppKit
import ApplicationServices
import Combine
import Foundation

/// Monitors for text selections using:
/// 1. Mouse events + Accessibility API (for native apps)
/// 2. Clipboard changes (fallback for browsers like Safari/Chrome)
///
/// Finder selections are intentionally excluded. Files are handed to Detach only
/// through an explicit Finder command or keyboard shortcut.
class SelectionMonitor: ObservableObject {

  @Published private(set) var hasActiveSelection = false
  @Published private(set) var selectionLocation: NSPoint = .zero
  @Published private(set) var detectedContent: DetectedContent?

  private var mouseUpMonitor: Any?
  private var mouseDownMonitor: Any?
  private var clickOutsideMonitor: Any?
  private var mouseDownLocation: NSPoint = .zero
  private var isMouseDragging = false

  private let finderIntegration = FinderIntegration()
  private let selectionDetector = SelectionDetector()

  // Triple-click detection
  private var clickTimes: [Date] = []
  private var clickLocations: [NSPoint] = []
  private let tripleClickTimeThreshold: TimeInterval = 0.5  // Max time between clicks
  private let tripleClickDistanceThreshold: CGFloat = 10  // Max distance between clicks

  // Apps that don't support Accessibility API (use clipboard fallback)
  private let browserBundleIds = [
    "com.apple.Safari",
    "com.google.Chrome",
    "org.mozilla.firefox",
    "com.microsoft.edgemac",
    "com.brave.Browser",
    "com.operasoftware.Opera",
  ]

  // Callbacks
  var onSelectionDetected: ((DetectedContent, NSPoint) -> Void)?
  var onSelectionCleared: (() -> Void)?
  var onTripleClickDetected: ((NSPoint) -> Void)?

  // Minimum drag distance to consider as a selection (in points)
  private let minDragDistance: CGFloat = 20

  init() {
    requestAccessibilityPermissionIfNeeded()
  }

  deinit {
    stopMonitoring()
  }

  // MARK: - Monitoring

  func startMonitoring() {
    guard mouseUpMonitor == nil else { return }

    print("👁️ Selection monitor started")
    print("   🖱️ Mouse selection for native apps")
    print("   📋 Clipboard fallback for browsers (⌘+C)")

    // Monitor mouse down to track drag start and detect triple-clicks
    mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
      [weak self] event in
      guard let self = self else { return }

      let currentLocation = NSEvent.mouseLocation
      let currentTime = Date()

      // Triple-click detection
      self.clickTimes.append(currentTime)
      self.clickLocations.append(currentLocation)

      // Keep only the last 3 clicks
      if self.clickTimes.count > 3 {
        self.clickTimes.removeFirst()
        self.clickLocations.removeFirst()
      }

      // Check if we have 3 clicks
      if self.clickTimes.count == 3 {
        let firstClickTime = self.clickTimes[0]
        let firstClickLocation = self.clickLocations[0]

        // Check time threshold (all 3 clicks within threshold)
        let timeSinceFirst = currentTime.timeIntervalSince(firstClickTime)

        // Check distance threshold (all clicks near each other)
        let distanceFromFirst = hypot(
          currentLocation.x - firstClickLocation.x,
          currentLocation.y - firstClickLocation.y
        )

        if timeSinceFirst <= self.tripleClickTimeThreshold
          && distanceFromFirst <= self.tripleClickDistanceThreshold
        {
          // Triple-click detected!
          print("🖱️🖱️🖱️ Triple-click detected at \(currentLocation)")

          // Clear click history to prevent re-triggering
          self.clickTimes.removeAll()
          self.clickLocations.removeAll()

          // Trigger callback (on main thread, with small delay to let system handle the click)
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.onTripleClickDetected?(currentLocation)
          }
          return
        }
      }

      // Continue with normal drag tracking
      self.mouseDownLocation = currentLocation
      self.isMouseDragging = true
    }

    // Monitor mouse up to detect selection end
    mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) {
      [weak self] event in
      guard let self = self else { return }

      let mouseUpLocation = NSEvent.mouseLocation
      let dragDistance = hypot(
        mouseUpLocation.x - self.mouseDownLocation.x,
        mouseUpLocation.y - self.mouseDownLocation.y)

      // Only trigger if it was a drag (not a click)
      if self.isMouseDragging && dragDistance > self.minDragDistance {
        // Native app: use Accessibility API
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
          self.checkForTextSelection(at: mouseUpLocation)
        }
      }

      self.isMouseDragging = false
    }

  }

  func stopMonitoring() {
    if let monitor = mouseUpMonitor {
      NSEvent.removeMonitor(monitor)
      mouseUpMonitor = nil
    }
    if let monitor = mouseDownMonitor {
      NSEvent.removeMonitor(monitor)
      mouseDownMonitor = nil
    }
    print("🛑 Selection monitor stopped")
  }

  // MARK: - Browser Detection

  private func isBrowserFrontmost() -> Bool {
    guard let frontApp = NSWorkspace.shared.frontmostApplication,
      let bundleId = frontApp.bundleIdentifier
    else {
      return false
    }
    return browserBundleIds.contains(bundleId)
  }

  // MARK: - Selection Detection

  private func checkForTextSelection(at location: NSPoint) {
    // Skip if Finder is frontmost (use file selection instead)
    if finderIntegration.isFinderFrontmost() {
      return
    }
    // Try Accessibility API first (via shared detector, which handles auth check)
    if let selectedText = selectionDetector.getSelectedText(), !selectedText.isEmpty {
      print("📝 Text selected with Accessibility")
      let content = DetectedContent(type: .text, text: selectedText, files: nil)
      triggerSelection(content: content, at: location)
      return
    }
    // If no text via Accessibility and the frontmost app is a browser, fallback to clipboard method
    if isBrowserFrontmost() {
      if let clipboardText = selectionDetector.getSelectedTextViaClipboard(),
        !clipboardText.isEmpty
      {
        print(
          "📋 Text selected (Clipboard fallback for browser): \"\(clipboardText.prefix(40))...\""
        )
        let content = DetectedContent(type: .text, text: clipboardText, files: nil)
        triggerSelection(content: content, at: location)
      }
    }
  }

  // Request Accessibility permission if not granted
  private func requestAccessibilityPermissionIfNeeded() {
    let options =
      [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }

  // MARK: - Trigger

  private func triggerSelection(content: DetectedContent, at location: NSPoint) {
    // Don't trigger again if already showing
    if hasActiveSelection { return }

    hasActiveSelection = true
    selectionLocation = location
    detectedContent = content

    print("✨ Selection detected! Showing trigger icon at \(location)")
    onSelectionDetected?(content, location)

    // Start monitoring for clicks outside
    startClickOutsideMonitor()
  }

  // MARK: - Click Outside

  private func startClickOutsideMonitor() {
    // Remove existing monitor
    if let monitor = clickOutsideMonitor {
      NSEvent.removeMonitor(monitor)
    }

    // Monitor for any clicks - if not on our icon, dismiss
    clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
      .leftMouseDown, .rightMouseDown,
    ]) { [weak self] event in
      // The TriggerIconController will handle hiding if clicked
      // This catches clicks elsewhere
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        // Only clear if we're still showing (icon click will clear first)
        if self?.hasActiveSelection == true {
          self?.clearSelection()
        }
      }
    }
  }

  func clearSelection() {
    guard hasActiveSelection else { return }

    hasActiveSelection = false
    detectedContent = nil

    if let monitor = clickOutsideMonitor {
      NSEvent.removeMonitor(monitor)
      clickOutsideMonitor = nil
    }

    onSelectionCleared?()
    print("⚪ Selection cleared")
  }
}
