import AppKit
import SwiftUI

struct FloatingChatToolbarView: View {
  @Binding var fastMode: Bool
  @Binding var inputText: String
  @Binding var selectedMode: String
  let canSend: Bool

  @ObservedObject var wsManager: WebSocketManager
  @ObservedObject var controller: FloatingWindowController

  var onAttach: () -> Void
  var onHistory: () -> Void
  var onNewChat: () -> Void
  var onStartIndexing: () -> Void
  var onVoiceInput: () -> Void
  var onSend: () -> Void
  var isRevising = false
  var branches: [ConversationBranch] = []
  var onSelectBranch: (String) -> Void = { _ in }

  @ObservedObject private var theme = ThemeManager.shared
  @State private var selectedModelName = "Default"

  private var agentOptions: [(model: String, isAvailable: Bool)] {
    let capabilities = wsManager.agentCapabilities
    if capabilities.isEmpty {
      // An empty list means capability discovery is still in flight. Do not
      // present the local providers as locked while the runtime is probing
      // their CLIs; the authoritative availability arrives in the response.
      return AgentProvider.loadingOptions
    }
    return capabilities.map { ($0.displayName, $0.installed) }
  }

  private var selectedCapability: AgentCapability? {
    wsManager.agentCapabilities.first { $0.id == controller.selectedAgent }
  }

  private var selectedAgentModel: AgentModelCapability? {
    guard let capability = selectedCapability else { return nil }
    if let selectedModel = controller.selectedModel {
      if let model = capability.models.first(where: { $0.id == selectedModel }) {
        return model
      }
    }
    if let defaultModel = capability.defaultModel {
      return capability.models.first { $0.id == defaultModel }
    }
    return capability.models.first
  }

  var body: some View {
    HStack(spacing: 8) {
        AgentModelMenu(
          agents: agentOptions,
          selectedAgentName: selectedMode,
          onSelectAgent: selectAgent,
          models: selectedCapability?.models ?? [],
          selectedModelID: controller.selectedModel,
          selectedModelName: $selectedModelName,
          selectedModel: selectedAgentModel,
          selectedEffort: controller.selectedModelSettings?.reasoningEffort,
          agentID: controller.selectedAgent,
          isLoading: wsManager.isLoadingCapabilities || wsManager.agentCapabilities.isEmpty,
          onSelectModel: selectAgentModel,
          onSelectReasoningEffort: selectReasoningEffort,
          onReset: { selectReasoningEffort(nil) },
          contextSummary: wsManager.lastContextSummary,
          isNewConversation: wsManager.currentConversationId == nil && !isRevising && !wsManager.isStreaming
        )
      if branches.count > 1 {
        ComposerBranchSwitcher(branches: branches, currentID: wsManager.currentConversationId,
          isBusy: wsManager.isStreaming, onSelect: onSelectBranch)
      }

      Spacer()

      if FeatureFlags.voiceModeEnabled {
        Button(action: onVoiceInput) {
          Image(systemName: voiceIcon)
            .font(.appFont(size: 13, weight: .medium))
            .foregroundColor(voiceColor)
            .frame(width: 26, height: 26)
        }
        .buttonStyle(ComposerButtonStyle())
        .help(voiceHelpText)
      }

      // History button - triggers external window
      Button(action: {
        onHistory()
      }) {
        Image(systemName: "clock.arrow.circlepath")
          .font(.appFont(size: 13, weight: .medium))
          .foregroundColor(theme.secondaryTextColor)
          .frame(width: 26, height: 26)
      }
      .buttonStyle(ComposerButtonStyle())
      .help("Conversation history")
      .accessibilityLabel("Conversation history")

      // New Chat button
      Button(action: {
        onNewChat()
      }) {
        Image(systemName: "plus.bubble")
          .font(.appFont(size: 13, weight: .medium))
          .foregroundColor(theme.secondaryTextColor)
          .frame(width: 26, height: 26)
      }
      .buttonStyle(ComposerButtonStyle())
      .help("New chat")
      .accessibilityLabel("New chat")

      if wsManager.isStreaming {
        Button(action: { wsManager.stopStreaming() }) {
          Image(systemName: "stop.circle.fill")
            .font(.appFont(size: 21))
            .foregroundColor(theme.textColor)
            .frame(width: 28, height: 28)
        }
        .buttonStyle(ComposerButtonStyle())
        .help("Stop generating")
        .accessibilityLabel("Stop generating")
      } else {
        Button(action: onSend) {
          Image(systemName: "arrow.up.circle.fill")
            .font(.appFont(size: 22))
            .foregroundColor(canSend ? theme.textColor : theme.textColor.opacity(0.3))
            .frame(width: 28, height: 28)
        }
        .buttonStyle(ComposerButtonStyle())
        .disabled(!canSend)
        .help(isRevising ? "Send edited message in a new branch" : "Send message")
        .accessibilityLabel(isRevising ? "Send edited message in new branch" : "Send message")
      }

    }
    .padding(.horizontal, 16)
    .padding(.top, 1)
    .padding(.bottom, 11)
    .onAppear {
      selectedMode = displayName(for: controller.selectedAgent)
      refreshSelectedModel()
    }
    .onChange(of: wsManager.agentCapabilities) {
      selectedMode = displayName(for: controller.selectedAgent)
      refreshSelectedModel()
    }
    .onChange(of: controller.selectedAgent) {
      selectedMode = displayName(for: controller.selectedAgent)
      refreshSelectedModel()
    }
    .onChange(of: controller.selectedModel) {
      refreshSelectedModel()
    }
  }

