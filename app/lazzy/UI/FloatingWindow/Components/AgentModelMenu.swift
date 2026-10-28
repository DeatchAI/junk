import SwiftUI

struct AgentModelMenu: View {
  let agents: [(model: String, isAvailable: Bool)]
  let selectedAgentName: String
  let onSelectAgent: (String) -> Void
  let models: [AgentModelCapability]
  let selectedModelID: String?
  @Binding var selectedModelName: String
  let selectedModel: AgentModelCapability?
  let selectedEffort: String?
  let agentID: String
  let isLoading: Bool
  let onSelectModel: (String?) -> Void
  let onSelectReasoningEffort: (String?) -> Void
  let onReset: () -> Void
  var contextSummary: ChatContextSummary? = nil
  var isNewConversation = true

  @State private var isPopoverPresented = false
  @ObservedObject private var theme = ThemeManager.shared
  @ObservedObject private var router = AutoRouter.shared

  private var contentRevision: AnyHashable {
    var values = [selectedModelID ?? "", selectedModelName, selectedEffort ?? "", agentID, String(isLoading), String(router.configuration.enabled), String(router.configuration.fixedChoice.isAutomatic), String(isNewConversation)]
    values.append(contextSummary?.runId ?? "")
    for agent in agents { values.append(contentsOf: [agent.model, String(agent.isAvailable)]) }
    for model in models {
      values.append(contentsOf: [model.id, model.displayName, model.reasoningLabel ?? ""])
      values.append(contentsOf: model.reasoningEfforts ?? [])
    }
    return AnyHashable(values)
  }

  private var autoSelected: Bool { isNewConversation && router.configuration.enabled && router.configuration.fixedChoice.isAutomatic }

  private var menuPanel: some View {
    AgentModelMenuPanel(
      agents: agents,
      selectedAgentName: selectedAgentName,
      onSelectAgent: onSelectAgent,
      models: models,
      selectedModelID: selectedModelID,
      selectedModelName: selectedModelName,
      selectedModel: selectedModel,
      selectedEffort: selectedEffort,
      agentID: agentID,
      isLoading: isLoading,
      onSelectModel: onSelectModel,
      onSelectReasoningEffort: onSelectReasoningEffort,
      onReset: onReset,
      contextSummary: contextSummary,
      isNewConversation: isNewConversation
    )
  }

  var body: some View {
    Button(action: { isPopoverPresented.toggle() }) {
      ComposerBrainIcon()
        .frame(width: 15, height: 15)
        .foregroundStyle(theme.secondaryTextColor)
        .frame(width: 26, height: 26)
    }
    .buttonStyle(ComposerButtonStyle())
    .help(autoSelected ? "Auto" : "\(selectedAgentName) · \(selectedModelName)")
    .accessibilityLabel("Agent and model")
    .accessibilityValue(autoSelected ? "Auto" : "\(selectedAgentName), \(selectedModelName)")
    .background {
      DropdownPanelAnchor(
        isPresented: $isPopoverPresented,
        menuWidth: 236,
        menu: menuPanel,
        contentRevision: contentRevision
      )
    }
  }
}

private struct AgentModelMenuPanel: View {
  let agents: [(model: String, isAvailable: Bool)]
  let selectedAgentName: String
  let onSelectAgent: (String) -> Void
  let models: [AgentModelCapability]
  let selectedModelID: String?
  let selectedModelName: String
  let selectedModel: AgentModelCapability?
  let selectedEffort: String?
  let agentID: String
  let isLoading: Bool
  let onSelectModel: (String?) -> Void
  let onSelectReasoningEffort: (String?) -> Void
  let onReset: () -> Void
  let contextSummary: ChatContextSummary?
  let isNewConversation: Bool

  @State private var isAgentSubmenuPresented = false
  @State private var isModelSubmenuPresented = false
  @State private var isReasoningSubmenuPresented = false
  @State private var isPermissionSubmenuPresented = false
  @State private var isContextPresented = false
  @State private var permissionMode = AgentPermissionMode.native
  @ObservedObject private var theme = ThemeManager.shared
  @ObservedObject private var router = AutoRouter.shared

  private var autoSelected: Bool { isNewConversation && router.configuration.enabled && router.configuration.fixedChoice.isAutomatic }

  private var settingsLabel: String {
    if let label = selectedModel?.reasoningLabel, !label.isEmpty {
      return label
    }
    if agentID == "claude" || selectedModel?.id.lowercased().hasPrefix("anthropic/") == true {
      return "Thinking"
    }
    return "Effort"
  }

  private var reasoningEfforts: [String] {
    selectedModel?.reasoningEfforts ?? []
  }

