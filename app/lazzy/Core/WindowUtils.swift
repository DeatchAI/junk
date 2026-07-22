import AppKit

/// A window that can become key/main even if it's borderless
class KeyableWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

/// A panel that can become key/main even if it's a non-activating panel
class KeyablePanel: NSPanel {
  var onCancelOperation: (() -> Void)?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  override func cancelOperation(_ sender: Any?) {
    if let onCancelOperation {
      onCancelOperation()
    } else {
      super.cancelOperation(sender)
    }
  }
}
