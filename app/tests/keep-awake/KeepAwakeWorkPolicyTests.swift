import Foundation

@main struct KeepAwakeWorkPolicyTests {
  @MainActor static func main() {
    let store = DetachedRunStore()
    let first = ChatRequest(text: "First", runId: "first", conversationId: "one", agent: "codex")
    let second = ChatRequest(text: "Second", runId: "second", conversationId: "two", agent: "claude")
    precondition(!KeepAwakeWorkPolicy.isWorking(store.runs))
    store.showDebugScenario(.thinking)
    precondition(!KeepAwakeWorkPolicy.isWorking(store.runs), "Preview tasks cannot keep the Mac awake")
    store.begin(first)
    store.begin(second)
    precondition(KeepAwakeWorkPolicy.isWorking(store.runs))
    store.requestApproval(id: "approval", runId: "first", conversationId: "one",
      command: "test", description: "Review", riskLevel: "low")
    precondition(KeepAwakeWorkPolicy.isWorking(store.runs), "Other work must retain the lease")
    store.waitForAnswer(runId: "second")
    precondition(!KeepAwakeWorkPolicy.isWorking(store.runs), "Waiting alone must not keep the Mac awake")
    store.resumeAfterAnswer(runId: "second")
    precondition(KeepAwakeWorkPolicy.isWorking(store.runs))
    store.requestStop(runId: "second")
    precondition(KeepAwakeWorkPolicy.isWorking(store.runs), "Stopping remains active until cleanup finishes")
    store.complete(runId: "second", conversationId: "two")
    precondition(!KeepAwakeWorkPolicy.isWorking(store.runs))
    print("Keep-awake policy follows real working tasks, waits, previews and concurrent runs")
  }
}
