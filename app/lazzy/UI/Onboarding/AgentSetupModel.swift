import Combine
import Foundation

@MainActor final class AgentSetupModel: ObservableObject {
  @Published private(set) var states: [AgentProvider: AgentReadiness] = [:]
  private var refreshTask: Task<Void, Never>?
  private static var successfulResponses: [String: Date] = [:]

  init(states: [AgentProvider: AgentReadiness] = [:]) { self.states = states }

  static func recordSuccessfulResponse(agent: String) { successfulResponses[agent] = .now }

  func readiness(for agent: AgentProvider) -> AgentReadiness {
    states[agent] ?? AgentReadiness(state: .checking, detail: "Checking this Mac…")
  }

  func refresh(only selected: AgentProvider? = nil) {
    let agents = AgentProvider.allCases.filter { selected == nil || $0 == selected }
    refreshTask?.cancel()
    let executables = Dictionary(uniqueKeysWithValues: agents.compactMap { agent in
      LocalAgentDetector.executable(for: agent).map { (agent, $0) }
    })
    states = Dictionary(uniqueKeysWithValues: agents.map { agent in
      (agent, executables[agent] == nil
        ? AgentReadiness(state: .missing, detail: agent.subtitle(isInstalled: false))
        : AgentReadiness(state: .checking, detail: "Checking sign-in without starting a task…"))
    })
    refreshTask = Task { [weak self] in
      await withTaskGroup(of: (AgentProvider, AgentReadiness).self) { group in
        for (agent, executable) in executables {
          group.addTask { (agent, await AgentStatusProbe.check(agent, executable: executable)) }
        }
        for await (agent, readiness) in group {
          guard !Task.isCancelled else { return }
          if readiness.state == .installed,
            let lastResponse = Self.successfulResponses[agent.id], Date().timeIntervalSince(lastResponse) < 3600 {
            self?.states[agent] = AgentReadiness(state: .ready, detail: "Your agent responded successfully in Detach in the last hour.")
          } else { self?.states[agent] = readiness }
        }
      }
    }
  }

  func cancel() { refreshTask?.cancel() }
}
