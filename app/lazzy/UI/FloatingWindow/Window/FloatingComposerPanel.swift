import AppKit

/// AppKit can ask a borderless hosting window to adopt its content's fitting
/// width even when the panel is not user-resizable. Keep the composer width
/// stable while allowing the response area to grow vertically.
final class FloatingComposerPanel: KeyablePanel {
  var fixedContentWidth: CGFloat = 0
  /// AppKit's min/max sizes apply to interactive resizing, not every content
  /// fitting request. Expanded panels must also enforce the display's bounds
  /// when the hosting view asks to adopt a long transcript's natural height.
  var expandedScreenBounds: NSRect?

  override func setFrame(_ frameRect: NSRect, display flag: Bool) {
    super.setFrame(constrainedFrame(frameRect), display: flag)
  }

  override func setFrame(
    _ frameRect: NSRect,
    display flag: Bool,
    animate animateFlag: Bool
  ) {
    super.setFrame(constrainedFrame(frameRect), display: flag, animate: animateFlag)
  }

  override func setContentSize(_ size: NSSize) {
    guard fixedContentWidth > 0 else {
      super.setContentSize(size)
      return
    }

    let height = expandedScreenBounds.map {
      min(max(size.height, frame.height), $0.height)
    } ?? size.height
    super.setContentSize(NSSize(width: fixedContentWidth, height: height))
  }

  private func constrainedFrame(_ proposed: NSRect) -> NSRect {
    guard fixedContentWidth > 0 else { return proposed }
    var frame = proposed
    frame.size.width = fixedContentWidth
    if let bounds = expandedScreenBounds {
      frame.size.height = min(frame.height, bounds.height)
      frame.origin.y = max(bounds.minY, min(frame.minY, bounds.maxY - frame.height))
    }
    return frame
  }
}
