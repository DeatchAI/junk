import AppKit

/// Keeps AppKit content fitting aligned with the composer’s user-selected width
/// while bounding its height and position to the current display.
final class FloatingComposerPanel: KeyablePanel {
  var fixedContentWidth: CGFloat = 0
  /// Bounds applied when the panel uses a fixed viewport or the expanded layout.
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
      frame.size.width = min(frame.width, bounds.width)
      frame.size.height = min(frame.height, bounds.height)
      frame.origin.x = max(bounds.minX, min(frame.minX, bounds.maxX - frame.width))
      frame.origin.y = max(bounds.minY, min(frame.minY, bounds.maxY - frame.height))
    }
    return frame
  }
}
