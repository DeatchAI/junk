import CoreGraphics

enum ScreenEdgePanelLayout {
  static func frame(
    placement: ActivityIslandPlacement,
    visibleFrame: CGRect,
    size: CGSize
  ) -> CGRect {
    CGRect(
      x: placement == .left ? visibleFrame.minX : visibleFrame.maxX - size.width,
      y: visibleFrame.midY - size.height / 2,
      width: size.width,
      height: size.height
    )
  }
}
