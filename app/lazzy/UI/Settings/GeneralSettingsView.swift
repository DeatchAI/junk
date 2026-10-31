//
//  GeneralSettingsView.swift
//  lazzy
//
//  Detach runtime and app behavior settings.
//

import SwiftUI

struct GeneralSettingsView: View {
  @ObservedObject var wsManager: WebSocketManager
  @ObservedObject private var theme = ThemeManager.shared
  @ObservedObject private var appPresentation = AppPresentationController.shared

  @StateObject private var loginItem = LaunchAtLoginController()
  @AppStorage(AppSettings.notchLiveActivitiesKey) private var notchLiveActivitiesEnabled = true
  @AppStorage(AppSettings.activityIslandPlacementKey)
  private var activityIslandPlacement = ActivityIslandPlacement.defaultPlacement.rawValue
  @AppStorage("ai_system_prompt") private var systemPrompt = AISettings.defaultSystemPrompt
  @AppStorage("detach_selected_agent") private var selectedAgent = DetachSettings.defaultAgent
  @State private var selectedModelName = "Default"
  @State private var permissionMode = AgentPermissionMode.native

  private var agentOptions: [(model: String, isAvailable: Bool)] {
    let capabilities = wsManager.agentCapabilities
    if capabilities.isEmpty {
      // Capability discovery is asynchronous. An empty list is not evidence
      // that the local providers are missing, so keep them selectable until
      // the runtime returns the authoritative result.
      return AgentProvider.loadingOptions
    }
    return capabilities.map { ($0.displayName, $0.installed) }
  }

  private var selectedCapability: AgentCapability? {
    wsManager.agentCapabilities.first { $0.id == selectedAgent }
  }

