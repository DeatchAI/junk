import SwiftUI

struct RouterKeyEditor: View {
  @ObservedObject var router: AutoRouter
  @ObservedObject private var theme = ThemeManager.shared
  @State private var apiKey = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Your Jev API key").font(.appFont(size: 13, weight: .medium))
      AppTextField(router.hasKey ? "A key is saved in Keychain" : "Paste your TypeSafe API key", text: $apiKey, secure: true).accessibilityLabel("Jev API key")
      HStack(spacing: 6) {
        Button("Save key") {
          router.saveKey(apiKey)
          if router.hasKey { apiKey = "" }
        }.disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button(router.isVerifying ? "Checking…" : "Test connection") { Task { await router.verifyKey() } }
          .disabled(!router.hasKey || router.isVerifying)
        if router.hasKey { Button("Remove key") { router.removeKey() } }
        Spacer()
        Link("Get a key", destination: URL(string: "https://console.typesafe.ai")!)
      }.font(.appFont(size: 11))
      if let status = router.keyStatus { Text(status).font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor) }
    }
    .buttonStyle(AppButtonStyle())
    .onDisappear { apiKey = "" }
  }
}
