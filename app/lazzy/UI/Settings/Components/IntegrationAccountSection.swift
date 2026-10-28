import SwiftUI

struct IntegrationAccountSection: View {
  @ObservedObject private var theme = ThemeManager.shared
  @ObservedObject private var account = AuthManager.shared
  @State private var isPresented = false

  var body: some View {
    SettingsCard {
      SettingsRow(title: "Optional integration account",
        subtitle: "Sign in to connect supported services. Your agents use their own accounts.") {
        Button(account.isAuthenticated ? "Manage account" : "Sign in") { isPresented = true }
          .font(.appFont(size: 11))
      }
    }
    .tint(theme.textColor)
    .sheet(isPresented: $isPresented) {
      VStack(alignment: .trailing, spacing: 12) {
        Button("Done") { isPresented = false }
        AccountSettingsView()
      }
      .padding(24).frame(width: 560, height: 500).background(theme.backgroundColor)
        .foregroundStyle(theme.textColor).tint(theme.textColor)
    }
  }
}
