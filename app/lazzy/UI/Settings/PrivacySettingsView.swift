import SwiftUI

struct PrivacySettingsView: View {
  @ObservedObject var wsManager: WebSocketManager
  @ObservedObject private var theme = ThemeManager.shared
  @StateObject private var cache = HistoryCacheSettings()
  @StateObject private var permissions = PermissionsManager()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        SettingsPageHeader(title: "Privacy & data",
          subtitle: "Choose what Detach caches on this Mac and when it can access your screen.")
        GitSnapshotSettingsView(connected: wsManager.isConnected)
        VStack(alignment: .leading, spacing: 10) {
          SettingsSectionHeader(title: "Local conversation cache",
            subtitle: "Your agents own the original chats. Detach can cache message text for search and offline reading.")
          SettingsCard {
            SettingsToggleRow(title: "Cache message text on this Mac",
              subtitle: "Turn off to remove cached text and read chats directly from their providers. Titles and project labels remain available.",
              isOn: Binding(get: { cache.status?.enabled ?? true }, set: { enabled in
                Task { await cache.setEnabled(enabled); wsManager.refreshHistoryListing() }
              }))
              .disabled(cache.status == nil || cache.isBusy || !wsManager.isConnected)
            SettingsCardDivider()
            SettingsRow(title: cacheSummary,
              subtitle: "Clearing this cache preserves provider chats, hidden-chat choices, and integration settings.") {
              Button(cache.isBusy ? "Updating…" : "Clear cached text") {
                Task { await cache.clear(); wsManager.refreshHistoryListing() }
              }
              .disabled(cache.status?.cachedMessages == 0 || cache.status == nil || cache.isBusy || !wsManager.isConnected)
            }
          }
          if let notice = cache.notice { statusText(notice) }
          if let error = cache.error {
            statusText(error)
            Button("Try again") { Task { await cache.load() } }.font(.appFont(size: 11))
          }
          if !wsManager.isConnected { statusText("Reconnect Detach to view or change its local search cache.") }
        }

        VStack(alignment: .leading, spacing: 10) {
          SettingsSectionHeader(title: "Screen access",
            subtitle: "Chat works without screen permissions. Detach asks when you first use the corresponding feature.")
          SettingsCard {
            SettingsRow(title: "Accessibility", subtitle: "Read selected text and interact with native apps when requested.") {
              Button(permissions.hasAccessibilityPermission ? "Allowed" : "Enable") {
                permissions.requestAccessibilityPermission()
              }.disabled(permissions.hasAccessibilityPermission)
            }
            SettingsCardDivider()
            SettingsRow(title: "Screen recording", subtitle: "Capture a screen or app when you ask an agent to inspect it.") {
              Button(permissions.hasScreenCapturePermission ? "Allowed" : "Enable") {
                permissions.requestScreenCapturePermission()
              }.disabled(permissions.hasScreenCapturePermission)
            }
          }
        }

        SettingsCard {
          VStack(alignment: .leading, spacing: 12) {
            Text("Where your requests go").font(.appFont(size: 13, weight: .semibold))
            Text("Your selected agent handles prompts and attachments through its own account and services. Provider storage and retention settings still apply.")
            Text("If you enable Auto with your own Jev key, new-message routing requests go to TypeSafe as explained in Auto router settings. Optional integrations use the services you connect.")
            Text("Provider histories, older Detach-only archives, composer drafts and attachment references have separate storage. Chats you have open remain in memory until closed.")
          }
          .font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
          .fixedSize(horizontal: false, vertical: true).padding(16)
        }
      }.padding(.bottom, 24)
    }
    .tint(theme.textColor)
    .task { if wsManager.isConnected { await cache.load() } }
    .onChange(of: wsManager.isConnected) { _, connected in
      if connected { Task { await cache.load() } }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      permissions.checkPermissions()
    }
  }

  private var cacheSummary: String {
    guard let status = cache.status else { return "Local cache" }
    let size = ByteCountFormatter.string(fromByteCount: Int64(status.bytes), countStyle: .file)
    return "\(status.cachedMessages) cached messages in \(status.cachedChats) chats · \(size) of message text"
  }

  private func statusText(_ text: String) -> some View {
    Text(text).font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
      .fixedSize(horizontal: false, vertical: true)
  }
}
