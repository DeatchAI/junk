import AppKit

enum FloatingChatWindowLayout {
  static let width: CGFloat = 520
  static let minimumHeight: CGFloat = 280
  // Compact height comes from the visible SwiftUI content. A 280pt minimum
  // leaves transparent space above a short composer and limits upward dragging.
  static let compactMinimumHeight: CGFloat = 1
  static let margin: CGFloat = 20

  static func frame(from current: NSRect, visibleFrame: NSRect, expanded: Bool) -> NSRect {
    let bounds = visibleFrame.insetBy(dx: margin, dy: margin)
    let height = expanded ? bounds.height : min(minimumHeight, bounds.height)
    let x = max(bounds.minX, min(current.minX, bounds.maxX - width))
    let y = expanded ? bounds.minY : max(bounds.minY, min(current.maxY - height, bounds.maxY - height))
    return NSRect(x: x, y: y, width: width, height: height)
  }

  static func visibleFrame(near location: NSPoint) -> NSRect {
    NSScreen.screens.first(where: { $0.frame.contains(location) })?.visibleFrame
      ?? NSScreen.main?.visibleFrame ?? .zero
  }

  static func visibleFrame(for preferredFrame: NSRect?, fallbackLocation: NSPoint) -> NSRect {
    if let preferredFrame,
      let screen = NSScreen.screens.first(where: {
        $0.frame.contains(NSPoint(x: preferredFrame.midX, y: preferredFrame.midY))
      }) {
      return screen.visibleFrame
    }
    return visibleFrame(near: fallbackLocation)
  }

  static func centeredFrame(visibleFrame: NSRect, height: CGFloat) -> NSRect {
    let bounds = visibleFrame.insetBy(dx: margin, dy: margin)
    let safeHeight = min(max(height, compactMinimumHeight), max(compactMinimumHeight, bounds.height))
    let x = max(bounds.minX, min(bounds.midX - width / 2, bounds.maxX - width))
    let y = max(bounds.minY, min(bounds.midY - safeHeight / 2, bounds.maxY - safeHeight))
    return NSRect(x: x, y: y, width: width, height: safeHeight)
  }

  static func restoredFrame(
    from preferredFrame: NSRect?,
    visibleFrame: NSRect,
    expanded: Bool,
    fallbackHeight: CGFloat
  ) -> NSRect {
    if expanded {
      let source = preferredFrame ?? centeredFrame(visibleFrame: visibleFrame, height: fallbackHeight)
      return frame(from: source, visibleFrame: visibleFrame, expanded: true)
    }

    let bounds = visibleFrame.insetBy(dx: margin, dy: margin)
    guard let preferredFrame, bounds.contains(preferredFrame) else {
      return centeredFrame(visibleFrame: visibleFrame, height: fallbackHeight)
    }

    let height = min(max(preferredFrame.height, compactMinimumHeight), max(compactMinimumHeight, bounds.height))
    let x = max(bounds.minX, min(preferredFrame.minX, bounds.maxX - width))
    let y = max(bounds.minY, min(preferredFrame.maxY - height, bounds.maxY - height))
    return NSRect(x: x, y: y, width: width, height: height)
  }

  static func resize(_ proposed: NSSize, visibleFrame: NSRect, expanded: Bool) -> NSSize {
    let maximumHeight = max(1, visibleFrame.height - (expanded ? margin * 2 : 0))
    let minimum = expanded ? minimumHeight : compactMinimumHeight
    return NSSize(width: width, height: min(max(proposed.height, min(minimum, maximumHeight)), maximumHeight))
  }
}

struct FloatingWindowPlacementState {
  var collapsedFrame: NSRect?
  var expandedFrame: NSRect?
  var handoffInProgress = false
  var handoffID: UUID?
}
