import Foundation

@main
struct IslandRunStateTests {
  @MainActor static func main() {
    UnreadResultTests.run()
    TaskInteractionTests.run()
    let store = DetachedRunStore(), controls = DetachedRunControls()
    let codex = WebSocketManager(), claude = WebSocketManager()
    let request = ChatRequest(text: "Fix the build", runId: "a", workspacePath: "/project",
      attachmentContext: "Selected reference", permissionMode: "supervised",
      model: "original-model", agent: "codex", modelSettings: .init(reasoningEffort: "high"),
      mcpServerIds: ["browser"])
    let other = ChatRequest(text: "Update the website", runId: "b", agent: "claude")
    store.begin(request); store.begin(other)
    codex.activeChatRequest = request; claude.activeChatRequest = other
    store.apply(.init(runId: nil, conversationId: nil, status: "Ambiguous event", toolName: nil, event: nil))
    assert(!store.runs.contains { $0.status == "Ambiguous event" }, "Unscoped events cannot pick an arbitrary task")
    controls.register(request, manager: codex); controls.register(other, manager: claude)
    store.apply(.init(runId: "a", conversationId: "chat-a", status: "Reading files", toolName: "read", event: nil))
    store.apply(.init(runId: "b", conversationId: "chat-b", status: "Editing", toolName: nil, event: nil))
    codex.currentConversationId = "chat-a"; claude.currentConversationId = "chat-b"
    let run = store.runs.first { $0.id == "a" }!
    assert(controls.canStop(run))
    controls.stop(run)
    assert(codex.stopped == 1 && claude.stopped == 0, "Stop must target only its owner")
    store.requestStop(runId: "a")
    store.apply(.init(runId: "a", conversationId: "chat-a", status: "Late heartbeat", toolName: nil, event: nil))
    store.fail(runId: "a", message: "Cancelled")
    assert(store.runs.first { $0.id == "a" }?.state == .stopping)
    store.complete(runId: "a", conversationId: "chat-a")
    var stopped = store.runs.first { $0.id == "a" }!
    assert(stopped.state == .stopped && stopped.stateLabel == "Stopped")
    assert(!controls.canResume(stopped), "Wait until the socket has drained the stopped turn")
    codex.isStoppingRun = false
    assert(controls.canResume(stopped))
    controls.resume(stopped)
    assert(codex.resumed?.conversationId == "chat-a" && claude.resumed == nil)
    assert(codex.resumed?.runId != request.runId && codex.resumed?.displayText == "Continue task")
    assert(codex.resumed?.agent == "codex")
    assert(codex.resumed?.model == "original-model")
    assert(codex.resumed?.workspacePath == "/project")
    assert(codex.resumed?.permissionMode == "supervised")
    assert(codex.resumed?.attachmentContext == "Selected reference")
    assert(codex.resumed?.mcpServerIds == ["browser"])
    assert(codex.resumed?.modelSettings?.reasoningEffort == "high")
    assert(!controls.canResume(stopped), "No overlapping resume")
    codex.isStreaming = false; codex.currentConversationId = "different-chat"
    assert(!controls.canResume(stopped), "Never hijack an owner that has moved to another chat")
    codex.currentConversationId = "chat-a"; codex.isConnected = false
    assert(!controls.canResume(stopped))

    store.begin(ChatRequest(text: "Continue task", runId: "a2", conversationId: "chat-a", agent: "codex"))
    assert(store.runs.last?.taskTitle == "Fix the build", "Follow-ups must retain the conversation title")
    store.updateConversationTitle(conversationId: "chat-a", title: "Fix Mac Build Failures")
    assert(store.runs.filter { $0.conversationId == "chat-a" }.allSatisfy { $0.taskTitle == "Fix Mac Build Failures" })
    assert(store.runs.first { $0.id == "b" }?.taskTitle == "Update the website")
    assert(store.presentationRuns.filter { $0.conversationId == "chat-a" }.count == 1)
    store.waitForAnswer(runId: "b")
    store.apply(.init(runId: "b", conversationId: "chat-b", status: "Heartbeat", toolName: "read", event: nil))
    assert(store.runs.first { $0.id == "b" }?.state == .awaitingInput)
    assert(store.presentationRuns.first?.id == "b", "Blocked work should be easy to find")
    store.complete(runId: "not-a-real-run", conversationId: "unknown")
    store.complete(runId: "not-a-real-run", conversationId: "chat-a")
    assert(store.runs.last?.state == .running, "Foreign terminal events cannot finish another task")
    store.fail(runId: "a2", message: "Build failed")
    store.complete(runId: "a2", conversationId: "chat-a")
    assert(store.runs.last?.state == .failed, "Runtime done after error must not erase the failure")
    store.begin(ChatRequest(text: "Second prompt", runId: "historic", conversationId: "old-chat", agent: "fx"),
      conversationTitle: "A saved conversation")
    assert(store.runs.last?.taskTitle == "A saved conversation")
    store.requestStop(runId: "historic")
    store.connectionLost(runId: "historic", message: "Disconnected")
    assert(store.runs.last?.state == .stopped, "A lost socket must not leave a task stuck stopping")
    let longTitle = String(repeating: "A", count: 120)
    store.begin(ChatRequest(text: longTitle, runId: "long-title", agent: "codex"))
    assert(store.runs.last?.taskTitle == String(repeating: "A", count: 97) + "...")
    stopped = store.runs.first { $0.id == "a" }!
    assert(stopped.state == .stopped && store.hasRecoverableRuns)
    assert(ActivityIslandContentLayout.size(taskCount: 12, hasQuestion: true, hasApproval: true,
      hasCredential: true).height < 600)
    print("Notch run lifecycle, titles, concurrent task routing, and resume context checks passed")
  }
}
