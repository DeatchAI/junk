import CoreGraphics

enum DropdownPanelPlacement {
  case below
  case trailing
}

enum DropdownPanelLayout {
  static let gap: CGFloat = 4

  static func frame(anchor: CGRect, size: CGSize, visibleFrame: CGRect,
                    placement: DropdownPanelPlacement) -> CGRect {
    var x: CGFloat
    var y: CGFloat
    switch placement {
    case .below:
      x = anchor.minX
      y = anchor.minY - size.height - gap
      if y < visibleFrame.minY, anchor.maxY + gap + size.height <= visibleFrame.maxY {
        y = anchor.maxY + gap
      }
    case .trailing:
      x = anchor.maxX + gap
      y = anchor.maxY - size.height
      if x + size.width > visibleFrame.maxX { x = anchor.minX - size.width - gap }
    }
    return CGRect(
      x: min(max(x, visibleFrame.minX), visibleFrame.maxX - size.width),
      y: min(max(y, visibleFrame.minY), visibleFrame.maxY - size.height),
      width: size.width, height: size.height
    )
  }

  /// Bridge just the gap, without treating toolbar buttons beside it as menu content.
  static func hoverBridge(anchor: CGRect, panel: CGRect) -> CGRect {
    if panel.maxY <= anchor.minY || panel.minY >= anchor.maxY {
      let left = max(anchor.minX, panel.minX)
      let right = min(anchor.maxX, panel.maxX)
      return CGRect(x: left, y: min(anchor.maxY, panel.maxY), width: max(0, right - left),
                    height: max(0, max(anchor.minY, panel.minY) - min(anchor.maxY, panel.maxY)))
    }
    let bottom = max(anchor.minY, panel.minY)
    let top = min(anchor.maxY, panel.maxY)
    return CGRect(x: min(anchor.maxX, panel.maxX), y: bottom,
                  width: max(0, max(anchor.minX, panel.minX) - min(anchor.maxX, panel.maxX)),
                  height: max(0, top - bottom))
  }
}
