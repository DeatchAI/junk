import AppKit

/// Non-activating, monochrome control indicator. Stop revokes the native task immediately.
@MainActor final class DesktopControlIndicator {
  private var panel: NSPanel?
  private var sessionID: String?
  private var stop: (() -> Void)?
  private var controls: [String: (app: String, stop: () -> Void)] = [:]

  func show(app: String, session: String, onStop: @escaping () -> Void) {
    controls[session] = (app, onStop)
    sessionID = session
    stop = onStop
    if panel == nil {
      let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
      let label = NSTextField(labelWithString: "")
      label.identifier = NSUserInterfaceItemIdentifier("control-label")
      label.frame = NSRect(x: 12, y: 11, width: 225, height: 18)
      label.font = .systemFont(ofSize: 12, weight: .medium)
      label.textColor = .labelColor
      let button = NSButton(title: "Stop", target: self, action: #selector(stopPressed))
      button.frame = NSRect(x: 237, y: 7, width: 55, height: 26)
      button.bezelStyle = .rounded
      view.addSubview(label); view.addSubview(button)
      let window = NSPanel(contentRect: view.bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      window.contentView = view
      window.backgroundColor = .windowBackgroundColor
      window.level = .floating
      window.hasShadow = true
      window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      window.isReleasedWhenClosed = false
      panel = window
    }
    (panel?.contentView?.subviews.first as? NSTextField)?.stringValue = "Agent using \(app)"
    if let screen = NSScreen.main {
      panel?.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 150, y: screen.visibleFrame.maxY - 54))
    }
    panel?.orderFrontRegardless()
  }

  func hide(session: String) {
    controls.removeValue(forKey: session)
    guard sessionID == session else { return }
    if let next = controls.first { show(app: next.value.app, session: next.key, onStop: next.value.stop) }
    else { panel?.orderOut(nil); sessionID = nil; stop = nil }
  }

  @objc private func stopPressed() { let action = stop; action?() }
}
