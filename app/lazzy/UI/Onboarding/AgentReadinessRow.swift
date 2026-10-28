import SwiftUI

struct AgentReadinessRow: View {
  let agentID: String
  @StateObject private var setup = AgentSetupModel()
  private var agent: AgentProvider { AgentProvider(rawValue: agentID) ?? .codex }

  var body: some View {
    VStack(spacing: 0) {
      SettingsRow(title: "Connection · \(setup.readiness(for: agent).title)",
        subtitle: setup.readiness(for: agent).detail) {
        HStack(spacing: 12) {
          Button("Check sign-in") { setup.refresh(only: agent) }
          Link("Setup guide", destination: agent.setupURL)
        }.font(.appFont(size: 11))
      }
      if LocalAgentDetector.executable(for: agent) != nil {
        SettingsRow(title: "Verify a response", subtitle: "Opens an example for you to send using your agent's normal allowance.") {
          Button("Try a first task") { AppCoordinator.shared?.openFirstAgentTask(agent: agentID) }
            .font(.appFont(size: 11))
        }
      }
    }
    .onAppear { setup.refresh(only: agent) }
    .onChange(of: agentID) { _, _ in setup.refresh(only: agent) }
    .onDisappear { setup.cancel() }
  }
}
