import AppKit
import Combine
import Foundation
import SwiftUI

class OnboardingWindowController: NSObject, ObservableObject, NSWindowDelegate {
  private var window: NSWindow?
  @Published var isVisible = false

  var onComplete: (() -> Void)?

  func show() {
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
    let window = KeyableWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.backgroundColor = .white
    window.isOpaque = true
    window.hasShadow = true
    window.isReleasedWhenClosed = false
    window.delegate = self

    let onboardingView = OnboardingView(
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
