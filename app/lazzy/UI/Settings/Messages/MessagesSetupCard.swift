import SwiftUI

/// Setup surfaces outside Settings use the same card and control styling.
struct MessagesSetupCard<Content: View>: View {
  let number: Int
  let title: String
  var complete = false
  @ViewBuilder let content: () -> Content
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    SettingsCard {
      VStack(alignment: .leading, spacing: 9) {
        HStack(spacing: 8) {
          Text(complete ? "✓" : String(number))
            .font(.appFont(size: 10, weight: .medium))
            .frame(width: 19, height: 19)
            .background(theme.textColor.opacity(0.07), in: Circle())
          Text(title).font(.appFont(size: 12.5, weight: .medium))
        }.foregroundStyle(theme.textColor)
        content().font(.appFont(size: 11.5)).foregroundStyle(theme.secondaryTextColor)
      }
      .frame(maxWidth: .infinity, alignment: .leading).padding(14)
    }
    .buttonStyle(AppButtonStyle())
  }
}
