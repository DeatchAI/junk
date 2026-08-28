import AppKit
import SwiftUI

struct FloatingChatToolbarView: View {
  @Binding var fastMode: Bool
  @Binding var inputText: String
  @Binding var selectedMode: String
  @Binding var outputMode: ComposerOutputMode
  @Binding var selectedMediaModelID: String
  @Binding var mediaConfig: MediaGenerationConfig
  let canSend: Bool

  @ObservedObject var wsManager: WebSocketManager
  @ObservedObject var controller: FloatingWindowController

  var onAttach: () -> Void
  var onHistory: () -> Void
  var onNewChat: () -> Void
  var onStartIndexing: () -> Void
  var onVoiceInput: () -> Void
  var onSend: () -> Void

  @ObservedObject private var theme = ThemeManager.shared
  @State private var selectedModelName = "Default"
  @State private var isConfigurationPresented = false
  @StateObject private var hostedSubscription = HostedSubscriptionManager.shared

  private var agentOptions: [(model: String, isAvailable: Bool)] {
    let capabilities = wsManager.agentCapabilities
    if capabilities.isEmpty {
      // An empty list means capability discovery is still in flight. Do not
      // present the local providers as locked while the runtime is probing
      // their CLIs; the authoritative availability arrives in the response.
      return [("Codex", true), ("Claude", true), ("Grok", true), ("fx", true), ("OpenCode", true), ("Detach Cloud", true)]
    }
    return capabilities.map { ($0.displayName, $0.id == "hosted" || $0.installed) }
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

  private var mediaModel: MediaModelCapability? {
    wsManager.mediaModels.first { $0.id == selectedMediaModelID }
      ?? wsManager.mediaModels.first { $0.kind == outputMode.rawValue.lowercased() }
  }

  var body: some View {
    HStack(spacing: 8) {
      // Mode, agent, and model selection stay visible. These are the choices
      // people make most often; only media-specific controls belong in the tray.
      ModelMenu(
        modelsWithAvailability: ComposerOutputMode.allCases.map { ($0.rawValue, true) },
        selectedOption: outputModeSelection,
        fontSize: 10,
        horizontalPadding: 6,
        verticalPadding: 6,
        iconSize: 8,
        backgroundColor: .clear,
        borderRadius: theme.borderRadius,
        showBorder: false,
        opensOnHover: true
      )

      if outputMode == .agent {
        ModelMenu(
          modelsWithAvailability: agentOptions,
          selectedOption: $selectedMode,
          onSelect: selectAgent,
          fontSize: 10,
          horizontalPadding: 6,
          verticalPadding: 6,
          iconSize: 8,
          backgroundColor: .clear,
          borderRadius: theme.borderRadius,
          showBorder: false,
          unavailableHelp: "This provider is not available on this Mac.",
          opensOnHover: true
        )

        AgentModelMenu(
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
          fontSize: 10,
          horizontalPadding: 6,
          verticalPadding: 6,
          iconSize: 8,
          backgroundColor: .clear,
          borderRadius: theme.borderRadius,
          showBorder: false,
          opensOnHover: true
        )
      } else {
        CustomMenu(
          options: mediaModelsForCurrentMode.map(\.displayName),
          selectedOption: mediaModelSelection,
          onSelect: selectMediaModel,
          fontSize: 10,
          horizontalPadding: 6,
          verticalPadding: 6,
          iconSize: 8,
          backgroundColor: .clear,
          borderRadius: theme.borderRadius,
          showBorder: false,
          opensOnHover: true
        )

        configurationButton
      }

      Spacer()

      // Fast mode toggle
      // Button(action: {
      //   fastMode.toggle()
      // }) {
      //   Image(systemName: fastMode ? "bolt.fill" : "bolt")
      //     .font(.appFont(size: 14, weight: .medium))
      //     .foregroundColor(fastMode ? .orange : theme.accentColor)
      // }
      // .buttonStyle(.plain)
      // .help(
      //   fastMode
      //     ? "Fast Mode: ON (⚡ Faster responses, fewer features)"
      //     : "Fast Mode: OFF (Full features)")

      // Commented out as we already have the attachement menu appear on "@" symbol.
      // File and folder attachment button
      // Button(action: onAttach) {
      //   Image(systemName: "paperclip")
      //     .font(.appFont(size: 13, weight: .medium))
      //     .foregroundColor(theme.secondaryTextColor)
      //     .frame(width: 26, height: 26)
      // }
      // .buttonStyle(.plain)
      // .help("Attach files or folders")

      if FeatureFlags.voiceModeEnabled {
        Button(action: onVoiceInput) {
          Image(systemName: voiceIcon)
            .font(.appFont(size: 13, weight: .medium))
            .foregroundColor(voiceColor)
            .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
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
      .buttonStyle(.plain)
      .help("Conversation History")

      // New Chat button
      Button(action: {
        onNewChat()
      }) {
        Image(systemName: "plus.bubble")
          .font(.appFont(size: 13, weight: .medium))
          .foregroundColor(theme.secondaryTextColor)
          .frame(width: 26, height: 26)
      }
      .buttonStyle(.plain)
      .help("New Chat")

      // Expand/Shrink button
      Button(action: {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
          controller.toggleExpansion()
        }
      }) {
        Image(
          systemName: controller.isExpanded
            ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        )
        .font(.appFont(size: 13, weight: .medium))
        .foregroundColor(theme.secondaryTextColor)
        .frame(width: 26, height: 26)
      }
      .buttonStyle(.plain)
      .help(controller.isExpanded ? "Shrink to Float" : "Expand composer")

      if wsManager.isStreaming {
        Button(action: { wsManager.stopStreaming() }) {
          Image(systemName: "stop.circle.fill")
            .font(.appFont(size: 21))
            .foregroundColor(.red)
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help("Stop generating")
      } else {
        Button(action: onSend) {
          Image(systemName: "arrow.up.circle.fill")
            .font(.appFont(size: 22))
            .foregroundColor(canSend ? theme.accentColor : theme.textColor.opacity(0.4))
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
      }

    }
    .padding(.horizontal, 12)
    .padding(.top, 1)
    .padding(.bottom, 9)
    .onAppear {
      selectedMode = displayName(for: controller.selectedAgent)
      refreshSelectedModel()
    }
    .task {
      await hostedSubscription.refresh()
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

  private var configurationButton: some View {
    Button {
      isConfigurationPresented.toggle()
    } label: {
      Image(systemName: "gearshape")
        .font(.appFont(size: 13, weight: .medium))
        .foregroundColor(isConfigurationPresented ? theme.accentColor : theme.secondaryTextColor)
        .frame(width: 26, height: 26)
        .background {
          if isConfigurationPresented {
            Circle().fill(theme.accentColor.opacity(0.12))
          }
        }
    }
    .buttonStyle(.plain)
    .help("Image or video configuration")
    .background {
      DropdownPanelAnchor(
        isPresented: $isConfigurationPresented,
        menuWidth: 296,
        menu: MediaConfigurationTray(
          model: mediaModel,
          config: $mediaConfig
        )
      )
    }
  }

  private func selectAgent(_ newAgent: String) {
    let agentId = agentId(for: newAgent)
    if agentId == "hosted" && !hostedSubscription.canUseHostedAI {
      selectedMode = displayName(for: controller.selectedAgent)
      HostedPricingWindowController.shared.show()
      return
    }
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

  private var mediaModelsForCurrentMode: [MediaModelCapability] {
    wsManager.mediaModels.filter { $0.kind == outputMode.rawValue.lowercased() }
  }

  private var mediaModelSelection: Binding<String> {
    Binding(
      get: { mediaModel?.displayName ?? "Choose model" },
      set: { displayName in
        guard let model = mediaModelsForCurrentMode.first(where: { $0.displayName == displayName }) else { return }
        selectedMediaModelID = model.id
      }
    )
  }

  private func selectMediaModel(_ displayName: String) {
    guard let model = mediaModelsForCurrentMode.first(where: { $0.displayName == displayName }) else { return }
    selectedMediaModelID = model.id
    mediaConfig = model.defaults
  }

  private var outputModeSelection: Binding<String> {
    Binding(
      get: { outputMode.rawValue },
      set: { rawValue in
        guard let mode = ComposerOutputMode(rawValue: rawValue) else { return }
        if mode != .agent && !hostedSubscription.canUseHostedAI {
          HostedPricingWindowController.shared.show()
          return
        }
        outputMode = mode
        if mode != .agent {
          wsManager.listMediaModels()
        }
      }
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
      ?? displayName.lowercased()
  }

  private func fallbackAgentDisplayName(for id: String) -> String {
    switch id {
    case "claude": return "Claude"
    case "grok": return "Grok"
    case "fx": return "fx"
    case "opencode": return "OpenCode"
    case "hosted": return "Detach Cloud"
    default: return "Codex"
    }
  }
}
