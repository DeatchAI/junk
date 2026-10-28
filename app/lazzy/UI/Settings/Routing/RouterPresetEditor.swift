import SwiftUI

struct RouterPresetEditor: View {
  let title: String
  @Binding var preset: RouterPreset
  let capabilities: [AgentCapability]
  private var models: [AgentModelCapability] { capabilities.first { $0.id == preset.agent }?.models ?? [] }
  private var model: AgentModelCapability? { models.first { $0.id == preset.model } }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(title).font(.appFont(size: 12, weight: .medium))
      HStack(spacing: 10) {
        Picker("Agent", selection: Binding(get: { preset.agent }, set: { preset = RouterPreset(agent: $0) })) {
          Text("Automatic").tag("")
          ForEach(AgentProvider.allCases) { agent in
            Text(agent.name).tag(agent.id)
              .disabled(!capabilities.isEmpty && !capabilities.contains { $0.id == agent.id && $0.installed })
          }
        }
        if !preset.isAutomatic {
          Picker("Model", selection: Binding(get: { preset.model ?? "" }, set: { preset.model = $0.isEmpty ? nil : $0; preset.effort = nil })) {
            Text("Agent default").tag("")
            ForEach(models) { Text($0.displayName).tag($0.id) }
            if let selected = preset.model, !models.contains(where: { $0.id == selected }) {
              Text("Unavailable: \(selected)").tag(selected).disabled(true)
            }
          }
        }
      }
      .pickerStyle(.menu).font(.appFont(size: 11))
      if let efforts = model?.reasoningEfforts, !efforts.isEmpty {
        Picker("Reasoning", selection: Binding(get: { preset.effort ?? "" }, set: { preset.effort = $0.isEmpty ? nil : $0 })) {
          Text("Automatic").tag("")
          ForEach(efforts, id: \.self) { Text($0.capitalized).tag($0) }
        }.pickerStyle(.menu).font(.appFont(size: 11))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct RouterPreferencesForm: View {
  @ObservedObject var router: AutoRouter
  var compact = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Picker("What matters most?", selection: $router.configuration.priority) {
        ForEach(RouterPriority.allCases) { Text($0.title).tag($0) }
      }.pickerStyle(.menu)
      if !compact { RouterRulesView(router: router) }
    }
    .font(.appFont(size: 12))
  }
}
