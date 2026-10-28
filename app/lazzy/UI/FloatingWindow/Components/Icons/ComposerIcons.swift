import SwiftUI

struct ComposerBrainIcon: View {
  var body: some View {
    BrainOutline().stroke(style: composerIconStroke)
      .accessibilityHidden(true)
  }
}

struct ComposerFolderIcon: View {
  var isAdding = false

  var body: some View {
    FolderOutline(isAdding: isAdding).stroke(style: composerIconStroke)
      .accessibilityHidden(true)
  }
}

private let composerIconStroke = StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)

private struct BrainOutline: Shape {
  func path(in rect: CGRect) -> Path {
    var hemisphere = Path()
    hemisphere.move(to: CGPoint(x: 12, y: 5.2))
    hemisphere.addCurve(to: CGPoint(x: 9.3, y: 2.5),
      control1: CGPoint(x: 12, y: 3.6), control2: CGPoint(x: 10.8, y: 2.5))
    hemisphere.addCurve(to: CGPoint(x: 6.4, y: 5.35),
      control1: CGPoint(x: 7.7, y: 2.5), control2: CGPoint(x: 6.4, y: 3.8))
    hemisphere.addCurve(to: CGPoint(x: 3, y: 8.65),
      control1: CGPoint(x: 4.45, y: 5.3), control2: CGPoint(x: 3, y: 6.8))
    hemisphere.addCurve(to: CGPoint(x: 3.7, y: 10.65),
      control1: CGPoint(x: 3, y: 9.4), control2: CGPoint(x: 3.25, y: 10.1))
    hemisphere.addCurve(to: CGPoint(x: 2.25, y: 13.65),
      control1: CGPoint(x: 2.8, y: 11.3), control2: CGPoint(x: 2.25, y: 12.45))
    hemisphere.addCurve(to: CGPoint(x: 5.25, y: 17.15),
      control1: CGPoint(x: 2.25, y: 15.4), control2: CGPoint(x: 3.55, y: 16.9))
    hemisphere.addCurve(to: CGPoint(x: 9.1, y: 21.3),
      control1: CGPoint(x: 5.25, y: 19.5), control2: CGPoint(x: 6.75, y: 21.3))
    hemisphere.addCurve(to: CGPoint(x: 12, y: 18.5),
      control1: CGPoint(x: 10.75, y: 21.3), control2: CGPoint(x: 12, y: 20.15))

    hemisphere.move(to: CGPoint(x: 6.4, y: 5.35))
    hemisphere.addCurve(to: CGPoint(x: 8.2, y: 8.1),
      control1: CGPoint(x: 6.4, y: 6.7), control2: CGPoint(x: 7.1, y: 7.6))
    hemisphere.move(to: CGPoint(x: 3.7, y: 10.65))
    hemisphere.addCurve(to: CGPoint(x: 6.8, y: 11.15),
      control1: CGPoint(x: 4.8, y: 10.2), control2: CGPoint(x: 6.1, y: 10.5))
    hemisphere.move(to: CGPoint(x: 5.25, y: 17.15))
    hemisphere.addCurve(to: CGPoint(x: 7.85, y: 14.8),
      control1: CGPoint(x: 6.6, y: 17.1), control2: CGPoint(x: 7.75, y: 16.2))
    hemisphere.move(to: CGPoint(x: 9.2, y: 12))
    hemisphere.addCurve(to: CGPoint(x: 12, y: 9.2),
      control1: CGPoint(x: 10.7, y: 12), control2: CGPoint(x: 12, y: 10.6))

    var path = hemisphere
    path.addPath(hemisphere, transform: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 24, ty: 0))
    path.move(to: CGPoint(x: 12, y: 5.2))
    path.addLine(to: CGPoint(x: 12, y: 18.5))
    return scaledComposerIcon(path, in: rect)
  }
}

private struct FolderOutline: Shape {
  let isAdding: Bool

  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: isAdding ? 11 : 19.5, y: 20))
    path.addLine(to: CGPoint(x: 4.5, y: 20))
    path.addQuadCurve(to: CGPoint(x: 3, y: 18.5), control: CGPoint(x: 3, y: 20))
    path.addLine(to: CGPoint(x: 3, y: 5.5))
    path.addQuadCurve(to: CGPoint(x: 4.5, y: 4), control: CGPoint(x: 3, y: 4))
    path.addLine(to: CGPoint(x: 8.5, y: 4))
    path.addQuadCurve(to: CGPoint(x: 10, y: 4.7), control: CGPoint(x: 9.4, y: 4))
    path.addLine(to: CGPoint(x: 11.7, y: 6.5))
    path.addLine(to: CGPoint(x: 19.5, y: 6.5))
    path.addQuadCurve(to: CGPoint(x: 21, y: 8), control: CGPoint(x: 21, y: 6.5))
    path.addLine(to: CGPoint(x: 21, y: isAdding ? 11.5 : 18.5))
    if !isAdding {
      path.addQuadCurve(to: CGPoint(x: 19.5, y: 20), control: CGPoint(x: 21, y: 20))
      path.closeSubpath()
    }
    path.move(to: CGPoint(x: 3, y: 10))
    path.addLine(to: CGPoint(x: 21, y: 10))
    if isAdding {
      path.move(to: CGPoint(x: 18.5, y: 14.5))
      path.addLine(to: CGPoint(x: 18.5, y: 22.5))
      path.move(to: CGPoint(x: 14.5, y: 18.5))
      path.addLine(to: CGPoint(x: 22.5, y: 18.5))
    }
    return scaledComposerIcon(path, in: rect)
  }
}

private func scaledComposerIcon(_ path: Path, in rect: CGRect) -> Path {
  path.applying(CGAffineTransform(a: rect.width / 24, b: 0, c: 0,
    d: rect.height / 24, tx: rect.minX, ty: rect.minY))
}
