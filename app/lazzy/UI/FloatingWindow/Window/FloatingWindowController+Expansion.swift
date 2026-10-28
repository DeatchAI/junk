import AppKit

extension FloatingWindowController {
  func toggleExpansion() {
    guard let window = chatWindow else { return }
    let expanded = !isExpanded
    let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
    let frame = FloatingChatWindowLayout.frame(from: window.frame, visibleFrame: visibleFrame, expanded: expanded)
    (window as? FloatingComposerPanel)?.expandedScreenBounds = expanded
      ? visibleFrame.insetBy(dx: FloatingChatWindowLayout.margin, dy: FloatingChatWindowLayout.margin) : nil

    if expanded {
      window.styleMask.insert(.resizable)
      window.standardWindowButton(.zoomButton)?.isHidden = true
      window.standardWindowButton(.closeButton)?.isHidden = true
      window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    } else {
      window.styleMask.remove(.resizable)
    }
    let minimumHeight = expanded ? FloatingChatWindowLayout.minimumHeight : FloatingChatWindowLayout.compactMinimumHeight
    window.minSize = NSSize(width: FloatingChatWindowLayout.width, height: min(minimumHeight, frame.height))
    window.maxSize = NSSize(width: FloatingChatWindowLayout.width,
      height: expanded ? frame.height : .greatestFiniteMagnitude)
    isExpanded = expanded
    if expanded { updateExpandedContentHeight(to: frame.height) }
    // Match the native viewport immediately. The resize delegate keeps it in sync
    // while the user adjusts the expanded panel's height.
    window.setFrame(frame, display: true)
    rememberCurrentWindowFrame()
    updateExpandedContentHeight()
    resetAnchor()
  }

  func windowDidChangeScreen(_ notification: Notification) {
    guard isExpanded, let window = chatWindow, let screen = window.screen else { return }
    let bounds = screen.visibleFrame.insetBy(dx: FloatingChatWindowLayout.margin, dy: FloatingChatWindowLayout.margin)
    (window as? FloatingComposerPanel)?.expandedScreenBounds = bounds
    window.maxSize.height = bounds.height
    window.setFrame(window.frame, display: true)
    rememberCurrentWindowFrame()
    updateExpandedContentHeight()
  }
}
