import SwiftUI

/// The same flared edge treatment follows the selected screen edge.
struct ScreenEdgeNotchShape: Shape {
  var placement: ActivityIslandPlacement

  func path(in rect: CGRect) -> Path {
    let bounds = placement.isSide
      ? CGRect(x: 0, y: 0, width: rect.height, height: rect.width)
      : CGRect(origin: .zero, size: rect.size)
    let path = topPath(in: bounds)
    let transform: CGAffineTransform
    switch placement {
    case .top:
      transform = .identity
    case .right:
      transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: rect.width, ty: 0)
    case .left:
      transform = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: rect.height)
    }
    return path.applying(transform).offsetBy(dx: rect.minX, dy: rect.minY)
  }

  private func topPath(in rect: CGRect) -> Path {
    let top = min(placement.isSide ? 18 : 30, rect.width / 4, rect.height / 4)
    let bottom = min(25, rect.width / 4, rect.height / 2)
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + top, y: rect.minY + top),
      control: CGPoint(x: rect.minX + top, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
      control: CGPoint(x: rect.minX + top, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
      control: CGPoint(x: rect.maxX - top, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY),
      control: CGPoint(x: rect.maxX - top, y: rect.minY)
    )
    path.closeSubpath()
    return path
  }
}