  private func refreshSelectedModel() {
    guard let capability = selectedCapability else {
      selectedModelName = "Default"
      return
    }

    if let id = controller.selectedModel,
       let model = capability.models.first(where: { $0.id == id }) {
      selectedModelName = model.displayName
    } else {
      selectedModelName = "Default"
      if !capability.models.isEmpty, controller.selectedModel != nil {
        controller.selectedModel = nil
        DetachSettings.setSelectedModel(nil, for: controller.selectedAgent)
      }
    }

    let persistedSettings = DetachSettings.modelSettings(
      for: controller.selectedAgent,
      model: controller.selectedModel
    )
    let supportedEfforts = Set(selectedAgentModel?.reasoningEfforts ?? [])
    if let selectedEffort = persistedSettings?.reasoningEffort,
       !supportedEfforts.isEmpty,
       !supportedEfforts.contains(selectedEffort) {
      controller.selectedModelSettings = nil
      DetachSettings.setModelSettings(
        nil,
        for: controller.selectedAgent,
        model: controller.selectedModel
      )
    } else {
      controller.selectedModelSettings = persistedSettings
    }
  }

  private func selectAgent(_ newAgent: String) {
    let agentId = agentId(for: newAgent)
    selectedMode = newAgent
    controller.selectedAgent = agentId
    DetachSettings.selectedAgent = agentId
    controller.selectedModel = DetachSettings.selectedModel(for: agentId)
    controller.selectedModelSettings = DetachSettings.modelSettings(
      for: agentId,
      model: controller.selectedModel
    )
    refreshSelectedModel()
  }

  private func selectAgentModel(_ newModel: String?) {
    controller.selectedModel = newModel
    DetachSettings.setSelectedModel(newModel, for: controller.selectedAgent)
    controller.selectedModelSettings = DetachSettings.modelSettings(
      for: controller.selectedAgent,
      model: newModel
    )
    selectedModelName = selectedCapability?.models.first(where: { $0.id == newModel })?.displayName ?? "Default"
    refreshSelectedModel()
  }

  private func selectReasoningEffort(_ effort: String?) {
    let selectedModel = selectedAgentModel
    let normalizedEffort = effort?.lowercased() == "none" || effort?.lowercased() == "auto"
      ? nil
      : effort

    // A setting selected while the model menu is on Default needs an explicit
    // model ID so every adapter can apply it to the same model the user saw.
    if controller.selectedModel == nil, let selectedModel, normalizedEffort != nil {
      controller.selectedModel = selectedModel.id
      DetachSettings.setSelectedModel(selectedModel.id, for: controller.selectedAgent)
      selectedModelName = selectedModel.displayName
    }

    let settings = normalizedEffort.map { AgentModelSettings(reasoningEffort: $0) }
    controller.selectedModelSettings = settings
    DetachSettings.setModelSettings(
      settings,
      for: controller.selectedAgent,
      model: controller.selectedModel
    )
  }

  private var voiceIcon: String {
    switch controller.voiceDictationState {
    case .listening:
      return "mic.fill"
    case .processing:
      return "waveform"
    case .requestingPermission:
      return "mic.badge.plus"
    case .idle, .failed:
      return "mic"
    }
  }

  private var voiceColor: Color {
    switch controller.voiceDictationState {
    case .listening, .processing:
      return theme.accentColor
    case .failed:
      return .red
    case .idle, .requestingPermission:
      return theme.secondaryTextColor
    }
  }

  private var voiceHelpText: String {
    switch controller.voiceDictationState {
    case .idle, .failed:
      return "Start voice input (or hold Fn)"
    case .requestingPermission, .listening:
      return "Stop voice input"
    case .processing:
      return "Finishing voice transcription"
    }
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
}
