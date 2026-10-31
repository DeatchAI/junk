import Foundation

enum TaskInteractionTests {
  @MainActor static func run() {
    let store = DetachedRunStore(), state = ActivityIslandTaskState()
    for (id, agent) in [("a", "codex"), ("b", "claude"), ("c", "pi"), ("d", "amp"), ("e", "omp")] {
      store.begin(ChatRequest(text: "Task \(id)", runId: id, conversationId: "chat-\(id)", agent: agent))
    }
    store.waitForAnswer(runId: "c", question: "Which project?")
    store.requestApproval(id: "permission-b", runId: "b", conversationId: "chat-b",
      command: "git push origin main", description: "Publish commits?", riskLevel: "high")
    var ordered = ActivityIslandTaskState.ordered(store.presentationRuns)
    assert(ordered.count == 5 && Set(ordered.map(\.id)).count == 5, "Each task has exactly one entry")
    assert(ordered.prefix(2).allSatisfy(\.needsAttention), "Questions and approvals precede running tasks")
    let question = ordered.first { $0.id == "c" }!
    let approval = ordered.first { $0.id == "b" }!
    state.select(question)
    state.reconcile(ordered)
    assert(state.expandedRunID == "c")
    state.reportHeight(180, for: question.id)
    state.reportHeight(400, for: approval.id)
    assert(state.expandedInteractionHeight == 180,
      "A different task's delayed layout must not resize the active question")
    // A newly interrupted task cannot replace a form the user is editing.
    store.waitForAnswer(runId: "a", question: "Choose a target")
    state.reconcile(store.presentationRuns)
    assert(state.expandedRunID == "c")
    state.toggle(question)
    assert(state.expandedRunID == nil && state.expandedInteractionHeight == nil,
      "Collapsing clears presentation sizing without touching the question")
    assert(store.runs.first { $0.id == "c" }?.state == .awaitingInput)
    state.select(approval)
    var replies: [(String, Bool)] = []
    state.respond(to: approval.approval!, approved: true) { replies.append(($0, $1)) }
    state.respond(to: approval.approval!, approved: false) { replies.append(($0, $1)) }
    assert(replies.count == 1 && replies[0].0 == "permission-b" && replies[0].1,
      "Only an explicit decision is sent, once, with its original request ID")
    state.reconcile(store.presentationRuns)
    assert(state.expandedRunID == "b", "Wait for runtime acknowledgement before collapsing")
    store.resolveApproval(id: "permission-b")
    state.reconcile(store.presentationRuns)
    assert(state.expandedRunID == nil && state.submittingApprovals.isEmpty)
    ordered = ActivityIslandTaskState.ordered(store.presentationRuns)
    assert(ordered.filter(\.needsAttention).count == 2, "Resolving an approval preserves other interruptions")
    state.select(question)
    store.resumeAfterAnswer(runId: "c")
    state.reconcile(store.presentationRuns)
    assert(state.expandedRunID == nil, "A resolved question collapses its existing row")
    store.waitForAnswer(runId: "orphan", question: "Continue?", conversationId: "chat-orphan",
      agent: "future-provider", taskTitle: "Restored task")
    assert(store.presentationRuns.contains { $0.id == "orphan" && $0.taskTitle == "Restored task" },
      "A question arriving before its activity still gets one actionable task row")
    progressChecks()
    print("Inline task identity, interruption ordering, explicit replies, acknowledgements, and reported progress passed")
  }

  private static func progressChecks() {
    func event(_ items: [ActivityJSONValue], visible: Bool = true) -> AgentActivityEvent {
      AgentActivityEvent(id: "plan", agent: "codex", kind: "plan", action: "plan", phase: "updated",
        title: "Updating the plan", subtitle: nil, toolName: "plan", userFacing: visible,
        sourceEventType: nil, sourceItemType: nil, details: ["items": .array(items)])
    }
    let steps: [ActivityJSONValue] = [.object(["completed": .bool(true)]), .object(["completed": .bool(false)])]
    let progress = DetachedRunProgress(event: event(steps))
    assert(progress?.completed == 1 && progress?.total == 2 && progress?.fraction == 0.5)
    assert(DetachedRunProgress(event: nil) == nil)
    assert(DetachedRunProgress(event: event([])) == nil)
    assert(DetachedRunProgress(event: event(steps, visible: false)) == nil, "Private provider data stays private")
    assert(DetachedRunProgress(event: event([.object(["text": .string("Unknown completion")])])) == nil,
      "Unreported completion cannot be guessed")
  }
}
