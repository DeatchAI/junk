import SwiftUI

struct RouterSettingsView: View {
  @ObservedObject var wsManager: WebSocketManager
  @ObservedObject private var router = AutoRouter.shared
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        SettingsPageHeader(title: "Auto router", subtitle: "Let your preferences choose the agent, model and reasoning for each new conversation.")
        SettingsCard {
          SettingsToggleRow(title: "Route new conversations automatically", subtitle: "Existing conversations stay with their original agent.", isOn: $router.configuration.enabled)
          SettingsCardDivider()
          VStack(alignment: .leading, spacing: 12) {
            RouterKeyEditor(router: router)
            Text("When Auto uses Jev, it sends up to 8,000 characters of your new message, attachment types and routing preferences directly to TypeSafe using your key. It does not upload your attachments or add conversation history. Any private information you include in the message itself is sent too. TypeSafe bills your account; its data policies apply.")
              .font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor).fixedSize(horizontal: false, vertical: true)
          }.padding(16)
        }

        section("Your preferences") {
          RouterPreferencesForm(router: router)
        }
        RouterTestView(router: router)
        section("Manual override and fallback") {
          VStack(alignment: .leading, spacing: 16) {
            RouterPresetEditor(title: "Always use this choice for new conversations", preset: $router.configuration.fixedChoice, capabilities: router.capabilities)
            Text("Automatic lets Jev decide. A fixed choice skips Jev and keeps your chosen model and reasoning.")
              .font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
            Picker("If Auto cannot choose", selection: $router.configuration.fallback) {
              ForEach(RouterFallback.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.menu)
            Text("Fallback applies before work starts. Detach never retries an in-progress task with another provider.")
              .font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
          }
        }
        usageSection
        decisionsSection
      }.padding(.bottom, 24)
    }
    .foregroundStyle(theme.textColor)
    .tint(theme.textColor)
    .onAppear { router.capabilities = wsManager.agentCapabilities; wsManager.requestCapabilities() }
    .onChange(of: wsManager.agentCapabilities) { _, value in router.capabilities = value }
  }

  private var usageSection: some View {
    section("Usage limits") {
      VStack(alignment: .leading, spacing: 14) {
        Toggle("Consider my remaining allowance", isOn: $router.configuration.considerUsage)
        if router.configuration.considerUsage {
          Stepper("Keep \(router.configuration.reservePercent)% in reserve", value: $router.configuration.reservePercent, in: 0...95, step: 5)
          Button("Refresh limits") { Task { await router.refreshUsage() } }.disabled(!wsManager.isConnected)
          ForEach(AgentProvider.allCases) { provider in
            let windows = router.usage.windows.filter { $0.agent == provider.id }
            HStack {
              Text(provider.name)
              Spacer()
              Text(usageDescription(windows)).foregroundStyle(theme.secondaryTextColor)
            }
          }
          Text("Codex limits are read from its signed-in CLI. Other providers report Unknown until a supported limit interface is available. Limits older than two minutes are treated as unknown; model-specific buckets without a known mapping are shown but do not block other models.")
            .font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
        }
      }.font(.appFont(size: 12))
    }
  }

  private func usageDescription(_ windows: [RouterUsageWindow]) -> String {
    guard Date().timeIntervalSince1970 - router.usage.checkedAt < 120 else { return "Unknown" }
    let current = windows.filter { $0.resetsAt.map { $0 > Date().timeIntervalSince1970 } ?? true }
    guard !current.isEmpty else { return "Unknown" }
    return current.map { "\($0.bucket): \(Int(max(0, min(100, 100 - $0.usedPercent))))% left" }.joined(separator: "; ")
  }

  private var decisionsSection: some View {
    section("Recent routing decisions") {
      VStack(alignment: .leading, spacing: 12) {
        if router.records.isEmpty {
          Text("Decisions appear here after you send a new task. Message text and API keys are never recorded.")
            .foregroundStyle(theme.secondaryTextColor)
        }
        ForEach(router.records) { record in
          VStack(alignment: .leading, spacing: 5) {
            if let selection = record.selection {
              Text("\(AgentProvider.displayName(for: selection.preset.agent)) · \(selection.preset.model ?? "Agent default") · \(selection.preset.effort ?? "Default reasoning")")
                .fontWeight(.medium)
              if let confidence = selection.confidence {
                Text("Classification confidence: \(Int(confidence * 100))%")
                  .foregroundStyle(theme.secondaryTextColor)
              }
            }
            Text(record.summary).foregroundStyle(theme.secondaryTextColor)
            Text(record.date, style: .time).foregroundStyle(theme.secondaryTextColor)
          }
          Divider()
        }
        if !router.records.isEmpty { Button("Clear decisions") { router.clearRecords() } }
      }.font(.appFont(size: 11))
    }
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      SettingsSectionHeader(title: title)
      SettingsCard { content().padding(16) }
    }
  }
}
