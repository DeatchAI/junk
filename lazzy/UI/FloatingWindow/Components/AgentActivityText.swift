import SwiftUI

struct AgentActivityText: View {
  let activity: String
  var fontSize: CGFloat = 11
  var isActive: Bool = true

  @ObservedObject private var theme = ThemeManager.shared

  @ViewBuilder
  var body: some View {
    let text = Text(activity)
      .font(.appFont(size: fontSize, weight: .medium))
      .foregroundColor(isActive ? theme.textColor.opacity(0.82) : theme.secondaryTextColor)
      .lineLimit(2)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityLabel(activity)

    if isActive {
      HStack(spacing: 8) {
        ShimmerBar()
          .frame(width: 22, height: 2)
        text.shimmer()
      }
    } else {
      text
    }
  }
}

private struct ShimmerBar: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 1)
      .fill(Color.white.opacity(0.65))
      .shimmer()
      .accessibilityHidden(true)
  }
}
