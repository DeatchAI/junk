import AppKit
import Combine
import Foundation
import SwiftUI

class OnboardingWindowController: NSObject, ObservableObject {
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
    window?.close()
    window = nil
    isVisible = false
  }

  private func createWindow() {
    let window = KeyableWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1_020, height: 680),
      styleMask: [.borderless],
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

    let onboardingView = OnboardingView(
      onComplete: { [weak self] in
        self?.onComplete?()
      },
      onClose: { [weak self] in
        // Closing setup means "finish later", not leaving the app in a state
        // where its core services never start.
        self?.onComplete?()
      }
    )

    let hostingView = NSHostingView(
      rootView: onboardingView.font(.custom("Geist-Regular", size: 14)))
    window.contentView = hostingView

    window.center()
    self.window = window
  }
}
