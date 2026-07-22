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
  var onSend: () -> Void

  @ObservedObject private var theme = ThemeManager.shared
  @State private var selectedModelName = "Default"

  private var agentOptions: [(model: String, isAvailable: Bool)] {
    let capabilities = wsManager.agentCapabilities
    if capabilities.isEmpty {
      return [("Codex", true), ("Claude", false), ("Grok", false)]
    }
    return capabilities.map { ($0.displayName, $0.installed) }
  }

  private var selectedCapability: AgentCapability? {
    wsManager.agentCapabilities.first { $0.id == controller.selectedAgent }
  }

  private var modelOptions: [(model: String, isAvailable: Bool)] {
    [("Default", true)] + (selectedCapability?.models.map { ($0.displayName, true) } ?? [])
  }

  var body: some View {
    HStack(spacing: 8) {

      // Agent selector
      ModelMenu(
        modelsWithAvailability: agentOptions,
        selectedOption: $selectedMode,
        onSelect: { newAgent in
          let agentId = agentId(for: newAgent)
          controller.selectedAgent = agentId
          controller.selectedModel = nil
          refreshSelectedModel()
        },
        fontSize: 10,
        horizontalPadding: 6,
        verticalPadding: 6,
        iconSize: 8,
        backgroundColor: .clear,
        borderRadius: theme.borderRadius,
        showBorder: false
      )

      if !modelOptions.dropFirst().isEmpty {
        ModelMenu(
          modelsWithAvailability: modelOptions,
          selectedOption: $selectedModelName,
          onSelect: { newModel in
            let model = selectedCapability?.models.first(where: { $0.displayName == newModel })?.id
            controller.selectedModel = model
          },
          fontSize: 10,
          horizontalPadding: 6,
          verticalPadding: 6,
          iconSize: 8,
          backgroundColor: .clear,
          borderRadius: theme.borderRadius,
          showBorder: false
        )
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

      // File and folder attachment button
      Button(action: onAttach) {
        Image(systemName: "paperclip")
          .font(.appFont(size: 14, weight: .medium))
          .foregroundColor(theme.textColor)
      }
      .buttonStyle(.plain)
      .help("Attach files or folders")

      // History button - triggers external window
      Button(action: {
        onHistory()
      }) {
        Image(systemName: "clock.arrow.circlepath")
          .font(.appFont(size: 14, weight: .medium))
          .foregroundColor(theme.textColor)
      }
      .buttonStyle(.plain)
      .help("Conversation History")

      // New Chat button
      Button(action: {
        onNewChat()
      }) {
        Image(systemName: "plus.bubble")
          .font(.appFont(size: 14, weight: .medium))
          .foregroundColor(theme.textColor)
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
        .font(.appFont(size: 14, weight: .medium))
        .foregroundColor(theme.textColor)
      }
      .buttonStyle(.plain)
      .help(controller.isExpanded ? "Shrink to Float" : "Expand to Chat")

      if wsManager.isStreaming {
        Button(action: { wsManager.stopStreaming() }) {
          Image(systemName: "stop.circle.fill")
            .font(.appFont(size: 18))
            .foregroundColor(.red)
        }
        .buttonStyle(.plain)
        .help("Stop generating")
      } else {
        Button(action: onSend) {
          Image(systemName: "arrow.up.circle.fill")
            .font(.appFont(size: 18))
            .foregroundColor(canSend ? theme.accentColor : theme.textColor.opacity(0.4))
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
      }

    }
    .padding(.horizontal, 10)
    .padding(.bottom, 10)
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
  }

  private func refreshSelectedModel() {
    guard let id = controller.selectedModel,
          let model = selectedCapability?.models.first(where: { $0.id == id }) else {
      selectedModelName = "Default"
      return
    }
    selectedModelName = model.displayName
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
}
