import Foundation

enum UnreadResultTests {
  @MainActor static func run() {
    let store = DetachedRunStore()
    for index in 0..<7 {
      store.begin(ChatRequest(text: "Task \(index)", runId: "r\(index)", workspacePath: "/projects/App\(index)", agent: "codex"))
      store.complete(runId: "r\(index)", conversationId: "chat\(index)")
    }
    assert(store.unreadRuns.count == 7 && store.presentationRuns.count == 7,
      "Unreviewed results must survive the old three-result presentation limit")
    assert(store.unreadRuns.first?.projectLabel == "App6")
    store.markReviewed(conversationId: "chat6")
    assert(store.unreadRuns.count == 6 && !store.presentationRuns.contains { $0.conversationId == "chat6" })
    store.complete(runId: "r6", conversationId: "chat6")
    assert(store.unreadRuns.count == 6, "A duplicated completion must not re-open a reviewed result")
    store.begin(ChatRequest(text: "Other work", runId: "live", agent: "claude"))
    assert(store.hasActiveRuns && store.hasUnreadResults)
    for index in 0..<6 { store.markReviewed(conversationId: "chat\(index)") }
    assert(!store.hasUnreadResults && store.hasActiveRuns, "Reviewing a result must not disturb another run")

    var outcome = DetachedRunOutcome()
    func event(_ id: String, kind: String, phase: String, details: [String: ActivityJSONValue]?) -> AgentActivityEvent {
      AgentActivityEvent(id: id, agent: "codex", kind: kind, action: nil, phase: phase,
        title: "Work", subtitle: nil, toolName: nil, userFacing: true,
        sourceEventType: nil, sourceItemType: nil, details: details)
    }
    outcome.record(event("test", kind: "command", phase: "completed", details: ["command": .string("bun test"), "exitCode": .number(0)]))
    outcome.record(event("test", kind: "command", phase: "completed", details: ["command": .string("bun test"), "exitCode": .number(0)]))
    outcome.record(event("failed", kind: "command", phase: "completed", details: ["command": .string("bun test"), "exitCode": .number(1)]))
    outcome.record(event("unknown", kind: "command", phase: "completed", details: ["command": .string("bun test")]))
    outcome.record(event("file", kind: "file_change", phase: "completed", details: ["changes": .array([.object(["path": .string("a.swift")])])]))
    assert(outcome.summary == "1 file changed · 1 check passed", "Only explicit, deduplicated successful checks count")
    print("Unread results, review acknowledgement, project identity, and evidence-based summaries passed")
  }
}
