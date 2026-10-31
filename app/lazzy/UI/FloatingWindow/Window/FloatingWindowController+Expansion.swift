import AppKit

extension FloatingWindowController {
  func toggleExpansion() {
    guard let window = chatWindow else { return }
    let expanded = !isExpanded
    let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
    let bounds = visibleFrame.insetBy(
      dx: FloatingChatWindowLayout.margin, dy: FloatingChatWindowLayout.margin
    )
    let frame = FloatingChatWindowLayout.frame(
      from: window.frame, visibleFrame: visibleFrame, expanded: expanded, windowWidth: windowContentWidth
    )
    (window as? FloatingComposerPanel)?.expandedScreenBounds = expanded ? bounds : nil
    window.minSize = NSSize(
      width: min(FloatingChatWindowLayout.minimumWidth, frame.width),
      height: min(
        expanded ? FloatingChatWindowLayout.minimumHeight : FloatingChatWindowLayout.resizeMinimumHeight,
        frame.height
      )
    )
    window.maxSize = NSSize(width: bounds.width, height: bounds.height)
    isExpanded = expanded
    isManuallyResized = false
    manuallyResizedHeight = nil
    if expanded { updateExpandedContentHeight(to: frame.height) }
    // Match the native viewport immediately. The resize delegate keeps it in sync
    // while the user adjusts the expanded panel's height.
    window.setFrame(frame, display: true)
    rememberCurrentWindowFrame()
    updateExpandedContentHeight()
    resetAnchor()
  }

  func windowDidChangeScreen(_ notification: Notification) {
    guard let window = chatWindow, let screen = window.screen else { return }
    let bounds = screen.visibleFrame.insetBy(dx: FloatingChatWindowLayout.margin, dy: FloatingChatWindowLayout.margin)
    window.minSize = NSSize(
      width: min(FloatingChatWindowLayout.minimumWidth, bounds.width),
      height: min(isExpanded ? FloatingChatWindowLayout.minimumHeight : FloatingChatWindowLayout.resizeMinimumHeight, bounds.height)
    )
    window.maxSize = NSSize(width: bounds.width, height: bounds.height)
    guard isExpanded || isManuallyResized else { return }
    (window as? FloatingComposerPanel)?.expandedScreenBounds = bounds
    window.setFrame(window.frame, display: true)
    rememberCurrentWindowFrame()
    updateExpandedContentHeight()
  }
}
