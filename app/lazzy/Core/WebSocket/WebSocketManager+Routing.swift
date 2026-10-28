import Foundation

extension WebSocketManager {
  /// Reserve this manager immediately; a double Send must not start two routing calls.
  func beginAutoRouting(_ request: ChatRequest) -> Bool {
    guard !isStreaming, !isStoppingRun else { return false }
    guard RoutePlanner.shouldRoute(request, configuration: AutoRouter.shared.configuration) else { return false }
    let generation = UUID()
    routingGeneration = generation
    isStreaming = true
    lastError = nil
    currentResponse = ""
    routingTask = Task { [weak self] in
      guard let self else { return }
      do {
        let choice = try await AutoRouter.shared.route(request, capabilities: self.agentCapabilities)
        try Task.checkCancellation()
        guard self.routingGeneration == generation, self.isConnected else { return }
        self.routingTask = nil
        self.routingGeneration = nil
        self.isStreaming = false
        var routed = request
        routed.agent = choice.preset.agent
        routed.model = choice.preset.model
        routed.modelSettings = choice.preset.effort.map { AgentModelSettings(reasoningEffort: $0) }
        // Permission policy belongs to the selected agent, never to Jev.
        routed.permissionMode = DetachSettings.permissionMode(for: choice.preset.agent).rawValue
        self.autoRoutedChoice = choice.preset
        self.dispatchChatRequest(routed)
      } catch {
        guard self.routingGeneration == generation, !Task.isCancelled else { return }
        self.routingTask = nil
        self.routingGeneration = nil
        self.isStreaming = false
        self.lastError = error.localizedDescription
        self.onError?(error.localizedDescription)
      }
    }
    return true
  }

  @discardableResult func cancelAutoRouting() -> Bool {
    guard routingTask != nil else { return false }
    routingTask?.cancel()
    routingTask = nil
    routingGeneration = nil
    isStreaming = false
    return true
  }
}
