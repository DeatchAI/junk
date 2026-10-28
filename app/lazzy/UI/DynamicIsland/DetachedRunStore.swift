import Combine
import Foundation

/// The local source of truth for detached agent work. It intentionally sits above the
/// floating chat window so closing that window never drops the user-facing run state.
final class DetachedRunStore: ObservableObject {
  @Published private(set) var runs: [DetachedAgentRun] = []
  var onUnreadChange: (([DetachedAgentRun]) -> Void)?

  var unreadRuns: [DetachedAgentRun] {
    runs.filter { $0.state == .completed && $0.isUnread && !$0.isDebugPreview }
      .sorted { $0.updatedAt > $1.updatedAt }
  }
  var hasUnreadResults: Bool { !unreadRuns.isEmpty }

  func restoreUnread(_ saved: [DetachedAgentRun]) {
    runs.append(contentsOf: saved.filter { saved in !runs.contains { $0.id == saved.id } })
  }

  func markReviewed(conversationId: String) {
    for index in runs.indices where runs[index].conversationId == conversationId { runs[index].isUnread = false }
    onUnreadChange?(unreadRuns)
  }

  func clearCompletedResults() {
    runs.removeAll { $0.state == .completed }
    onUnreadChange?(unreadRuns)
  }

  /// Includes previews so the Notch Debug menu still accurately renders its samples.
  var visibleActiveRuns: [DetachedAgentRun] {
    runs.filter(\.isActive).sorted {
      if $0.needsAttention != $1.needsAttention { return $0.needsAttention }
      return $0.startedAt < $1.startedAt
    }
  }

  /// Only real agent work participates in lifecycle decisions such as completion
  /// and automatic dismissal. A preview must never keep the notch "working".
  var activeRuns: [DetachedAgentRun] {
    visibleActiveRuns.filter { !$0.isDebugPreview }
  }

  var primaryRun: DetachedAgentRun? {
    visibleActiveRuns.first ?? unreadRuns.first ?? runs.sorted { $0.updatedAt > $1.updatedAt }.first
  }

  var presentationRuns: [DetachedAgentRun] {
    let active = visibleActiveRuns
    let recent = runs
      .filter { !$0.isActive }
      .sorted { $0.updatedAt > $1.updatedAt }
      .prefix(3)
    let resumable = recent.filter { $0.state == .stopped || $0.state == .failed }
    let live = (active + resumable).sorted {
      if $0.needsAttention != $1.needsAttention { return $0.needsAttention }
      return $0.startedAt < $1.startedAt
    }
    let ordered = live + unreadRuns + recent.filter { $0.state == .completed && $0.isDebugPreview }
    var conversations = Set<String>()
    return ordered.filter { conversations.insert($0.conversationId ?? $0.id).inserted }
  }

  var hasActiveRuns: Bool { !activeRuns.isEmpty }
  var hasRecoverableRuns: Bool { presentationRuns.contains { $0.state == .stopped || $0.state == .failed } }

  var hasPendingApproval: Bool {
    runs.contains { $0.state == .awaitingApproval && $0.approval != nil }
  }

