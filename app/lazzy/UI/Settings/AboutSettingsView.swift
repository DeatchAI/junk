import SwiftUI

struct AboutSettingsView: View {
  @ObservedObject private var theme = ThemeManager.shared
  @State private var isHoveringLogo = false
  @Environment(\.colorScheme) var colorScheme

  private var appVersion: String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    return "VERSION \(version) (\(build))"
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        SettingsPageHeader(
          title: "About",
          subtitle: "Product information, version details, and helpful links."
        )

        SettingsCard {
          HStack(spacing: 18) {
            Image(colorScheme == .dark ? "LazzyIcon-lg-dark" : "LazzyIcon-lg-white")
              .resizable()
              .scaledToFit()
              .frame(width: 76, height: 76)
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
              .grayscale(isHoveringLogo ? 0 : 0.15)
              .scaleEffect(isHoveringLogo ? 1.025 : 1.0)
              .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHoveringLogo)
              .onHover { isHoveringLogo = $0 }

            VStack(alignment: .leading, spacing: 5) {
              Text("Detach")
                .font(.appFont(size: 22, weight: .semibold))
                .foregroundColor(theme.textColor)

              Text("Your local macOS AI assistant")
                .font(.appFont(size: 12))
                .foregroundColor(theme.secondaryTextColor)

              Text(appVersion)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundColor(theme.secondaryTextColor.opacity(0.8))
                .padding(.top, 5)
            }

            Spacer()
          }
          .padding(18)
        }

        VStack(alignment: .leading, spacing: 10) {
          SettingsSectionHeader(title: "Links")

          SettingsCard {
            AboutLink(title: "Website", subtitle: "Product news and downloads", url: "https://getlazzy.app", icon: "globe")
            SettingsCardDivider()
            AboutLink(title: "X / Twitter", subtitle: "Follow Detach updates", url: "https://x.com/getlazzyapp", icon: "bubble.left.and.bubble.right")
            SettingsCardDivider()
            AboutLink(title: "Privacy", subtitle: "How Detach handles your data", url: "https://getlazzy.app/privacy", icon: "hand.raised")
            SettingsCardDivider()
            AboutLink(title: "Terms", subtitle: "Terms of service", url: "https://getlazzy.app/terms", icon: "doc.text")
            SettingsCardDivider()
            AboutLink(title: "Contact", subtitle: "Get help or share feedback", url: "mailto:hello@getlazzy.app", icon: "envelope")
          }
        }

        Text("© 2026 Goloak Vrindavan Inc.")
          .font(.appFont(size: 10))
          .foregroundColor(theme.secondaryTextColor.opacity(0.65))

        Spacer(minLength: 20)
      }
      .padding(.bottom, 24)
    }
  }
}

struct AboutLink: View {
  let title: String
  let subtitle: String
  let url: String
  let icon: String
  @State private var isHovered = false
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Button(action: {
      if let destination = URL(string: url) {
        NSWorkspace.shared.open(destination)
      }
    }) {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(isHovered ? theme.accentColor : theme.secondaryTextColor)
          .frame(width: 20)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.appFont(size: 12, weight: .medium))
            .foregroundColor(theme.textColor)
          Text(subtitle)
            .font(.appFont(size: 10.5))
            .foregroundColor(theme.secondaryTextColor)
        }

        Spacer()

        Image(systemName: "arrow.up.right")
          .font(.system(size: 9, weight: .semibold))
          .foregroundColor(isHovered ? theme.accentColor : theme.secondaryTextColor.opacity(0.7))
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 11)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }
}
