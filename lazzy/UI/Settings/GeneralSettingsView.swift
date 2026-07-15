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

  private var agentOptions: [(model: String, isAvailable: Bool)] {
    let capabilities = wsManager.agentCapabilities
    if capabilities.isEmpty {
      return [("Codex", true), ("Claude", false), ("Grok", false)]
    }
    return capabilities.map { ($0.displayName, $0.installed) }
  }

  private var selectedCapability: AgentCapability? {
    wsManager.agentCapabilities.first { $0.id == selectedAgent }
  }

  private var modelOptions: [(model: String, isAvailable: Bool)] {
    [("Default", true)] + (selectedCapability?.models.map { ($0.displayName, true) } ?? [])
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        runtimeSection
        appBehaviorSection
        instructionsSection
        debugSection
        Spacer(minLength: 40)
      }
      .padding(.bottom, 24)
    }
    .onAppear {
      wsManager.requestCapabilities()
      refreshSelectedModel()
    }
    .onChange(of: wsManager.agentCapabilities) {
      refreshSelectedModel()
    }
  }

  private var debugSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Debug Settings")
        .font(.appFont(size: 14, weight: .semibold))
        .foregroundColor(theme.textColor)

      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Reset Onboarding")
            .font(.appFont(size: 13, weight: .medium))
            .foregroundColor(theme.textColor)
          Text("Clears the onboarding completed flag and presents the onboarding screen.")
            .font(.appFont(size: 11))
            .foregroundColor(theme.secondaryTextColor)
        }
        Spacer()
        Button("Reset Onboarding") {
          AppCoordinator.shared?.resetOnboarding()
        }
        .font(.appFont(size: 12, weight: .medium))
        .buttonStyle(.plain)
        .foregroundColor(.red)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.1))
        .cornerRadius(theme.borderRadius / 2)
        .overlay(
          RoundedRectangle(cornerRadius: theme.borderRadius / 2)
            .stroke(Color.red.opacity(0.3), lineWidth: 0.5)
        )
      }
      .padding(16)
      .background(theme.backgroundColor.opacity(0.3))
      .cornerRadius(theme.borderRadius)
      .overlay(
        RoundedRectangle(cornerRadius: theme.borderRadius)
          .stroke(theme.textColor.opacity(0.1), lineWidth: 0.5)
      )
    }
  }

  private var runtimeSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Detach Runtime")
        .font(.custom("Sick-Regular", size: 24))
        .foregroundColor(theme.textColor)

      Text("Detach uses local agents already signed in on this Mac. No hosted provider keys, credits, billing, or model registry are used.")
        .font(.appFont(size: 12))
        .foregroundColor(theme.secondaryTextColor)
        .lineSpacing(3)

      VStack(alignment: .leading, spacing: 14) {
        HStack {
          statusDot(isActive: wsManager.isConnected)
          Text(wsManager.isConnected ? "Runtime connected" : "Runtime disconnected")
            .font(.appFont(size: 13, weight: .medium))
            .foregroundColor(theme.textColor)
          Spacer()
          Button("Refresh") {
            wsManager.requestCapabilities()
          }
          .font(.appFont(size: 12, weight: .medium))
          .buttonStyle(.plain)
          .foregroundColor(theme.accentColor)
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("ACTIVE AGENT")
            .font(.appFont(size: 11, weight: .bold))
            .foregroundColor(theme.secondaryTextColor)

          ModelMenu(
            modelsWithAvailability: agentOptions,
            selectedOption: Binding(
              get: { displayName(for: selectedAgent) },
              set: { newValue in
                selectedAgent = agentId(for: newValue)
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
        }

        if !modelOptions.dropFirst().isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("MODEL")
              .font(.appFont(size: 11, weight: .bold))
              .foregroundColor(theme.secondaryTextColor)

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
          }
        }

        ForEach(wsManager.agentCapabilities) { capability in
          AgentCapabilityRow(capability: capability)
        }
      }
      .padding(16)
      .background(theme.backgroundColor.opacity(0.3))
      .cornerRadius(theme.borderRadius)
      .overlay(
        RoundedRectangle(cornerRadius: theme.borderRadius)
          .stroke(theme.textColor.opacity(0.1), lineWidth: 0.5)
      )
    }
  }

  private var appBehaviorSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("App Behavior")
        .font(.appFont(size: 14, weight: .semibold))
        .foregroundColor(theme.textColor)

      SettingsToggleRow(
        title: "Launch at Login",
        subtitle: "Automatically start Detach when you log in to your Mac",
        isOn: $launchAtLogin
      )
      .background(theme.backgroundColor.opacity(0.3))
      .cornerRadius(theme.borderRadius)
      .overlay(
        RoundedRectangle(cornerRadius: theme.borderRadius)
          .stroke(theme.textColor.opacity(0.1), lineWidth: 0.5)
      )
    }
  }

  private var instructionsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Default Instructions")
        .font(.appFont(size: 14, weight: .semibold))
        .foregroundColor(theme.textColor)

      TextEditor(text: $systemPrompt)
        .font(.appFont(size: 13))
        .foregroundColor(theme.textColor)
        .padding(8)
        .frame(height: 120)
        .background(theme.inputBackgroundColor)
        .cornerRadius(theme.borderRadius / 1.5)
        .overlay(
          RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
            .stroke(theme.borderColor, lineWidth: 0.5)
        )
        .scrollContentBackground(.hidden)

      Text("These instructions are sent with Detach quick actions and normal chat turns.")
        .font(.appFont(size: 11))
        .foregroundColor(theme.secondaryTextColor.opacity(0.8))
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
