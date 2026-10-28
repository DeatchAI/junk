import SwiftUI

enum ComposerMenuStyle {
  static let rootWidth: CGFloat = 248
  static let detailWidth: CGFloat = 300
  static let commandWidth: CGFloat = 280
  static let rowHeight: CGFloat = 26
  static let panelInset: CGFloat = 8
}

private struct ComposerMenuSurface: ViewModifier {
  let width: CGFloat
  @ObservedObject private var theme = ThemeManager.shared

  func body(content: Content) -> some View {
    content.padding(4).frame(width: width, alignment: .leading)
      .themedSurface(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(theme.textColor.opacity(theme.mode == .liquidGlass ? 0 : 0.13), lineWidth: 0.5)
          .allowsHitTesting(false)
      }
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

extension View {
  func composerMenuSurface(width: CGFloat) -> some View { modifier(ComposerMenuSurface(width: width)) }
}
