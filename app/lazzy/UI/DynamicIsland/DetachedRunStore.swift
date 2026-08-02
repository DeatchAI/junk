import Combine
import Foundation

enum DetachedRunState: Equatable {
  case running
  case awaitingApproval
  case awaitingCredential
  case completed
  case failed
}

enum NotchDebugScenario: CaseIterable {
  case thinking
  case command
  case fileChange
  case mcpTool
  case plan
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

  var isActive: Bool {
    state == .running || state == .awaitingApproval || state == .awaitingCredential
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

  var currentActivity: String {
    if let toolName, !toolName.isEmpty {
      return "Using \(toolName.replacingOccurrences(of: "_", with: " "))"
    }
    if let event, !event.title.isEmpty, event.title != taskTitle {
      return event.title
    }
    return status
  }
}

/// The local source of truth for detached agent work. It intentionally sits above the
/// floating chat window so closing that window never drops the user-facing run state.
final class DetachedRunStore: ObservableObject {
  @Published private(set) var runs: [DetachedAgentRun] = []

  /// Includes previews so the Notch Debug menu still accurately renders its samples.
  var visibleActiveRuns: [DetachedAgentRun] {
    runs.filter(\.isActive).sorted { $0.updatedAt > $1.updatedAt }
  }

  /// Only real agent work participates in lifecycle decisions such as completion
  /// and automatic dismissal. A preview must never keep the notch "working".
  var activeRuns: [DetachedAgentRun] {
    visibleActiveRuns.filter { !$0.isDebugPreview }
  }

  var primaryRun: DetachedAgentRun? {
    visibleActiveRuns.first ?? runs.sorted { $0.updatedAt > $1.updatedAt }.first
  }

  var presentationRuns: [DetachedAgentRun] {
    let active = visibleActiveRuns
    let recent = runs
      .filter { !$0.isActive }
      .sorted { $0.updatedAt > $1.updatedAt }
      .prefix(3)
    return active + recent
  }

  var hasActiveRuns: Bool { !activeRuns.isEmpty }

  var hasPendingApproval: Bool {
    runs.contains { $0.state == .awaitingApproval && $0.approval != nil }
  }

  func begin(_ request: ChatRequest) {
    guard let runId = request.runId else { return }
    discardDebugPreviews()
    let prompt = compact(request.displayText ?? request.text)
    let chatTitle = makeChatTitle(prompt)
    upsert(runId) { run in
      run.agent = request.agent ?? run.agent
      run.prompt = prompt
      run.chatTitle = chatTitle
      run.status = "Starting agent"
      run.state = .running
      run.updatedAt = .now
    } create: {
      DetachedAgentRun(
        id: runId,
        conversationId: request.conversationId,
        agent: request.agent ?? "agent",
        prompt: prompt,
        chatTitle: chatTitle,
        status: "Starting agent",
        toolName: nil,
        event: nil,
        state: .running,
        approval: nil,
        credential: nil,
        isDebugPreview: false,
        startedAt: .now,
        updatedAt: .now
      )
    }
  }

  func apply(_ update: AgentActivityUpdate) {
    let runId = update.runId ?? activeRuns.first?.id
    guard let runId else { return }
    discardDebugPreviews()

    upsert(runId) { run in
      run.conversationId = update.conversationId ?? run.conversationId
      run.agent = update.event?.agent ?? run.agent
      run.status = update.status
      run.toolName = update.toolName ?? update.event?.toolName ?? run.toolName
      run.event = update.event ?? run.event
      if run.state != .awaitingApproval && run.state != .awaitingCredential { run.state = .running }
      run.updatedAt = .now
    } create: {
      DetachedAgentRun(
        id: runId,
        conversationId: update.conversationId,
        agent: update.event?.agent ?? "agent",
        prompt: "Detached agent task",
        chatTitle: "New chat",
        status: update.status,
        toolName: update.toolName ?? update.event?.toolName,
        event: update.event,
        state: .running,
        approval: nil,
        credential: nil,
        isDebugPreview: false,
        startedAt: .now,
        updatedAt: .now
      )
    }
  }

  func complete(runId: String?, conversationId: String) {
    guard let runId = resolvedRealRunId(runId: runId, conversationId: conversationId) else { return }
    update(runId) { run in
      run.conversationId = conversationId
      run.status = "Completed"
      run.state = .completed
      run.approval = nil
      run.credential = nil
      run.updatedAt = .now
    }
  }