  func begin(_ request: ChatRequest, conversationTitle: String? = nil) {
    guard let runId = request.runId else { return }
    discardDebugPreviews()
    let prompt = compact(request.displayText ?? request.text)
    let existingTitle = request.conversationId.flatMap { id in
      runs.first(where: { $0.conversationId == id })?.chatTitle
    }
    let chatTitle = conversationTitle ?? existingTitle ?? makeChatTitle(request.displayText ?? request.text)
    upsert(runId) { run in
      run.agent = request.agent ?? run.agent
      run.prompt = prompt
      run.chatTitle = chatTitle
      run.workspacePath = request.workspacePath
      run.isUnread = false
      run.outcome = DetachedRunOutcome()
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
        updatedAt: .now,
        workspacePath: request.workspacePath
      )
    }
  }

  func updateConversationTitle(conversationId: String, title: String) {
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    for index in runs.indices where runs[index].conversationId == conversationId && runs[index].chatTitle != title {
      runs[index].chatTitle = title
    }
  }

  func apply(_ update: AgentActivityUpdate) {
    let matchingRun = update.conversationId.flatMap { id in activeRuns.first { $0.conversationId == id } }
    let runId = update.runId ?? matchingRun?.id ?? (activeRuns.count == 1 ? activeRuns.first?.id : nil)
    guard let runId else { return }
    discardDebugPreviews()

    upsert(runId) { run in
      run.conversationId = update.conversationId ?? run.conversationId
      run.agent = update.event?.agent ?? run.agent
      guard run.state != .stopping && run.state != .stopped && run.state != .completed && run.state != .failed else { return }
      run.status = update.status
      run.toolName = update.toolName ?? update.event?.toolName
      run.event = update.event
      run.outcome.record(update.event)
      if run.state != .awaitingApproval && run.state != .awaitingCredential && run.state != .awaitingInput { run.state = .running }
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

  func waitForAnswer(runId: String, question: String? = nil) {
    update(runId) { run in
      run.state = .awaitingInput
      run.status = question ?? "Waiting for your answer"
      run.toolName = nil
      run.event = nil
      run.updatedAt = .now
    }
  }

  func resumeAfterAnswer(runId: String) {
    update(runId) { run in
      guard run.state == .awaitingInput else { return }
      run.state = .running
      run.status = "Continuing…"
      run.updatedAt = .now
    }
  }

  func complete(runId: String?, conversationId: String) {
    guard let runId = resolvedRealRunId(runId: runId, conversationId: conversationId) else { return }
    update(runId) { run in
      run.conversationId = conversationId
      guard run.state != .failed && run.state != .completed else { return }
      run.state = run.state == .stopping ? .stopped : run.state == .stopped ? .stopped : .completed
      run.isUnread = run.state == .completed
      run.status = run.stateLabel
      run.toolName = nil
      run.event = nil
      run.approval = nil
      run.credential = nil
      run.updatedAt = .now
    }
    onUnreadChange?(unreadRuns)
  }

  func fail(runId: String?, message: String) {
    guard let runId = resolvedRealRunId(runId: runId) else { return }
    update(runId) { run in
      guard run.isActive, run.state != .stopping else { return }
      run.status = compact(message)
      run.state = .failed
      run.approval = nil
      run.credential = nil
      run.updatedAt = .now
    }
  }

  func requestStop(runId: String) {
    update(runId) { run in
      guard run.isActive else { return }
      run.state = .stopping
      run.status = "Stopping…"
      run.toolName = nil
      run.event = nil
      run.approval = nil
      run.credential = nil
      run.updatedAt = .now
    }
  }

  func connectionLost(runId: String, message: String) {
    update(runId) { run in
      guard run.isActive else { return }
      run.state = run.state == .stopping ? .stopped : .failed
      run.status = run.state == .stopped ? "Stopped" : compact(message)
      run.approval = nil
      run.credential = nil
      run.event = nil
      run.toolName = nil
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

  func resolveApproval(id: String, status: String = "Continuing agent task") {
    guard let index = runs.firstIndex(where: { $0.approval?.id == id }) else { return }
    runs[index].approval = nil
    runs[index].state = .running
    runs[index].status = status
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
    case .question:
      run = makeRun(id: "debug-question-run", agent: "preview", kind: "status", title: "Clarification preview", status: "Waiting for your answer", state: .awaitingInput)
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
    if let runId {
      return runs.contains(where: { $0.id == runId && !$0.isDebugPreview }) ? runId : nil
    }
    if let conversationId,
      let matchingRun = activeRuns.first(where: { $0.conversationId == conversationId })
    {
      return matchingRun.id
    }
    return activeRuns.count == 1 ? activeRuns.first?.id : nil
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
