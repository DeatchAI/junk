import SwiftUI

struct PrivacySettingsView: View {
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Privacy Philosophy.")
        .font(.custom("Sick-Regular", size: 24))
        .foregroundColor(theme.textColor)
        .padding(.bottom, 24)

      VStack(alignment: .leading, spacing: 32) {
        PrivacySection(
          number: "01",
          title: "Our Philosophy",
          content:
            "Privacy is not a feature; it is our foundation. We believe that your digital assistant should be a private extension of your own mind, not a data collection point."
        )

        PrivacySection(
          number: "02",
          title: "Local-First",
          content:
            "Detach does not store your chat history, files, or interactions on our servers. All conversation data is stored exclusively on your local macOS device."
        )

        PrivacySection(
          number: "03",
          title: "Zero Telemetry",
          content:
            "We do not employ any telemetry or usage tracking systems. We do not monitor how you use the app or features. Your usage remains completely private."
        )

        VStack(alignment: .leading, spacing: 12) {
          Text("For the full legal details, please visit our website.")
            .font(.appFont(size: 13))
            .foregroundColor(theme.textColor.opacity(0.5))

          Button(action: {
            if let url = URL(string: "https://getlazzy.app/privacy") {
              NSWorkspace.shared.open(url)
            }
          }) {
            Text("Read Full Privacy Policy →")
              .font(.appFont(size: 13, weight: .bold))
              .foregroundColor(theme.accentColor)
          }
          .buttonStyle(.plain)
        }
        .padding(.top, 8)
      }

      Spacer()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct PrivacySection: View {
  let number: String
  let title: String
  let content: String
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Text(number)
          .font(.system(size: 10, weight: .bold, design: .monospaced))
          .foregroundColor(theme.accentColor)

        Text(title.uppercased())
          .font(.system(size: 10, weight: .bold, design: .monospaced))
          .foregroundColor(theme.textColor.opacity(0.4))
          .tracking(1)
      }

      Text(content)
        .font(.appFont(size: 14))
        .foregroundColor(theme.textColor.opacity(0.7))
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
