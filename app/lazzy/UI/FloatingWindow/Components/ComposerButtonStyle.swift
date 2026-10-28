import SwiftUI

/// A full rectangular hit target with quiet hover and pressed feedback.
struct ComposerButtonStyle: ButtonStyle {
  var cornerRadius: CGFloat = 7
  @Environment(\.isEnabled) private var isEnabled
  @ObservedObject private var theme = ThemeManager.shared
  @State private var isHovered = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .contentShape(Rectangle())
      .background {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(theme.textColor.opacity(
            !isEnabled ? 0 : configuration.isPressed ? 0.16 : isHovered ? 0.08 : 0
          ))
      }
      .onHover { isHovered = $0 }
      .animation(.easeOut(duration: 0.1), value: isHovered)
      .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
  }
}
