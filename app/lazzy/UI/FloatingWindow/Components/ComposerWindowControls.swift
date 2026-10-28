import SwiftUI

struct ComposerWindowControls: View {
  @ObservedObject var controller: FloatingWindowController
  let onClose: () -> Void
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(spacing: 4) {
      Button {
        controller.toggleExpansion()
      } label: {
        Image(systemName: controller.isExpanded
          ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
          .font(.appFont(size: 12, weight: .medium)).frame(width: 26, height: 26)
      }
      .help(controller.isExpanded ? "Shrink composer" : "Expand composer")
      .accessibilityLabel(controller.isExpanded ? "Shrink composer" : "Expand composer")

      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.appFont(size: 12, weight: .medium)).frame(width: 26, height: 26)
      }
      .help("Close conversation")
      .accessibilityLabel("Close conversation")
    }
    .foregroundStyle(theme.secondaryTextColor)
    .buttonStyle(ComposerButtonStyle())
  }
}
