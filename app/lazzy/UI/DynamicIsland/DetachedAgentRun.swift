import Foundation

enum DetachedRunState: Equatable {
  case running
  case awaitingApproval
  case awaitingInput
  case awaitingCredential
  case stopping
  case stopped
  case completed
  case failed
}

enum NotchDebugScenario: CaseIterable {
  case thinking
  case command
  case fileChange
  case mcpTool
  case plan
  case question
  case approval
  case failure
  case completed
  case multiAgent
  case multiMixedStates
  case clear

  var title: String {
    switch self {
    case .thinking: return "Thinking"
    case .command: return "Terminal command"
    case .fileChange: return "File change"
    case .mcpTool: return "MCP tool"
    case .plan: return "Plan update"
    case .question: return "Clarification"
    case .approval: return "Approval request"
    case .failure: return "Failure"
    case .completed: return "Completed"
    case .multiAgent: return "Multiple agents"
    case .multiMixedStates: return "Multiple states"
    case .clear: return "Clear notch"
    }
  }
}

struct DetachedRunApproval: Equatable {
  let id: String
  let command: String
  let description: String
  let riskLevel: String
}

struct DetachedRunCredential: Equatable {
  let id: String
  let label: String
  let origin: String
}

struct DetachedAgentRun: Identifiable, Equatable {
  let id: String
  var conversationId: String?
  var agent: String
  var prompt: String
  var chatTitle: String
  var status: String
  var toolName: String?
  var event: AgentActivityEvent?
  var state: DetachedRunState
  var approval: DetachedRunApproval?
  var credential: DetachedRunCredential?
  let isDebugPreview: Bool
  let startedAt: Date
  var updatedAt: Date
  var workspacePath: String? = nil
  var isUnread = false
  var outcome = DetachedRunOutcome()

  var projectLabel: String {
    workspacePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No project"
  }

  var isActive: Bool {
    state == .stopping || state == .running || state == .awaitingApproval || state == .awaitingCredential || state == .awaitingInput
  }

  var displayTitle: String {
    if let event, !event.title.isEmpty { return event.title }
    if let toolName, !toolName.isEmpty { return toolName.replacingOccurrences(of: "_", with: " ").capitalized }
    return agent.capitalized
  }

  /// Mirrors the runtime-created title so a task can be named before history
  /// has completed its round trip back to the macOS client.
  var taskTitle: String {
    chatTitle.isEmpty ? "New chat" : chatTitle
  }

  var needsAttention: Bool {
    state == .awaitingApproval || state == .awaitingInput || state == .awaitingCredential
  }

  var stateLabel: String {
    switch state {
    case .running: return "Working"
    case .awaitingApproval: return "Approval needed"
    case .awaitingInput: return "Needs your answer"
    case .awaitingCredential: return "Touch ID needed"
    case .stopping: return "Stopping…"
    case .stopped: return "Stopped"
    case .completed: return "Completed"
    case .failed: return "Needs attention"
    }
  }

  var currentActivity: String {
    switch state {
    case .awaitingApproval:
      guard let approval else { return stateLabel }
      return approval.description.isEmpty ? approval.command : approval.description
    case .awaitingInput: return status
    case .awaitingCredential: return credential.map { "Confirm access to \($0.label)" } ?? stateLabel
    case .stopped: return "Continue when you’re ready"
    case .completed: return outcome.summary ?? (isUnread ? "Ready to review" : "Reviewed")
    case .failed, .stopping: return status
    case .running: break
    }
    if let event, !event.title.isEmpty, event.title != taskTitle { return event.title }
    if !status.isEmpty { return status }
    return "Working…"
  }
}
