import AppKit
import SwiftUI

struct AgentSetupList: View {
  @ObservedObject var setup: AgentSetupModel
  @Binding var selectedAgent: String

  private var selected: AgentProvider { AgentProvider(rawValue: selectedAgent) ?? .codex }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ScrollView {
        VStack(spacing: 8) {
          ForEach(AgentProvider.allCases) { agent in
            let readiness = setup.readiness(for: agent)
            Button { selectedAgent = agent.id } label: {
              HStack(spacing: 12) {
                Image(systemName: agent.symbol).frame(width: 24)
                Text(agent.name).font(.system(size: 14, weight: .semibold))
                Spacer()
                if readiness.state == .checking { ProgressView().controlSize(.small) }
                Text(readiness.title).font(.system(size: 12)).foregroundStyle(.secondary)
                Image(systemName: selectedAgent == agent.id ? "checkmark.circle.fill" : "circle")
              }
              .padding(12)
              .background(.primary.opacity(selectedAgent == agent.id ? 0.09 : 0.035), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(agent.name), \(readiness.title)")
          }
        }
      }.scrollIndicators(.hidden).frame(height: 260)
      Text(setup.readiness(for: selected).detail)
        .font(.system(size: 12)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 16) {
        Button("Check again") { setup.refresh() }
        Link("Setup guide", destination: selected.setupURL)
        if setup.readiness(for: selected).state != .missing {
          Button("Copy sign-in command") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selected.signInCommand, forType: .string)
          }
        }
      }.font(.system(size: 12)).buttonStyle(.plain).tint(.primary)
    }
  }
}
