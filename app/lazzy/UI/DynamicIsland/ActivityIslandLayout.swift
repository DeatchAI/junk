import CoreGraphics

/// AppKit owns these dimensions; streamed content never drives window sizing.
enum ActivityIslandLayout {
  static let compactHeightPadding: CGFloat = 6
  static let compactSideSize = CGSize(width: 48, height: 124)

  static func frame(
    placement: ActivityIslandPlacement,
    screenFrame: CGRect,
    visibleFrame: CGRect,
    physicalNotch: CGSize,
    expanded: Bool,
    contentSize: CGSize
  ) -> CGRect {
    if placement.isSide {
      let size = expanded
        ? CGSize(
          width: min(440, visibleFrame.width - 32),
          height: min(contentSize.height + ActivityIslandContentLayout.sideInset * 2, visibleFrame.height - 32)
        )
        : compactSideSize
      return ScreenEdgePanelLayout.frame(placement: placement, visibleFrame: visibleFrame, size: size)
    }

    let compactWidth = physicalNotch.width + 168
    let size = expanded
      ? CGSize(
        width: min(max(contentSize.width, compactWidth), max(360, visibleFrame.width - 48)),
        height: physicalNotch.height + contentSize.height
      )
      : CGSize(width: compactWidth, height: physicalNotch.height + compactHeightPadding)
    return CGRect(
      x: screenFrame.midX - size.width / 2,
      y: screenFrame.maxY - size.height,
      width: size.width,
      height: size.height
    )
  }
}