  func fail(runId: String?, message: String) {
    guard let runId = resolvedRealRunId(runId: runId) else { return }
    update(runId) { run in
      run.status = compact(message)
      run.state = .failed
      run.approval = nil
      run.credential = nil
      run.updatedAt = .now
    }
  }

  func requestApproval(
    id: String,
    runId: String?,
    conversationId: String?,
    command: String,
    description: String,
    riskLevel: String
  ) {
    let resolvedRunId = runId ?? activeRuns.first?.id
    guard let resolvedRunId else { return }
    let approval = DetachedRunApproval(id: id, command: command, description: description, riskLevel: riskLevel)

    upsert(resolvedRunId) { run in
      run.conversationId = conversationId ?? run.conversationId
      run.status = "Approval needed"
      run.state = .awaitingApproval
      run.approval = approval
      run.updatedAt = .now
    } create: {
      DetachedAgentRun(
        id: resolvedRunId,
        conversationId: conversationId,
        agent: "agent",
        prompt: "Detached agent task",
        chatTitle: "New chat",
        status: "Approval needed",
        toolName: command,
        event: nil,
        state: .awaitingApproval,
        approval: approval,
        credential: nil,
        isDebugPreview: false,
        startedAt: .now,
        updatedAt: .now
      )
    }
  }

  func resolveApproval(id: String) {
    guard let index = runs.firstIndex(where: { $0.approval?.id == id }) else { return }
    runs[index].approval = nil
    runs[index].state = .running
    runs[index].status = "Continuing agent task"
    runs[index].updatedAt = .now
  }

  func requestCredential(id: String, runId: String?, conversationId: String?, label: String, origin: String) {
    let resolvedRunId = runId ?? activeRuns.first?.id
    guard let resolvedRunId else { return }
    let credential = DetachedRunCredential(id: id, label: label, origin: origin)
    upsert(resolvedRunId) { run in
      run.conversationId = conversationId ?? run.conversationId
      run.status = "Touch ID required"
      run.state = .awaitingCredential
      run.credential = credential
      run.updatedAt = .now
    } create: {
      DetachedAgentRun(id: resolvedRunId, conversationId: conversationId, agent: "agent", prompt: "Detached agent task", chatTitle: "New chat", status: "Touch ID required", toolName: "Secure credential", event: nil, state: .awaitingCredential, approval: nil, credential: credential, isDebugPreview: false, startedAt: .now, updatedAt: .now)
    }
  }

  func resolveCredential(id: String, success: Bool) {
    guard let index = runs.firstIndex(where: { $0.credential?.id == id }) else { return }
    runs[index].credential = nil
    runs[index].state = success ? .running : .failed
    runs[index].status = success ? "Credential inserted securely" : "Credential use was cancelled"
    runs[index].updatedAt = .now
  }

