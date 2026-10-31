import AppKit

extension FloatingWindowController {
  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    guard sender === chatWindow else { return frameSize }
    let screen = sender.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? sender.frame
    let minimumHeight: CGFloat
    if isExpanded {
      minimumHeight = FloatingChatWindowLayout.minimumHeight
    } else if abs(frameSize.height - sender.frame.height) < 0.5 {
      minimumHeight = min(FloatingChatWindowLayout.resizeMinimumHeight, sender.frame.height)
    } else {
      minimumHeight = FloatingChatWindowLayout.resizeMinimumHeight
    }
    let size = FloatingChatWindowLayout.userResizableSize(
      frameSize, visibleFrame: screen, minimumHeight: minimumHeight
    )

    sender.minSize = NSSize(
      width: min(FloatingChatWindowLayout.minimumWidth, size.width), height: minimumHeight
    )
    guard let panel = sender as? FloatingComposerPanel else { return size }
    panel.fixedContentWidth = size.width
    panel.expandedScreenBounds = screen.insetBy(
      dx: FloatingChatWindowLayout.margin, dy: FloatingChatWindowLayout.margin
    )
    if abs(windowContentWidth - size.width) > 0.5 { windowContentWidth = size.width }
    if !isExpanded {
      if !isManuallyResized { isManuallyResized = true }
      if abs((manuallyResizedHeight ?? 0) - size.height) > 0.5 {
        manuallyResizedHeight = size.height
      }
    }
    return size
  }

  func windowDidResize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window === chatWindow else { return }
    let frame = window.frame
    if abs(windowContentWidth - frame.width) > 0.5 {
      windowContentWidth = frame.width
      (window as? FloatingComposerPanel)?.fixedContentWidth = frame.width
    }
    if !isExpanded && isManuallyResized,
      abs((manuallyResizedHeight ?? 0) - frame.height) > 0.5
    {
      manuallyResizedHeight = frame.height
    }
    updateExpandedContentHeight()
    rememberCurrentWindowFrame()
  }
}
