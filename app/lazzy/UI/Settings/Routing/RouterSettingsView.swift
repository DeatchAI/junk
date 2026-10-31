import SwiftUI

struct RouterSettingsView: View {
  @ObservedObject var wsManager: WebSocketManager
  @ObservedObject private var router = AutoRouter.shared
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    SettingsPage(title: "Auto router",
      subtitle: "Choose the agent, model, and reasoning for each new conversation.") {
      SettingsSection(title: "Routing") {
        SettingsToggleRow(title: "Route new conversations automatically",
          subtitle: "Existing conversations stay with their original agent.", isOn: $router.configuration.enabled)
        SettingsCardDivider()
        VStack(alignment: .leading, spacing: 10) {
          RouterKeyEditor(router: router)
          Text("When Auto uses Jev, it sends up to 8,000 characters of your new message, attachment types and routing preferences directly to TypeSafe using your key. It does not upload your attachments or add conversation history. Any private information you include in the message itself is sent too. TypeSafe bills your account; its data policies apply.")
            .font(.appFont(size: 10.5)).foregroundStyle(theme.secondaryTextColor)
            .fixedSize(horizontal: false, vertical: true)
        }.padding(14)
      }
      SettingsSection(title: "Your preferences") {
        RouterPreferencesForm(router: router)
      }
      RouterTestView(router: router)
      SettingsSection(title: "Manual override and fallback") {
        RouterPresetEditor(title: "Always use", preset: $router.configuration.fixedChoice, capabilities: router.capabilities)
        SettingsCardDivider()
        SettingsRow(title: "If Auto cannot choose", subtitle: "Applied before work starts.") {
          AppSelect(title: "Fallback", selection: $router.configuration.fallback,
            options: RouterFallback.allCases.map { .init(title: $0.title, value: $0) })
        }
        Text("Automatic lets Jev decide. A fixed choice skips Jev. Detach never retries an in-progress task with another provider.")
          .font(.appFont(size: 10.5)).foregroundStyle(theme.secondaryTextColor).padding(14)
      }
      usageSection
      decisionsSection
    }
    .foregroundStyle(theme.textColor)
    .onAppear { router.capabilities = wsManager.agentCapabilities; wsManager.requestCapabilities() }
    .onChange(of: wsManager.agentCapabilities) { _, value in router.capabilities = value }
  }

  private var usageSection: some View {
    SettingsSection(title: "Usage limits") {
      SettingsToggleRow(title: "Consider my remaining allowance", isOn: $router.configuration.considerUsage)
      if router.configuration.considerUsage {
        SettingsCardDivider()
        SettingsRow(title: "Reserve", subtitle: "Percentage of your allowance to keep available.") {
          HStack(spacing: 8) {
            Text("\(router.configuration.reservePercent)%").font(.appFont(size: 11))
              .foregroundStyle(theme.secondaryTextColor)
            AppStepper(value: $router.configuration.reservePercent, range: 0...95, step: 5, title: "Reserve")
          }
        }
        SettingsCardDivider()
        SettingsRow(title: "Provider limits") {
          Button("Refresh") { Task { await router.refreshUsage() } }
            .buttonStyle(AppButtonStyle()).disabled(!wsManager.isConnected)
        }
        ForEach(AgentProvider.allCases) { provider in
          SettingsCardDivider()
          SettingsRow(title: provider.name, controlWidth: 270) {
            Text(usageDescription(router.usage.windows.filter { $0.agent == provider.id }))
              .font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
          }
        }
        Text("Codex limits are read from its signed-in CLI. Other providers report Unknown until a supported limit interface is available. Limits older than two minutes are treated as unknown; model-specific buckets without a known mapping are shown but do not block other models.")
          .font(.appFont(size: 10.5)).foregroundStyle(theme.secondaryTextColor)
          .fixedSize(horizontal: false, vertical: true).padding(14)
      }
    }
  }

  private func usageDescription(_ windows: [RouterUsageWindow]) -> String {
    guard Date().timeIntervalSince1970 - router.usage.checkedAt < 120 else { return "Unknown" }
    let current = windows.filter { $0.resetsAt.map { $0 > Date().timeIntervalSince1970 } ?? true }
    guard !current.isEmpty else { return "Unknown" }
    return current.map { "\($0.bucket): \(Int(max(0, min(100, 100 - $0.usedPercent))))% left" }.joined(separator: "; ")
  }

  private var decisionsSection: some View {
    SettingsSection(title: "Recent routing decisions") {
      VStack(alignment: .leading, spacing: 10) {
        if router.records.isEmpty {
          Text("Decisions appear here after you send a new task. Message text and API keys are never recorded.")
            .foregroundStyle(theme.secondaryTextColor)
        }
        ForEach(router.records) { record in
          VStack(alignment: .leading, spacing: 4) {
            if let selection = record.selection {
              Text("\(AgentProvider.displayName(for: selection.preset.agent)) · \(selection.preset.model ?? "Agent default") · \(selection.preset.effort ?? "Default reasoning")")
                .fontWeight(.medium)
              if let confidence = selection.confidence {
                Text("Classification confidence: \(Int(confidence * 100))%").foregroundStyle(theme.secondaryTextColor)
              }
            }
            Text(record.summary).foregroundStyle(theme.secondaryTextColor)
            Text(record.date, style: .time).foregroundStyle(theme.secondaryTextColor)
          }
          SettingsCardDivider()
        }
        if !router.records.isEmpty {
          Button("Clear decisions") { router.clearRecords() }.buttonStyle(AppButtonStyle())
        }
      }.font(.appFont(size: 11)).padding(14)
    }
  }
}
