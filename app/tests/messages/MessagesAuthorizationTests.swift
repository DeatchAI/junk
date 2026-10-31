import Foundation

extension MessagesRemoteTests {
  @MainActor static func authorizationTests() {
    let (controller, rpc, _, domain) = fixture()
    defer { controller.stop(); UserDefaults.standard.removePersistentDomain(forName: domain) }
    let store = DetachedRunStore(), controls = DetachedRunControls()
    var decisions: [(String, Bool)] = []
    controller.configure(store: store, controls: controls, approvalResponse: {
      decisions.append(($0, $1)); return true
    })
    controller.beginPairing(agentAddress: "agent@example.com")
    rpc.emit(controller.pairing!.messageText)
    let task = ChatRequest(text: "Task", runId: "AAAAAAAA-1111", agent: "codex")
    store.begin(task)
    store.requestApproval(id: "approval-native", runId: task.runId, conversationId: nil,
      command: "git push", description: "Push reviewed changes", riskLevel: "normal")
    drain()
    let notification = rpc.sent.last!
    let code = notification.components(separatedBy: "approve ")[1].components(separatedBy: "\n")[0]
    rpc.emit("approve \(code)", id: 30, sender: "outsider@example.com")
    rpc.emit("approve \(code)", id: 31, fromMe: true)
    rpc.emit("approve \(code)", id: 32, chatID: 99)
    rpc.emit("approve \(code)", id: 33, group: true)
    check(decisions.isEmpty, "Other senders, echoes, chats and groups cannot grant a decision")
    rpc.emit("approve \(code)", id: 34)
    check(decisions.count == 1 && decisions[0].0 == "approval-native" && decisions[0].1,
      "Only the paired sender in the verified conversation can respond to a native approval")
    rpc.emit("approve \(code)", id: 35)
    check(decisions.count == 1, "Even another delivered message cannot repeat a consumed approval")
  }
}
