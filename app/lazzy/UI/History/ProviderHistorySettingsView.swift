import SwiftUI

struct ProviderHistorySettingsView: View {
  @ObservedObject var manager: WebSocketManager
  @ObservedObject var state: ProviderHistoryState
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      SettingsSectionHeader(title: "Provider history",
        subtitle: "Your agents own your chats. Detach keeps a searchable local cache, not a separate conversation store.")
      SettingsCard {
        SettingsRow(title: state.statusText, subtitle: "Saved chats are discovered automatically. Provider storage and retention policies still apply.") {
          Button("Refresh") { state.refresh(using: manager) }
            .disabled(state.isSyncing || !manager.isConnected)
        }
        SettingsCardDivider()
        SettingsRow(title: "Hidden chats", subtitle: "Hiding in Detach never deletes the original conversation") {
          Button("Restore hidden") { state.restoreHidden(using: manager) }.disabled(!manager.isConnected)
        }
      }
      if !state.notices.isEmpty {
        AppDisclosure("Provider availability") {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(state.notices, id: \.self) { Text($0) }
          }.padding(.top, 8)
        }.font(.appFont(size: 11)).foregroundStyle(.secondary)
      }
    }
  }
}
