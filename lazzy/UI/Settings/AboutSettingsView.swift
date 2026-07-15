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
    VStack(spacing: 0) {
      Spacer()

      VStack(spacing: 32) {
        // App Icon
        Image(colorScheme == .dark ? "LazzyIcon-lg-dark" : "LazzyIcon-lg-white")
          .resizable()
          .scaledToFit()
          .frame(width: 140, height: 140)
          .cornerRadius(20)
          .grayscale(isHoveringLogo ? 0 : 0.2)
          .scaleEffect(isHoveringLogo ? 1.02 : 1.0)
          .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHoveringLogo)
          .onHover { isHoveringLogo = $0 }

        VStack(spacing: 8) {
          Text("Detach")
            .font(.custom("Sick-Regular", size: 52))
            .foregroundColor(theme.textColor)

          Text(appVersion)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(theme.textColor.opacity(0.5))
            .tracking(1)
        }
      }

      VStack(spacing: 24) {
        Text("Your macOS AI assistant.")
          .font(.appFont(size: 18))
          .tracking(-1)
          .foregroundColor(theme.textColor.opacity(0.8))
          .multilineTextAlignment(.center)

        Text(
          "Detach lives in your menu bar and helps you get work done."
        )
        .font(.appFont(size: 13))
        .foregroundColor(theme.textColor.opacity(0.5))
        .multilineTextAlignment(.center)
        .lineSpacing(4)
        .padding(.horizontal, 40)
      }
      .padding(.top, 10)

      Spacer()

      HStack(spacing: 24) {
        AboutLink(title: "Website", url: "https://getlazzy.app")
        AboutLink(title: "Twitter", url: "https://x.com/getlazzyapp")
        AboutLink(title: "Privacy", url: "https://getlazzy.app/privacy")
        AboutLink(title: "Terms", url: "https://getlazzy.app/terms")
        AboutLink(title: "Contact", url: "mailto:hello@getlazzy.app")
        // AboutLink(title: "© 2025 Goloak Vrindavan Inc.", url: nil)
      }
      .padding(.top, 40)
    }
    .padding(.top, 40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct AboutLink: View {
  let title: String
  let url: String?
  @State private var isHovered = false
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    if url != nil {
      Button(action: {
        if let url = URL(string: url!) {
          NSWorkspace.shared.open(url)
        }
      }) {
        Text(title)
          .font(.appFont(size: 12, weight: .medium))
          .foregroundColor(isHovered ? theme.accentColor : theme.textColor.opacity(0.4))
          .underline(isHovered)
      }
      .buttonStyle(.plain)
      .onHover { isHovered = $0 }
    } else {
      Text(title)
        .font(.appFont(size: 12, weight: .medium))
        .foregroundColor(theme.textColor.opacity(0.4))
    }
  }
}