  /// Local-only samples for evaluating the notch without starting a paid agent run.
  func showDebugScenario(_ scenario: NotchDebugScenario) {
    guard scenario != .clear else {
      runs.removeAll()
      return
    }

    let now = Date.now
    func makeRun(
      id: String,
      agent: String,
      kind: String,
      title: String,
      status: String,
      state: DetachedRunState = .running,
      toolName: String? = nil,
      approval: DetachedRunApproval? = nil,
      credential: DetachedRunCredential? = nil,
      isDebugPreview: Bool = true
    ) -> DetachedAgentRun {
      DetachedAgentRun(
        id: id,
        conversationId: nil,
        agent: agent,
        prompt: "Preview only — no agent request was started.",
        chatTitle: title,
        status: status,
        toolName: toolName,
        event: AgentActivityEvent(
          id: "debug_\(id)",
          agent: agent,
          kind: kind,
          action: nil,
          phase: state == .failed ? "failed" : state == .completed ? "completed" : "updated",
          title: title,
          subtitle: status,
          toolName: toolName,
          userFacing: true,
          sourceEventType: "notch_debug",
          sourceItemType: nil
        ),
        state: state,
        approval: approval,
        credential: credential,
        isDebugPreview: isDebugPreview,
        startedAt: now,
        updatedAt: now
      )
    }

    let run: DetachedAgentRun
    switch scenario {
    case .thinking:
      run = makeRun(id: "debug-thinking", agent: "codex", kind: "lifecycle", title: "Codex is reasoning", status: "Reviewing the task and planning the next step")
    case .command:
      run = makeRun(id: "debug-command", agent: "codex", kind: "command", title: "Running tests", status: "Checking the current implementation", toolName: "terminal")
    case .fileChange:
      run = makeRun(id: "debug-file", agent: "claude", kind: "file_change", title: "Updating ActivityIslandView.swift", status: "Applying a focused interface change", toolName: "apply_patch")
    case .mcpTool:
      run = makeRun(id: "debug-mcp", agent: "grok", kind: "mcp_tool", title: "Using browser", status: "Reading the current page state", toolName: "browser")
    case .plan:
      run = makeRun(id: "debug-plan", agent: "claude", kind: "plan", title: "Updating the plan", status: "One task completed, two steps remaining", toolName: "plan")
    case .approval:
      let approval = DetachedRunApproval(
        id: "debug-approval",
        command: "git push origin feature/notch",
        description: "Push the completed branch to the remote repository?",
        riskLevel: "normal"
      )
      run = makeRun(id: "debug-approval-run", agent: "codex", kind: "command", title: "Approval needed", status: "Waiting for your decision", state: .awaitingApproval, toolName: "git push", approval: approval)
    case .failure:
      run = makeRun(id: "debug-failure", agent: "grok", kind: "error", title: "Browser action needs attention", status: "The page did not respond to the requested action", state: .failed, toolName: "browser")
    case .completed:
      run = makeRun(id: "debug-completed", agent: "claude", kind: "lifecycle", title: "Task completed", status: "The agent has finished its work", state: .completed)
    case .multiAgent:
      runs = [
        makeRun(id: "debug-multi-codex", agent: "codex", kind: "command", title: "Running tests", status: "Validating the new notch states", toolName: "terminal"),
        makeRun(id: "debug-multi-claude", agent: "claude", kind: "file_change", title: "Editing the agent view", status: "Applying visual polish", toolName: "apply_patch"),
        makeRun(id: "debug-multi-grok", agent: "grok", kind: "mcp_tool", title: "Using browser", status: "Checking the live result", toolName: "browser"),
      ]
      return
    case .multiMixedStates:
      let approval = DetachedRunApproval(
        id: "debug-mixed-approval",
        command: "git push origin main",
        description: "Push local commits to production branch?",
        riskLevel: "high"
      )
      runs = [
        makeRun(id: "debug-mixed-running", agent: "codex", kind: "command", title: "Running build pipeline", status: "Compiling binary targets", toolName: "xcodebuild"),
        makeRun(id: "debug-mixed-approval", agent: "claude", kind: "command", title: "Approval needed", status: "Confirm git push", state: .awaitingApproval, toolName: "git push", approval: approval),
        makeRun(id: "debug-mixed-completed", agent: "grok", kind: "lifecycle", title: "Asset generation", status: "Created app icons successfully", state: .completed),
        makeRun(id: "debug-mixed-failed", agent: "claude", kind: "error", title: "Deploy task failed", status: "Remote rejected push", state: .failed, toolName: "ssh"),
      ]
      return
    case .clear:
      return
    }

    runs = [run]
  }

  private func update(_ id: String, _ mutate: (inout DetachedAgentRun) -> Void) {
    guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
    mutate(&runs[index])
  }

  private func discardDebugPreviews() {
    runs.removeAll { $0.isDebugPreview }
  }

  /// The runtime normally echoes the client run ID. If an older/late event does
  /// not, this single-run runtime can still close the live run by conversation.
  private func resolvedRealRunId(runId: String?, conversationId: String? = nil) -> String? {
    if let runId, runs.contains(where: { $0.id == runId && !$0.isDebugPreview }) {
      return runId
    }
    if let conversationId,
      let matchingRun = activeRuns.first(where: { $0.conversationId == conversationId })
    {
      return matchingRun.id
    }
    return activeRuns.first?.id
  }

  private func upsert(
    _ id: String,
    update: (inout DetachedAgentRun) -> Void,
    create: () -> DetachedAgentRun
  ) {
    if let index = runs.firstIndex(where: { $0.id == id }) {
      update(&runs[index])
    } else {
      runs.append(create())
    }
  }

  private func compact(_ text: String) -> String {
    let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return String(normalized.prefix(100))
  }

  private func makeChatTitle(_ text: String) -> String {
    let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return "New chat" }
    return normalized.count > 100 ? String(normalized.prefix(97)) + "..." : normalized
  }
}
