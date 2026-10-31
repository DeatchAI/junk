import SwiftUI

struct SettingsView: View {
  @ObservedObject var wsManager: WebSocketManager
  var onRunWorkflow: ((SavedWorkflow) -> Void)? = nil
  var launchIntent: SettingsLaunchIntent?
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var theme = ThemeManager.shared
  @State private var selectedTab: String
  @State private var sidebarVisible = true

  init(wsManager: WebSocketManager, onRunWorkflow: ((SavedWorkflow) -> Void)? = nil,
       launchIntent: SettingsLaunchIntent? = nil, initialTab: String = "general") {
    self.wsManager = wsManager
    self.onRunWorkflow = onRunWorkflow
    self.launchIntent = launchIntent
    _selectedTab = State(initialValue: launchIntent?.settingsTab ?? initialTab)
  }

  var body: some View {
    VStack(spacing: 0) {
      SettingsWindowToolbar(sidebarVisible: $sidebarVisible, onClose: { dismiss() })
      HStack(spacing: 0) {
        if sidebarVisible {
          SettingsSidebar(selection: $selectedTab)
          Rectangle().fill(theme.textColor.opacity(0.07)).frame(width: 0.5)
        }
        page
          .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 16)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }
    .frame(width: 920, height: 680)
    .foregroundStyle(theme.textColor)
    .buttonStyle(AppButtonStyle())
    .themedSurface(in: RoundedRectangle(cornerRadius: theme.borderRadius, style: .continuous))
    .clipShape(RoundedRectangle(cornerRadius: theme.borderRadius, style: .continuous))
  }

  @ViewBuilder private var page: some View {
    switch selectedTab {
    case "account": AccountSettingsView()
    case "license": LicenseSettingsView()
    case "general": GeneralSettingsView(wsManager: wsManager)
    case "machines": RemoteMachinesSettingsView()
    case "router": RouterSettingsView(wsManager: wsManager)
    case "appearance": AppearanceSettingsView()
    case "shortcuts": ShortcutsSettingsView()
    case "workflows":
      WorkflowsSettingsView(wsManager: wsManager, onRunWorkflow: onRunWorkflow,
        startInCreateMode: launchIntent == .createWorkflow)
    case "mcp":
      MCPSettingsContentView(wsManager: wsManager, startInAddServerMode: launchIntent == .connectMCP)
    case "browser": BrowserSettingsView(wsManager: wsManager)
    case "messages": MessagesRemoteSettingsView()
    case "secrets": SecretsSettingsView()
    case "privacy": PrivacySettingsView(wsManager: wsManager)
    case "about": AboutSettingsView()
    default: EmptyView()
    }
  }
}

#Preview {
  SettingsView(wsManager: WebSocketManager())
}
