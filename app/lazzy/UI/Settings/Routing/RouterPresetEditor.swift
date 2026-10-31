import SwiftUI

struct RouterPresetEditor: View {
  let title: String
  @Binding var preset: RouterPreset
  let capabilities: [AgentCapability]
  private var models: [AgentModelCapability] { capabilities.first { $0.id == preset.agent }?.models ?? [] }
  private var model: AgentModelCapability? { models.first { $0.id == preset.model } }

  private var agentOptions: [AppSelectOption<String>] {
    [.init(title: "Automatic", value: "")] + AgentProvider.allCases.map { agent in
      .init(title: agent.name, value: agent.id, asset: agent.asset,
        isEnabled: capabilities.isEmpty || capabilities.contains { $0.id == agent.id && $0.installed })
    }
  }

  private var modelOptions: [AppSelectOption<String>] {
    var options: [AppSelectOption<String>] = [.init(title: "Agent default", value: "")]
      + models.map { .init(title: $0.displayName, value: $0.id) }
    if let selected = preset.model, !models.contains(where: { $0.id == selected }) {
      options.append(.init(title: "Unavailable: \(selected)", value: selected, isEnabled: false))
    }
    return options
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsRow(title: title) {
        AppSelect(title: "Agent",
          selection: Binding(get: { preset.agent }, set: { preset = RouterPreset(agent: $0) }),
          options: agentOptions)
      }
      if !preset.isAutomatic {
        SettingsCardDivider()
        SettingsRow(title: "Model") {
          AppSelect(title: "Model",
            selection: Binding(get: { preset.model ?? "" }, set: {
              preset.model = $0.isEmpty ? nil : $0
              preset.effort = nil
            }), options: modelOptions)
        }
      }
      if let efforts = model?.reasoningEfforts, !efforts.isEmpty {
        SettingsCardDivider()
        SettingsRow(title: "Reasoning") {
          AppSelect(title: "Reasoning",
            selection: Binding(get: { preset.effort ?? "" }, set: { preset.effort = $0.isEmpty ? nil : $0 }),
            options: [.init(title: "Automatic", value: "")]
              + efforts.map { .init(title: $0.capitalized, value: $0) })
        }
      }
    }
  }
}

struct RouterPreferencesForm: View {
  @ObservedObject var router: AutoRouter
  var compact = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsRow(title: "What matters most?") {
        AppSelect(title: "Priority", selection: $router.configuration.priority,
          options: RouterPriority.allCases.map { .init(title: $0.title, value: $0) })
      }
      if !compact {
        SettingsCardDivider()
        RouterRulesView(router: router).padding(14)
      }
    }
  }
}