  private var hasReasoningSettings: Bool {
    !reasoningEfforts.isEmpty
  }

  private var selectedEffortLabel: String {
    guard let selectedEffort else { return "Auto" }
    return reasoningEffortLabel(selectedEffort)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      AgentNestedMenuRow(
        title: "Agent",
        value: autoSelected ? "Auto" : selectedAgentName,
        menuWidth: 220,
        isPresented: $isAgentSubmenuPresented,
        opensOnHover: true,
        menu: AgentProviderChoicesMenu(agents: agents, selectedAgentName: selectedAgentName,
          autoSelected: autoSelected, showsAuto: isNewConversation, onSelectAuto: {
            router.configuration.fixedChoice = RouterPreset()
            router.configuration.enabled = true
            isAgentSubmenuPresented = false
          }) { agent in
          if isNewConversation { router.configuration.enabled = false }
          isAgentSubmenuPresented = false
          onSelectAgent(agent)
        },
        contentRevision: AnyHashable([selectedAgentName, String(autoSelected), String(isNewConversation)]
          + agents.flatMap { [$0.model, String($0.isAvailable)] })
      )

      if !autoSelected { AgentNestedMenuRow(
        title: "Model",
        value: selectedModelName,
        menuWidth: 220,
        isPresented: $isModelSubmenuPresented,
        opensOnHover: true,
        menu: AgentModelChoicesMenu(
          models: models,
          selectedModelID: selectedModelID,
          isLoading: isLoading,
          onSelect: { modelID in
            isModelSubmenuPresented = false
            onSelectModel(modelID)
          }
        ),
        contentRevision: AnyHashable([selectedModelID ?? "", String(isLoading)]
          + models.flatMap { [$0.id, $0.displayName] })
      ) }

      if !autoSelected && hasReasoningSettings {
        AgentNestedMenuRow(
          title: settingsLabel,
          value: selectedEffortLabel,
          menuWidth: 220,
          isPresented: $isReasoningSubmenuPresented,
          opensOnHover: true,
          menu: AgentReasoningChoicesMenu(
            efforts: reasoningEfforts,
            selectedEffort: selectedEffort,
            onSelect: { effort in
              isReasoningSubmenuPresented = false
              onSelectReasoningEffort(effort)
            }
          ),
          contentRevision: AnyHashable([selectedEffort ?? ""] + reasoningEfforts)
        )
      }

      Divider()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)

      if AgentPermissionMode.supportsOverrides(for: agentID) {
        AgentNestedMenuRow(
          title: "Permissions", value: permissionMode.title(for: agentID), menuWidth: 210,
          isPresented: $isPermissionSubmenuPresented,
          menu: AgentPermissionChoicesView(agentID: agentID, selected: permissionMode) { mode in
            permissionMode = mode
            DetachSettings.setPermissionMode(mode, for: agentID)
            isPermissionSubmenuPresented = false
          },
          contentRevision: permissionMode.rawValue
        )
      }

      AgentNestedMenuRow(
        title: "Context", value: "Last message", menuWidth: 292,
        isPresented: $isContextPresented,
        menu: AgentContextDetailView(summary: contextSummary),
        contentRevision: contextSummary?.runId
      )

      Button(action: onReset) {
        HStack(spacing: 8) {
          Image(systemName: "arrow.counterclockwise")
            .font(.appFont(size: 11, weight: .medium))
          Text("Reset to default")
            .font(.appFont(size: 11))
          Spacer(minLength: 8)
        }
        .foregroundColor(selectedEffort == nil ? theme.secondaryTextColor.opacity(0.45) : theme.secondaryTextColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
      }
      .buttonStyle(ComposerButtonStyle())
      .disabled(selectedEffort == nil)
    }
    .padding(6)
    .frame(width: 236, alignment: .leading)
    .themedSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(theme.textColor.opacity(theme.mode == .liquidGlass ? 0 : 0.1), lineWidth: 0.5)
        .allowsHitTesting(false)
    }
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .onAppear { permissionMode = DetachSettings.permissionMode(for: agentID) }
    .onChange(of: agentID) { permissionMode = DetachSettings.permissionMode(for: agentID) }
    .onReceive(NotificationCenter.default.publisher(for: DetachSettings.permissionModeDidChange)) { notification in
      guard notification.userInfo?["agent"] as? String == agentID else { return }
      let current = DetachSettings.permissionMode(for: agentID)
      if permissionMode != current { permissionMode = current }
    }
  }

}

