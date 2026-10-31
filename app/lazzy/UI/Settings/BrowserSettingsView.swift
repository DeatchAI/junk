//
//  BrowserSettingsView.swift
//  lazzy
//
//  Signed-in Chrome browser integration.
//

import SwiftUI

struct BrowserSettingsView: View {
  @ObservedObject var wsManager: WebSocketManager
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        SettingsPageHeader(
          title: "Browser",
          subtitle: "Use your signed-in Chrome profile through the Detach Browser Agent extension."
        )

        statusCard

        VStack(alignment: .leading, spacing: 10) {
          SettingsSectionHeader(title: "How it works")

          SettingsCard {
            infoRow(
              icon: "person.text.rectangle",
              title: "Your signed-in browser",
              detail: "Detach reuses the focused Chrome window, including its existing logins, cookies, subscriptions, and site preferences."
            )
            SettingsCardDivider()
            infoRow(
              icon: "rectangle.stack",
              title: "Task-scoped tabs",
              detail: "Detach tracks the active tab and tabs opened by the task. It never launches a separate browser profile or closes your Chrome window."
            )
            SettingsCardDivider()
            infoRow(
              icon: "checkmark.shield",
              title: "Verified browser actions",
              detail: "Frames, forms, uploads, downloads, documents, visual widgets, and page transitions are handled through the extension with direct verification."
            )
          }
        }

        VStack(alignment: .leading, spacing: 10) {
          SettingsSectionHeader(title: "Setup")

          SettingsCard {
            VStack(alignment: .leading, spacing: 15) {
              Text("Load the Detach Browser Agent extension, grant access to the sites you want Detach to use, then open its popup once to connect it.")
                .font(.appFont(size: 11.5))
                .lineSpacing(3)
                .foregroundColor(theme.secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)

              HStack(spacing: 8) {
                Button("Open Chrome Extensions") {
                  NSWorkspace.shared.open(URL(string: "chrome://extensions")!)
                }
                .buttonStyle(AppButtonStyle(kind: .primary))
                .tint(theme.textColor)

                Button("Show extension folder") {
                  showBrowserExtensionFolder()
                }
                .buttonStyle(AppButtonStyle())
                .tint(theme.textColor)
              }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }

        Spacer(minLength: 20)
      }
      .padding(.bottom, 24)
    }
  }

  private var statusCard: some View {
    SettingsCard {
      HStack(spacing: 12) {
        Image(systemName: "person.crop.circle.badge.checkmark")
          .font(.system(size: 19, weight: .medium))
          .foregroundColor(theme.textColor.opacity(0.82))
          .frame(width: 26)

        VStack(alignment: .leading, spacing: 4) {
          Text("Signed-in Chrome")
            .font(.appFont(size: 13, weight: .semibold))
            .foregroundColor(theme.textColor)
          Text(wsManager.isConnected ? "Detach runtime connected" : "Start Detach, then open the browser extension popup")
            .font(.appFont(size: 11))
            .foregroundColor(theme.secondaryTextColor)
        }

        Spacer()

        Circle()
          .fill(theme.textColor.opacity(wsManager.isConnected ? 0.82 : 0.3))
          .frame(width: 7, height: 7)
      }
      .padding(16)
    }
  }

  private func infoRow(icon: String, title: String, detail: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(theme.textColor.opacity(0.76))
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.appFont(size: 12.5, weight: .medium))
          .foregroundColor(theme.textColor)
        Text(detail)
          .font(.appFont(size: 11))
          .lineSpacing(2)
          .foregroundColor(theme.secondaryTextColor)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
  }

  private func showBrowserExtensionFolder() {
    guard let resourceURL = Bundle.main.resourceURL else { return }
    let extensionURL = resourceURL.appendingPathComponent("chrome-extension", isDirectory: true)
    NSWorkspace.shared.activateFileViewerSelecting([extensionURL])
  }
}

#Preview {
  BrowserSettingsView(wsManager: WebSocketManager())
    .padding()
    .frame(width: 520, height: 720)
    .background(Color(white: 0.1))
}
