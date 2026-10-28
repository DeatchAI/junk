import Combine
import Foundation

/// A run always targets its original socket, never the globally selected agent.
@MainActor
final class DetachedRunControls: ObservableObject {
  private final class Target {
    weak var manager: WebSocketManager?
    let request: ChatRequest
    init(_ request: ChatRequest, manager: WebSocketManager) {
      self.request = request
      self.manager = manager
    }
  }

  private var targets: [String: Target] = [:]
  private var observations: [ObjectIdentifier: AnyCancellable] = [:]

  func register(_ request: ChatRequest, manager: WebSocketManager) {
    guard let id = request.runId else { return }
    targets[id] = Target(request, manager: manager)
    let owner = ObjectIdentifier(manager)
    if observations[owner] == nil {
      observations[owner] = manager.$isConnected.combineLatest(manager.$isStreaming)
        .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.objectWillChange.send() }
    }
  }

  func canStop(_ run: DetachedAgentRun) -> Bool {
    guard run.isActive, run.state != .stopping, let manager = targets[run.id]?.manager else { return false }
    return manager.isConnected && manager.isStreaming && manager.activeChatRequest?.runId == run.id
  }

  func canResume(_ run: DetachedAgentRun) -> Bool {
    guard run.state == .stopped || run.state == .failed,
      let conversationID = run.conversationId, let manager = targets[run.id]?.manager else { return false }
    return manager.isConnected && !manager.isStreaming && !manager.isStoppingRun
      && manager.currentConversationId == conversationID
  }

  func stop(_ run: DetachedAgentRun) {
    guard canStop(run) else { return }
    targets[run.id]?.manager?.stopStreaming()
  }

  func resume(_ run: DetachedAgentRun) {
    guard canResume(run), let target = targets[run.id], let conversationID = run.conversationId else { return }
    target.manager?.continueDetachedRun(target.request, conversationId: conversationID)
  }
}
