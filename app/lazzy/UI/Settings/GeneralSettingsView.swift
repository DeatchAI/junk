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

  @AppStorage("launch_at_login") private var launchAtLogin = false
  @AppStorage("ai_system_prompt") private var systemPrompt = AISettings.defaultSystemPrompt
  @AppStorage("detach_selected_agent") private var selectedAgent = DetachSettings.defaultAgent
  @State private var selectedModelName = "Default"
  @StateObject private var hostedSubscription = HostedSubscriptionManager.shared

  private var agentOptions: [(model: String, isAvailable: Bool)] {
    let capabilities = wsManager.agentCapabilities
    if capabilities.isEmpty {
      return [("Codex", true), ("Claude", false), ("Grok", false), ("OpenCode", false), ("Hosted AI", true)]
    }
    return capabilities.map { ($0.displayName, $0.id == "hosted" || $0.installed) }
  }

  private var selectedCapability: AgentCapability? {
    wsManager.agentCapabilities.first { $0.id == selectedAgent }
  }

  private var modelOptions: [(model: String, isAvailable: Bool)] {
    [("Default", true)] + (selectedCapability?.models.map { ($0.displayName, true) } ?? [])
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        SettingsPageHeader(
          title: "General",
          subtitle: "Choose the agent Detach uses and configure its everyday behavior."
        )
        runtimeSection
        appBehaviorSection
        instructionsSection
        debugSection
        Spacer(minLength: 20)
      }
      .padding(.bottom, 24)
    }
    .onAppear {
      wsManager.requestCapabilities()
      refreshSelectedModel()
    }
    .task {
      await hostedSubscription.refresh()
    }
    .onChange(of: wsManager.agentCapabilities) {
      refreshSelectedModel()
    }
  }

  private var debugSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      SettingsSectionHeader(title: "Developer")

      SettingsCard {
        SettingsRow(
          title: "Reset onboarding",
          subtitle: "Show the welcome and permissions flow again"
        ) {
        Button("Reset Onboarding") {
          AppCoordinator.shared?.resetOnboarding()
        }
        .font(.appFont(size: 11, weight: .medium))
        .buttonStyle(.plain)
        .foregroundColor(.red)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
      }
    }
  }

  private var runtimeSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      SettingsSectionHeader(
        title: "Agent runtime",
        subtitle: "Use your existing coding-agent or OpenCode account, or choose Detach-hosted models."
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
          .foregroundColor(theme.accentColor)
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
                if nextAgent == "hosted" && !hostedSubscription.canUseHostedAI {
                  HostedPricingWindowController.shared.show()
                  return
                }
                selectedAgent = nextAgent
                DetachSettings.selectedAgent = selectedAgent
                wsManager.updateAISettings(
                  agent: selectedAgent,
                  model: nil,
                  imageModel: nil,
                  temperature: nil,
                  maxSteps: nil,
                  systemPrompt: nil
                )
                refreshSelectedModel()
              }
            )
          )
          .frame(width: 170)
        }

        if !modelOptions.dropFirst().isEmpty {
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
                  imageModel: nil,
                  temperature: nil,
                  maxSteps: nil,
                  systemPrompt: nil
                )
              }
            )
            .frame(width: 170)
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
    VStack(alignment: .leading, spacing: 10) {
      SettingsSectionHeader(title: "App behavior")

      SettingsCard {
        SettingsToggleRow(
          title: "Launch at login",
          subtitle: "Start Detach automatically when you sign in to your Mac",
          isOn: $launchAtLogin
        )
      }
    }
  }

  private var instructionsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      SettingsSectionHeader(
        title: "Default instructions",
        subtitle: "Applied to quick actions and regular chat turns."
      )

      SettingsCard {
        TextEditor(text: $systemPrompt)
          .font(.appFont(size: 12))
          .foregroundColor(theme.textColor)
          .padding(12)
          .frame(height: 112)
          .scrollContentBackground(.hidden)
          .background(Color.clear)
      }
    }
  }

  private func statusDot(isActive: Bool) -> some View {
    Circle()
      .fill(isActive ? Color.green : Color.orange)
      .frame(width: 8, height: 8)
  }

  private func displayName(for id: String) -> String {
    wsManager.agentCapabilities.first(where: { $0.id == id })?.displayName
      ?? fallbackAgentDisplayName(for: id)
  }

  private func agentId(for displayName: String) -> String {
    wsManager.agentCapabilities.first(where: { $0.displayName == displayName })?.id
      ?? displayName.lowercased()
  }

  private func fallbackAgentDisplayName(for id: String) -> String {
    switch id {
    case "claude": return "Claude"
    case "grok": return "Grok"
    case "opencode": return "OpenCode"
    case "hosted": return "Hosted AI"
    default: return "Codex"
    }
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
        .foregroundColor(capability.installed ? .green : .orange)
        .font(.appFont(size: 14))

      VStack(alignment: .leading, spacing: 3) {
        Text(capability.displayName)
          .font(.appFont(size: 13, weight: .medium))
          .foregroundColor(theme.textColor)

        Text(capability.installed ? capability.executablePath ?? "Installed" : capability.authHint ?? "Not installed")
          .font(.appFont(size: 11))
          .foregroundColor(theme.secondaryTextColor)
          .lineLimit(2)
      }

      Spacer()
    }
  }
}

struct SettingsToggleRow: View {
  let title: String
  let subtitle: String?
  @Binding var isOn: Bool

  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.appFont(size: 13))
          .foregroundColor(theme.textColor)

        if let subtitle = subtitle {
          Text(subtitle)
            .font(.appFont(size: 11))
            .foregroundColor(theme.textColor.opacity(0.6))
        }
      }

      Spacer()

      Toggle("", isOn: $isOn)
        .toggleStyle(SwitchToggleStyle(tint: theme.accentColor))
        .labelsHidden()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}

#Preview {
  GeneralSettingsView(wsManager: WebSocketManager())
    .frame(width: 500, height: 600)
    .background(Color.black)
}