private struct AgentNestedMenuRow<MenuContent: View>: View {
  let title: String
  let value: String
  let menuWidth: CGFloat
  @Binding var isPresented: Bool
  var opensOnHover: Bool = false
  let menu: MenuContent
  var contentRevision: AnyHashable? = nil

  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Button(action: { isPresented = opensOnHover ? true : !isPresented }) {
      HStack(spacing: 8) {
        Text(title)
          .font(.appFont(size: 12))
          .foregroundColor(theme.textColor)
        Spacer(minLength: 8)
        Text(value)
          .font(.appFont(size: 12))
          .foregroundColor(theme.secondaryTextColor)
          .lineLimit(1)
        Image(systemName: "chevron.right")
          .font(.appFont(size: 10, weight: .semibold))
          .foregroundColor(theme.secondaryTextColor)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .contentShape(Rectangle())
    }
    .buttonStyle(ComposerButtonStyle())
    .onHover { hovering in
      if opensOnHover && hovering && !isPresented {
        isPresented = true
      }
    }
    .background {
      DropdownPanelAnchor(
        isPresented: $isPresented,
        menuWidth: menuWidth,
        menu: menu,
        placement: .trailing,
        opensOnHover: opensOnHover,
        contentRevision: contentRevision
      )
    }
  }
}

private struct AgentModelChoicesMenu: View {
  let models: [AgentModelCapability]
  let selectedModelID: String?
  let isLoading: Bool
  let onSelect: (String?) -> Void

  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 0) {
        AgentNestedChoiceRow(
          title: "Default",
          isSelected: selectedModelID == nil,
          isAvailable: true,
          action: { onSelect(nil) }
        )

        ForEach(models) { model in
          AgentNestedChoiceRow(
            title: model.displayName,
            isSelected: selectedModelID == model.id,
            isAvailable: true,
            action: { onSelect(model.id) }
          )
        }

        if models.isEmpty {
          AgentNestedChoiceRow(
            title: isLoading ? "Loading models…" : "No models detected",
            isSelected: false,
            isAvailable: false,
            action: {}
          )
        }
      }
      .padding(6)
    }
    .frame(width: 220)
    .frame(maxHeight: 260)
    .themedSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(theme.textColor.opacity(theme.mode == .liquidGlass ? 0 : 0.1), lineWidth: 0.5)
        .allowsHitTesting(false)
    }
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

}

private struct AgentReasoningChoicesMenu: View {
  let efforts: [String]
  let selectedEffort: String?
  let onSelect: (String?) -> Void

  @ObservedObject private var theme = ThemeManager.shared

  private var options: [String] {
    ["none"] + efforts.filter { value in
      let normalized = value.lowercased()
      return normalized != "none" && normalized != "auto"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(options, id: \.self) { effort in
        AgentNestedChoiceRow(
          title: reasoningEffortLabel(effort),
          isSelected: (selectedEffort ?? "none").lowercased() == effort.lowercased(),
          isAvailable: true,
          action: { onSelect(effort == "none" ? nil : effort) }
        )
      }
    }
    .padding(6)
    .frame(width: 220, alignment: .leading)
    .themedSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(theme.textColor.opacity(theme.mode == .liquidGlass ? 0 : 0.1), lineWidth: 0.5)
        .allowsHitTesting(false)
    }
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

}

private struct AgentNestedChoiceRow: View {
  let title: String
  let isSelected: Bool
  let isAvailable: Bool
  let action: () -> Void

  @State private var isHovered = false
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Text(title)
          .font(.appFont(size: 12, weight: isSelected && isAvailable ? .medium : .regular))
          .foregroundColor(textColor)
          .lineLimit(1)
        Spacer(minLength: 8)
        if isSelected && isAvailable {
          Image(systemName: "checkmark")
            .font(.appFont(size: 10, weight: .bold))
            .foregroundColor(textColor)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(backgroundFill)
      )
    }
    .buttonStyle(ComposerButtonStyle())
    .disabled(!isAvailable)
    .onHover { isHovered = $0 }
  }

  private var textColor: Color {
    if isSelected && isAvailable { return theme.backgroundColor }
    if !isAvailable { return theme.textColor.opacity(0.4) }
    return theme.textColor
  }

  private var backgroundFill: Color {
    if isSelected && isAvailable { return theme.textColor }
    if isHovered && isAvailable { return theme.textColor.opacity(0.06) }
    return .clear
  }
}

private func reasoningEffortLabel(_ effort: String) -> String {
  switch effort.lowercased() {
  case "none", "auto": return "Auto"
  case "low", "minimal": return "Light"
  case "medium": return "Medium"
  case "high": return "High"
  case "xhigh": return "Extra high"
  case "max": return "Max"
  case "ultra": return "Ultra"
  default: return effort.replacingOccurrences(of: "_", with: " ").capitalized
  }
}
