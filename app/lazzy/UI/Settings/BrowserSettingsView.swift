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
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 8) {
        Text("Browser Automation")
          .font(.custom("Sick-Regular", size: 24))
          .foregroundColor(theme.textColor)

        Text("Detach works in your existing signed-in Chrome profile through the Detach Browser Agent extension.")
          .font(.appFont(size: 13))
          .lineSpacing(4)
          .foregroundColor(theme.secondaryTextColor)
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          statusCard
          Divider().opacity(0.1)
          sectionLabel("HOW IT WORKS")
          infoRow(
            icon: "person.text.rectangle",
            title: "Your signed-in browser",
            detail: "Detach reuses the focused Chrome window, including its existing logins, cookies, subscriptions, and site preferences."
          )
          infoRow(
            icon: "rectangle.stack",
            title: "Task-scoped tabs",
            detail: "Detach tracks the active tab and tabs opened by the task. It never launches a separate browser profile or closes your Chrome window."
          )
          infoRow(
            icon: "checkmark.shield",
            title: "Verified browser actions",
            detail: "Frames, forms, uploads, downloads, documents, visual widgets, and page transitions are handled through the extension with direct verification."
          )

          Divider().opacity(0.1)
          sectionLabel("SETUP")
          Text("Load the Detach Browser Agent extension, grant access to the sites you want Detach to use, then open its popup once to connect it.")
            .font(.appFont(size: 12))
            .lineSpacing(4)
            .foregroundColor(theme.secondaryTextColor)

          HStack(spacing: 10) {
            Button("Open Chrome Extensions") {
              NSWorkspace.shared.open(URL(string: "chrome://extensions")!)
            }
            .buttonStyle(.borderedProminent)

            Button("Show extension folder") {
              showBrowserExtensionFolder()
            }
            .buttonStyle(.bordered)
          }

          Spacer(minLength: 40)
        }
      }
    }
  }

  private var statusCard: some View {
    HStack(spacing: 12) {
      Image(systemName: "person.crop.circle.badge.checkmark")
        .font(.system(size: 20, weight: .medium))
        .foregroundColor(theme.accentColor)
        .frame(width: 28)

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
        .fill(wsManager.isConnected ? Color.green : Color.orange)
        .frame(width: 8, height: 8)
    }
    .padding(14)
    .background(theme.inputBackgroundColor)
    .overlay(
      RoundedRectangle(cornerRadius: theme.borderRadius)
        .stroke(theme.borderColor, lineWidth: 0.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: theme.borderRadius))
  }

  private func sectionLabel(_ text: String) -> some View {
    Text(text)
      .font(.appFont(size: 11, weight: .bold))
      .foregroundColor(theme.secondaryTextColor)
  }

  private func infoRow(icon: String, title: String, detail: String) -> some View {
    HStack(alignment: .top, spacing: 11) {
      Image(systemName: icon)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(theme.accentColor)
        .frame(width: 20)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.appFont(size: 13, weight: .medium))
          .foregroundColor(theme.textColor)
        Text(detail)
          .font(.appFont(size: 11))
          .lineSpacing(3)
          .foregroundColor(theme.secondaryTextColor.opacity(0.82))
      }
    }
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
