import SwiftUI

struct RouterRulesView: View {
  @ObservedObject var router: AutoRouter
  @ObservedObject private var theme = ThemeManager.shared
  @State private var editing: RouterRule?

  private var rules: [RouterRule] { router.configuration.activeRules }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if rules.isEmpty {
        Text("Auto will choose for you. Add a preference for work you want routed a particular way.")
          .foregroundStyle(theme.secondaryTextColor)
          .fixedSize(horizontal: false, vertical: true)
      }
      ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
        HStack(alignment: .center, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text(rule.description).lineLimit(2)
            Text(choiceLabel(rule.preset)).foregroundStyle(theme.secondaryTextColor).lineLimit(1)
          }
          Spacer(minLength: 8)
          AppActionMenu(actions: [
            .init(title: "Edit", symbol: "pencil") { editing = rule },
            .init(title: "Move up", symbol: "arrow.up", isEnabled: index > 0) { move(index, by: -1) },
            .init(title: "Move down", symbol: "arrow.down", isEnabled: index < rules.count - 1) { move(index, by: 1) },
            .init(title: "Remove", symbol: "trash") { remove(rule.id) },
          ]) {
            Image(systemName: "ellipsis").frame(width: 12)
          }.accessibilityLabel("Options for \(rule.description)")
        }
        .padding(10)
        .background(theme.controlBackgroundColor, in: RoundedRectangle(cornerRadius: 8))
      }
      Button("Add a preference", systemImage: "plus") { editing = RouterRule() }
        .disabled(rules.count >= RouterConfiguration.maxRules)
      Text("Preferences are checked in order. Everything else is handled automatically.")
        .foregroundStyle(theme.secondaryTextColor)
      if rules.count >= RouterConfiguration.maxRules {
        Text("You can add up to \(RouterConfiguration.maxRules) preferences.").foregroundStyle(theme.secondaryTextColor)
      }
    }
    .sheet(item: $editing) { rule in
      RouterRuleEditor(rule: rule, capabilities: router.capabilities) { saved in
        var updated = rules
        if let index = updated.firstIndex(where: { $0.id == saved.id }) { updated[index] = saved }
        else { updated.append(saved) }
        router.configuration.setRules(updated)
        editing = nil
      } onCancel: { editing = nil }
    }
  }

  private func choiceLabel(_ preset: RouterPreset) -> String {
    let model = router.capabilities.first { $0.id == preset.agent }?.models.first { $0.id == preset.model }?.displayName
      ?? preset.model ?? "Agent default"
    return [AgentProvider.displayName(for: preset.agent), model, preset.effort?.capitalized ?? "Automatic reasoning"].joined(separator: " · ")
  }

  private func move(_ index: Int, by offset: Int) {
    var updated = rules
    let destination = index + offset
    guard updated.indices.contains(index), updated.indices.contains(destination) else { return }
    updated.swapAt(index, destination)
    router.configuration.setRules(updated)
  }

  private func remove(_ id: UUID) {
    router.configuration.setRules(rules.filter { $0.id != id })
  }
}

struct RouterRuleEditor: View {
  @State var rule: RouterRule
  let capabilities: [AgentCapability]
  let onSave: (RouterRule) -> Void
  let onCancel: () -> Void
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Routing preference").font(.appFont(size: 16, weight: .semibold))
      Text("When the request is about")
      AppTextField("For example: UI, visual design, and landing pages", text: $rule.description)
        .onChange(of: rule.description) { _, value in
          if value.count > 240 { rule.description = String(value.prefix(240)) }
          rule.matchingDetails = nil
        }
      RouterPresetEditor(title: "Use this choice", preset: $rule.preset, capabilities: capabilities)
      if capabilities.isEmpty {
        Text("Models appear after agents connect. You can refine this preference in Settings.")
          .foregroundStyle(theme.secondaryTextColor)
      }
      HStack {
        Spacer()
        Button("Cancel", action: onCancel)
        Button("Save") {
          rule.description = rule.description.trimmingCharacters(in: .whitespacesAndNewlines)
          onSave(rule)
        }
        .disabled(rule.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || rule.preset.isAutomatic)
        .keyboardShortcut(.defaultAction)
      }
    }
    .buttonStyle(AppButtonStyle())
    .font(.appFont(size: 12))
    .padding(22)
    .frame(width: 480)
    .foregroundStyle(theme.textColor)
  }
}
