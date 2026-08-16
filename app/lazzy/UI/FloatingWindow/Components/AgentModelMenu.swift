import SwiftUI

struct AgentModelMenu: View {
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

  var fontSize: CGFloat = 13
  var horizontalPadding: CGFloat = 12
  var verticalPadding: CGFloat = 6
  var iconSize: CGFloat = 10
  var backgroundColor: Color? = nil
  var borderRadius: CGFloat? = nil
  var showBorder: Bool = true
  var opensOnHover: Bool = false

  @State private var isPopoverPresented = false
  @State private var isHovered = false
  @ObservedObject private var theme = ThemeManager.shared

  private var effectiveBackgroundColor: Color {
    backgroundColor ?? theme.inputBackgroundColor
  }

  private var effectiveBorderRadius: CGFloat {
    borderRadius ?? (theme.borderRadius / 1.5)
  }

  var body: some View {
    Button(action: { isPopoverPresented.toggle() }) {
      HStack(spacing: 8) {
        Text(selectedModelName)
          .font(.appFont(size: fontSize))
          .foregroundColor(theme.textColor)
          .lineLimit(1)
          .padding(.trailing, 4)
        Image(systemName: "chevron.up")
          .font(.appFont(size: iconSize, weight: .bold))
          .foregroundColor(theme.secondaryTextColor)
      }
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, verticalPadding)
      .background(effectiveBackgroundColor)
      .cornerRadius(effectiveBorderRadius)
      .overlay(
        showBorder
          ? RoundedRectangle(cornerRadius: effectiveBorderRadius)
            .stroke(isHovered ? theme.accentColor.opacity(0.5) : theme.borderColor, lineWidth: 0.5)
          : nil
      )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovered = hovering
      if opensOnHover && hovering {
        isPopoverPresented = true
      }
    }
    .help("Choose a model and configure its reasoning")
    .background {
      DropdownPanelAnchor(
        isPresented: $isPopoverPresented,
        menuWidth: 236,
        menu: AgentModelMenuPanel(
          models: models,
          selectedModelID: selectedModelID,
          selectedModelName: selectedModelName,
          selectedModel: selectedModel,
          selectedEffort: selectedEffort,
          agentID: agentID,
          isLoading: isLoading,
          onSelectModel: onSelectModel,
          onSelectReasoningEffort: onSelectReasoningEffort,
          onReset: onReset
        ),
        opensOnHover: opensOnHover
      )
    }
  }
}

private struct AgentModelMenuPanel: View {
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

  @State private var isModelSubmenuPresented = false
  @State private var isReasoningSubmenuPresented = false
  @ObservedObject private var theme = ThemeManager.shared

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
        )
      )

      if hasReasoningSettings {
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
          )
        )
      }

      Divider()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)

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
      .buttonStyle(.plain)
      .disabled(selectedEffort == nil)
    }
    .padding(6)
    .frame(width: 236, alignment: .leading)
    .background(menuBackground)
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(theme.textColor.opacity(0.1), lineWidth: 0.5)
    }
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  @ViewBuilder
  private var menuBackground: some View {
    if theme.usesGlassEffect {
      ZStack {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(.ultraThinMaterial)
        if let overlay = theme.glassOverlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(overlay)
        }
      }
    } else {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(theme.solidBackground)
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

  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Button(action: { isPresented.toggle() }) {
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
    .buttonStyle(.plain)
    .onHover { hovering in
      if opensOnHover && hovering {
        isPresented = true
      }
    }
    .background {
      DropdownPanelAnchor(
        isPresented: $isPresented,
        menuWidth: menuWidth,
        menu: menu,
        placement: .trailing,
        opensOnHover: opensOnHover
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
    .background(menuBackground)
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(theme.textColor.opacity(0.1), lineWidth: 0.5)
    }
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  @ViewBuilder
  private var menuBackground: some View {
    if theme.usesGlassEffect {
      ZStack {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(.ultraThinMaterial)
        if let overlay = theme.glassOverlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(overlay)
        }
      }
    } else {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(theme.solidBackground)
    }
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
    .background(menuBackground)
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(theme.textColor.opacity(0.1), lineWidth: 0.5)
    }
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  @ViewBuilder
  private var menuBackground: some View {
    if theme.usesGlassEffect {
      ZStack {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(.ultraThinMaterial)
        if let overlay = theme.glassOverlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(overlay)
        }
      }
    } else {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(theme.solidBackground)
    }
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
            .foregroundColor(.white)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(backgroundFill)
      )
    }
    .buttonStyle(.plain)
    .disabled(!isAvailable)
    .onHover { isHovered = $0 }
  }

  private var textColor: Color {
    if isSelected && isAvailable { return .white }
    if !isAvailable { return theme.textColor.opacity(0.4) }
    return theme.textColor
  }

  private var backgroundFill: Color {
    if isSelected && isAvailable { return theme.accentColor }
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
