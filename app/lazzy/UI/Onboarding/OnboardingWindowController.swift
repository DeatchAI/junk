import AppKit
import Combine
import Foundation
import SwiftUI

class OnboardingWindowController: NSObject, ObservableObject, NSWindowDelegate {
  private var window: NSWindow?
  private var licenseOnly = false
  @Published var isVisible = false

  var onComplete: (() -> Void)?

  func show(licenseOnly: Bool = false) {
    if window != nil, self.licenseOnly != licenseOnly { close() }
    self.licenseOnly = licenseOnly
    if window == nil {
      createWindow()
    }
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    isVisible = true
  }

  func close() {
    let closingWindow = window
    window = nil
    isVisible = false
    closingWindow?.delegate = nil
    closingWindow?.close()
  }

  func windowWillClose(_ notification: Notification) {
    window = nil
    isVisible = false
  }

  private func createWindow() {
    let visibleFrame = NSScreen.main?.visibleFrame
    let width = min(1040, max(700, visibleFrame?.width ?? 1040))
    let height = min(748, max(520, visibleFrame?.height ?? 748))
    let window = KeyableWindow(
      contentRect: NSRect(x: 0, y: 0, width: width, height: height),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = true
    window.isReleasedWhenClosed = false
    window.contentMinSize = NSSize(width: 700, height: 520)
    window.delegate = self

    let onboardingView = OnboardingView(
      licenseOnly: licenseOnly,
      onComplete: { [weak self] in
        self?.onComplete?()
      }
    )

    let hostingView = NSHostingView(rootView: onboardingView)
    window.contentView = hostingView

    window.center()
    self.window = window
  }
}
