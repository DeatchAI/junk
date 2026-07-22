import Auth
import Supabase
import SwiftUI
import SDWebImageSwiftUI

private let providerLogos: [Provider: String] = [
  .github: "https://supabase.com/dashboard/img/icons/github-icon.svg",
  .google: "https://supabase.com/dashboard/img/icons/google-icon.svg",
  .discord: "https://supabase.com/dashboard/img/icons/discord-icon.svg",
  .twitter: "https://supabase.com/dashboard/img/icons/twitter-icon.svg"
]

struct SocialLoginButton: View {
  let title: String
  let provider: Auth.Provider

  @StateObject private var auth = AuthManager.shared
  @ObservedObject private var theme = ThemeManager.shared
  @State private var isHovered = false

  var providerIcon: String {
    providerLogos[provider]!
  }

  var body: some View {
    Button(action: {
      Task {
        await auth.signInWithOAuth(provider: provider)
      }
    }) {
      HStack(spacing: 12) {
        if let url = URL(string: providerIcon), providerIcon.contains("://") {
        WebImage(
          url: url, options: [],
          context: [.imageThumbnailPixelSize: CGSize.zero]
        )
        .resizable()
        .frame(width: 16, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 8))
      } else {
        ZStack {
          RoundedRectangle(cornerRadius: 8)
            .fill(theme.textColor.opacity(0.05))
            .frame(width: 16, height: 16)
          Text(providerIcon)
            .font(.appFont(size: 20))
        }
      }

        Text(title)
          .font(.appFont(size: 13, weight: .medium))
          .foregroundColor(theme.textColor)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
      .background(theme.textColor.opacity(isHovered ? 0.08 : 0.04))
      .cornerRadius(theme.borderRadius)
      .overlay(
        RoundedRectangle(cornerRadius: theme.borderRadius)
          .stroke(theme.textColor.opacity(0.1), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }
}
