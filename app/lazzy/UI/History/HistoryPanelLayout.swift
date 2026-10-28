import CoreGraphics

enum HistoryPanelLayout {
  static let expandedWidth: CGFloat = 360
  static func frame(
    placement: ActivityIslandPlacement,
    visibleFrame: CGRect,
    expanded: Bool
  ) -> CGRect {
    let size = expanded
      ? CGSize(width: min(expandedWidth, visibleFrame.width - 32), height: min(640, visibleFrame.height - 48))
      : ActivityIslandLayout.compactSideSize
    return ScreenEdgePanelLayout.frame(placement: placement, visibleFrame: visibleFrame, size: size)
  }
}
