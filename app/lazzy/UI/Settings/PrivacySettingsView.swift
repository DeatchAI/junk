import SwiftUI

struct PrivacySettingsView: View {
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        SettingsPageHeader(
          title: "Privacy",
          subtitle: "Detach is built around local execution and clear boundaries for your data."
        )

        VStack(alignment: .leading, spacing: 10) {
          SettingsSectionHeader(title: "How Detach handles your data")

          SettingsCard {
            PrivacySection(
              icon: "person.crop.circle.badge.checkmark",
              title: "Private by design",
              content: "Your assistant should feel like a private extension of your own mind—not a data collection point."
            )

            SettingsCardDivider()

            PrivacySection(
              icon: "internaldrive",
              title: "Local-first storage",
              content: "Chat history, files, and interactions are stored on this Mac rather than on Detach servers."
            )

            SettingsCardDivider()

            PrivacySection(
              icon: "waveform.slash",
              title: "No usage telemetry",
              content: "Detach does not monitor how you use the app or build a profile from your activity."
            )
          }
        }

        SettingsCard {
          SettingsRow(
            title: "Privacy policy",
            subtitle: "Read the full legal details on the Detach website"
          ) {
            Button(action: {
              if let url = URL(string: "https://getlazzy.app/privacy") {
                NSWorkspace.shared.open(url)
              }
            }) {
              HStack(spacing: 5) {
                Text("Open")
                Image(systemName: "arrow.up.right")
              }
              .font(.appFont(size: 11, weight: .medium))
              .foregroundColor(theme.accentColor)
            }
            .buttonStyle(.plain)
          }
        }

        Spacer(minLength: 20)
      }
      .padding(.bottom, 24)
    }
  }
}

struct PrivacySection: View {
  let icon: String
  let title: String
  let content: String
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(alignment: .top, spacing: 13) {
      Image(systemName: icon)
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(theme.accentColor)
        .frame(width: 28, height: 28)
        .background(theme.accentColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.appFont(size: 12.5, weight: .medium))
          .foregroundColor(theme.textColor)

        Text(content)
          .font(.appFont(size: 10.5))
          .foregroundColor(theme.secondaryTextColor)
          .lineSpacing(2)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
  }
}