  private var modelOptions: [(model: String, isAvailable: Bool)] {
    let models = selectedCapability?.models ?? []
    if !models.isEmpty {
      return [("Default", true)] + models.map { ($0.displayName, true) }
    }
    if wsManager.isLoadingCapabilities || wsManager.agentCapabilities.isEmpty {
      return [("Default", true), ("Loading models…", false)]
    }
    return [("Default", true), ("No models detected", false)]
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        SettingsPageHeader(
          title: "General",
          subtitle: "Choose the agent Detach uses and configure its everyday behavior."
        )
        runtimeSection
        if selectedAgent == "cursor" {
          CursorProviderSettingsView(wsManager: wsManager)
        }
        ProviderHistorySettingsView(manager: wsManager, state: wsManager.providerHistory)
        appBehaviorSection
        instructionsSection
        debugSection
        Spacer(minLength: 20)
      }
      .padding(.bottom, 24)
    }
    .onAppear {
      loginItem.refresh()
      AISettings.retireDefaultPersona()
      permissionMode = DetachSettings.permissionMode(for: selectedAgent)
      wsManager.requestCapabilities()
      refreshSelectedModel()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      loginItem.refresh()
    }
    .onChange(of: wsManager.agentCapabilities) {
      refreshSelectedModel()
    }
    .onChange(of: selectedAgent) {
      permissionMode = DetachSettings.permissionMode(for: selectedAgent)
    }
    .onReceive(NotificationCenter.default.publisher(for: DetachSettings.permissionModeDidChange)) { notification in
      guard notification.userInfo?["agent"] as? String == selectedAgent else { return }
      let current = DetachSettings.permissionMode(for: selectedAgent)
      if permissionMode != current { permissionMode = current }
    }
  }

  private var debugSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      SettingsSectionHeader(title: "Developer")

      SettingsCard {
        SettingsRow(
          title: "Reset onboarding",
          subtitle: "Show agent setup and shortcuts again"
        ) {
        Button("Reset Onboarding") {
          AppCoordinator.shared?.resetOnboarding()
        }
        .font(.appFont(size: 11, weight: .medium))
        .buttonStyle(.plain)
        .foregroundColor(theme.textColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(theme.textColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
      }
    }
  }

  private var runtimeSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      SettingsSectionHeader(
        title: "Agent runtime",
        subtitle: "Use your coding-agent, Cursor, fx, or OpenCode account."
      )

      SettingsCard {
        HStack {
          statusDot(isActive: wsManager.isConnected)
          Text(wsManager.isConnected ? "Runtime connected" : "Runtime disconnected")
            .font(.appFont(size: 12, weight: .medium))
            .foregroundColor(theme.textColor)
          Spacer()
          Button("Refresh") {
            wsManager.requestCapabilities()
          }
          .font(.appFont(size: 11, weight: .medium))
          .buttonStyle(.plain)
          .foregroundColor(theme.textColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)

        SettingsCardDivider()

        SettingsRow(
          title: "Active agent",
          subtitle: "The coding harness Detach uses for new conversations"
        ) {
          ModelMenu(
            modelsWithAvailability: agentOptions,
            selectedOption: Binding(
              get: { displayName(for: selectedAgent) },
              set: { newValue in
                let nextAgent = agentId(for: newValue)
                selectedAgent = nextAgent
                DetachSettings.selectedAgent = selectedAgent
                wsManager.updateAISettings(
                  agent: selectedAgent,
                  model: nil,
                  temperature: nil,
                  maxSteps: nil,
                  systemPrompt: nil
                )
                refreshSelectedModel()
              }
            ),
            showsProviderLogos: true
          )
        }

        SettingsCardDivider()

        AgentReadinessRow(agentID: selectedAgent)
        SettingsCardDivider()

        SettingsRow(
          title: "Model",
          subtitle: "Saved separately for each agent"
        ) {
          ModelMenu(
            modelsWithAvailability: modelOptions,
            selectedOption: $selectedModelName,
            onSelect: { newValue in
              let model = selectedCapability?.models.first(where: { $0.displayName == newValue })?.id
              DetachSettings.setSelectedModel(model, for: selectedAgent)
              wsManager.updateAISettings(
                agent: selectedAgent,
                model: model,
                temperature: nil,
                maxSteps: nil,
                systemPrompt: nil
              )
            }
          )
        }

        SettingsCardDivider()
        SettingsRow(
          title: "Permissions",
          subtitle: AgentPermissionMode.supportsOverrides(for: selectedAgent)
            ? permissionMode.detail : "Managed by this agent's native configuration."
        ) {
          if AgentPermissionMode.supportsOverrides(for: selectedAgent) {
            AppSelect(title: "Permissions", selection: $permissionMode,
              options: AgentPermissionMode.allCases.map {
                .init(title: $0.title(for: selectedAgent), value: $0)
              })
            .onChange(of: permissionMode) {
              DetachSettings.setPermissionMode(permissionMode, for: selectedAgent)
            }
          } else {
            Text("Agent default").font(.appFont(size: 12)).foregroundColor(theme.secondaryTextColor)
          }
        }

        if !wsManager.agentCapabilities.isEmpty {
          SettingsCardDivider()

          VStack(spacing: 0) {
            ForEach(Array(wsManager.agentCapabilities.enumerated()), id: \.element.id) { index, capability in
              AgentCapabilityRow(capability: capability)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

              if index < wsManager.agentCapabilities.count - 1 {
                SettingsCardDivider()
              }
            }
          }
        }
      }
    }
  }

  private var appBehaviorSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      SettingsSectionHeader(title: "App behavior")

      SettingsCard {
        SettingsToggleRow(
          title: "Launch at login",
          subtitle: "Start Detach automatically when you sign in to your Mac",
          isOn: Binding(get: { loginItem.isEnabled }, set: loginItem.setEnabled)
        )

        SettingsCardDivider()

        SettingsRow(
          title: "App location",
          subtitle: appPresentation.mode.subtitle
        ) {
          AppSelect(
            title: "App location",
            selection: Binding(get: { appPresentation.mode }, set: appPresentation.select),
            options: AppPresentationMode.allCases.map { .init(title: $0.title, value: $0) },
            menuWidth: 220
          )
        }

        if loginItem.needsApproval {
          SettingsRow(title: "Approval needed", subtitle: "Finish enabling Detach in Login Items.") {
            Button("Open Login Items") { loginItem.openLoginItems() }
          }
        }
        if let error = loginItem.error {
          Text(error).font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
            .padding(.horizontal, 16).padding(.bottom, 12)
        }

        SettingsCardDivider()

        SettingsToggleRow(
          title: "Live activities",
          subtitle: "Show running agents, completions, and approval requests at the screen edge",
          isOn: $notchLiveActivitiesEnabled
        )

        SettingsCardDivider()

        SettingsRow(
          title: "Live activity position",
          subtitle: "Use a side to keep the top notch free for other apps"
        ) {
          AppSelect(title: "Live activity position", selection: $activityIslandPlacement,
            options: ActivityIslandPlacement.allCases.map { .init(title: $0.title, value: $0.rawValue) })
          .disabled(!notchLiveActivitiesEnabled)
        }
      }
    }
  }

  private var instructionsSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      SettingsSectionHeader(
        title: "Additional instructions",
        subtitle: "Optional instructions you choose to share with agents. Leave empty to use their native defaults."
      )

      SettingsCard {
        AppTextEditor(title: "Additional instructions", text: $systemPrompt, height: 88).padding(10)
      }
    }
  }

  private func statusDot(isActive: Bool) -> some View {
    Circle()
      .fill(theme.textColor.opacity(isActive ? 1 : 0.35))
      .frame(width: 8, height: 8)
  }

  private func displayName(for id: String) -> String {
    wsManager.agentCapabilities.first(where: { $0.id == id })?.displayName
      ?? fallbackAgentDisplayName(for: id)
  }

  private func agentId(for displayName: String) -> String {
    wsManager.agentCapabilities.first(where: { $0.displayName == displayName })?.id
      ?? AgentProvider.identifier(for: displayName)
  }

  private func fallbackAgentDisplayName(for id: String) -> String {
    AgentProvider.displayName(for: id)
  }

  private func refreshSelectedModel() {
    guard let id = DetachSettings.selectedModel(for: selectedAgent),
          let model = selectedCapability?.models.first(where: { $0.id == id }) else {
      selectedModelName = "Default"
      if selectedCapability?.models.isEmpty == false {
        DetachSettings.setSelectedModel(nil, for: selectedAgent)
      }
      return
    }
    selectedModelName = model.displayName
  }
}

struct AgentCapabilityRow: View {
  let capability: AgentCapability
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: capability.installed ? "checkmark.circle.fill" : "exclamationmark.circle")
        .foregroundColor(theme.textColor.opacity(capability.installed ? 1 : 0.35))
        .font(.appFont(size: 14))

      VStack(alignment: .leading, spacing: 2) {
        Text(capability.displayName)
          .font(.appFont(size: 13, weight: .medium))
          .foregroundColor(theme.textColor)

        if let authHint = capability.authHint, !authHint.isEmpty {
          Text(authHint)
            .font(.appFont(size: 11))
            .foregroundColor(theme.textColor.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Spacer()
    }
  }
}

#Preview {
  GeneralSettingsView(wsManager: WebSocketManager())
    .frame(width: 500, height: 600)
    .background(Color.black)
}
