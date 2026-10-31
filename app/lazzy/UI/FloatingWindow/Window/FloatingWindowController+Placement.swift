import AppKit

extension FloatingWindowController {
  /// Calculates a window frame using the screen under the cursor, or centers it
  /// on that screen for sessions opened from the Activity Notch.
  func calculateWindowFrame(
    for location: NSPoint, currentHeight: CGFloat, centered: Bool = false, windowWidth: CGFloat? = nil
  ) -> (frame: NSRect, region: AnchorRegion) {
    let windowWidth = windowWidth ?? Self.compactWindowWidth
    let screenFrame = FloatingChatWindowLayout.visibleFrame(near: location)
    if centered {
      return (FloatingChatWindowLayout.centeredFrame(
        visibleFrame: screenFrame, height: currentHeight, windowWidth: windowWidth
      ), .center)
    }
    let relY = (location.y - screenFrame.minY) / screenFrame.height
    let relX = (location.x - screenFrame.minX) / screenFrame.width
    var x = location.x + 20
    var y = location.y - currentHeight / 2
    var region: AnchorRegion = .center

    if relY < 0.25 {
      y = location.y + 20
      region = .bottom
    } else if relY > 0.75 {
      y = location.y - currentHeight - 20
      region = .top
    }
    if relX > 0.7 { x = location.x - windowWidth - 20 }

    let safeWidth = max(1, min(windowWidth, screenFrame.width - 20))
    x = max(screenFrame.minX + 10, min(x, screenFrame.maxX - safeWidth - 10))
    y = max(screenFrame.minY + 10, min(y, screenFrame.maxY - currentHeight - 10))
    return (NSRect(x: x, y: y, width: safeWidth, height: currentHeight), region)
  }

  func rememberCurrentWindowFrame() {
    guard isVisible, !placementState.handoffInProgress, let window = chatWindow else { return }
    if isExpanded {
      placementState.expandedFrame = window.frame
    } else {
      placementState.collapsedFrame = window.frame
    }
  }
}
