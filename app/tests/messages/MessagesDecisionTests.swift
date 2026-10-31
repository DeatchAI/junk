import Foundation

extension MessagesRemoteTests {
  @MainActor static func accountTests() {
    let nativeFixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("fixtures/account-routing.json")
    let nativeRouting = try! JSONSerialization.jsonObject(with: Data(contentsOf: nativeFixture)) as! [String: Any]
    check(MessagesAccountDiscovery.address(in: nativeRouting) == "fixture-agent@example.com",
      "Actual bundled-driver routing output supplies the synthetic Mac address")
    let response: [String: Any] = ["chats": [
      ["service": "iMessage", "account_login": "E:agent@example.com", "participants": ["someone@example.com"]],
      ["service": "iMessage", "last_addressed_handle": "agent@example.com"],
      ["service": "SMS", "account_login": "+14155550123"]
    ]]
    check(MessagesAccountDiscovery.address(in: response) == "agent@example.com",
      "Only the local iMessage routing address is suggested, not a contact or SMS identity")
    check(MessagesAccountDiscovery.address(in: ["chats": [
      ["service": "iMessage", "last_addressed_handle": "P:+14155550123"]]]) == "+14155550123",
      "Telephone routing prefixes are handled")
    check(MessagesAccountDiscovery.address(in: ["chats": [
      ["service": "iMessage", "account_login": "E:old@example.com"],
      ["service": "iMessage", "account_login": "E:new@example.com"]]]) == nil,
      "Historical accounts are not silently guessed between")
    check(MessagesAccountDiscovery.address(in: ["chats": [
      ["service": "iMessage", "account_login": "not-an-address", "participants": ["someone@example.com"]]]]) == nil,
      "A participant is never mistaken for the signed-in address")
    let (controller, rpc, _, name) = fixture()
    defer { controller.stop(); UserDefaults.standard.removePersistentDomain(forName: name) }
    rpc.chatListResponse = response
    controller.checkMessagesAccess(offerPairing: true)
    check(controller.pairing?.agentAddress == "agent@example.com", "A usable address opens the QR automatically")
    check(!rpc.calls.contains { $0.0.hasPrefix("messages.") }, "Address discovery never loads message history")
    let token = controller.pairing!.token
    controller.checkMessagesAccess(offerPairing: true)
    check(controller.pairing?.token == token, "Checking access does not replace a live QR")
    controller.stop()
    rpc.holdAccountLookup = true
    // A stored explicit address is reused without repeatedly querying historical chats.
    controller.checkMessagesAccess(offerPairing: true)
    check(controller.pairing?.agentAddress == "agent@example.com", "Saved setup opens directly at the QR")

    let (missing, missingRPC, _, missingName) = fixture()
    defer { missing.stop(); UserDefaults.standard.removePersistentDomain(forName: missingName) }
    missingRPC.chatListResponse = ["chats": []]
    missing.checkMessagesAccess(offerPairing: true)
    check(missing.pairing == nil && missing.state == .needsSetup,
      "A new or unavailable account falls back to a single address field")

    let (cancelled, cancelledRPC, _, cancelledName) = fixture()
    defer { cancelled.stop(); UserDefaults.standard.removePersistentDomain(forName: cancelledName) }
    cancelledRPC.holdAccountLookup = true
    cancelled.checkMessagesAccess(offerPairing: true)
    cancelled.stop()
    cancelledRPC.waitingAccount?(.success(response))
    check(cancelled.pairing == nil && cancelled.agentAddress.isEmpty, "Late discovery cannot recreate a cancelled QR")

    let (denied, deniedRPC, _, deniedName) = fixture()
    defer { denied.stop(); UserDefaults.standard.removePersistentDomain(forName: deniedName) }
    deniedRPC.statusReady = false
    denied.checkMessagesAccess(offerPairing: true)
    check(denied.state == .needsPermission && !deniedRPC.calls.contains { $0.0 == "chats.list" },
      "Account lookup does not proceed without database access")
  }

  @MainActor static func decisionTests() {
    let choices = MessagesDecisionChoices()
    let now = Date()
    let pending = MessagesDecisionChoices.Choice.approval(runID: "run", requestID: "approval")
    let token = choices.code(for: pending, at: now)
    check(choices.choice(for: token.lowercased(), at: now) == pending, "Decision codes are case insensitive")
    check(choices.choice(for: token, at: now.addingTimeInterval(60)) == nil, "Approval codes expire within the native deadline")
    choices.reset()
    check(choices.choice(for: token, at: now) == nil, "Disconnect clears outstanding decisions")

    let store = DetachedRunStore(), controls = DetachedRunControls(), questions = AgentQuestionCenter()
    let task = ChatRequest(text: "Task", runId: "AAAAAAAA-1111", agent: "codex")
    let other = ChatRequest(text: "Other", runId: "BBBBBBBB-2222", agent: "claude")
    store.begin(task); store.begin(other)
    var replies: [String] = [], decisions: [(String, Bool)] = []
    let commands = MessagesActivityCommands(store: store, controls: controls, questions: questions) { replies.append($0) }
    commands.approvalResponse = { id, approved in decisions.append((id, approved)); return true }
    store.requestApproval(id: "native-one", runId: task.runId, conversationId: nil,
      command: "git push", description: "Push reviewed changes", riskLevel: "normal")
    let run = store.runs.first { $0.id == task.runId }!
    let approvalText = commands.approvalText(for: run)!
    let code = approvalText.components(separatedBy: "approve ")[1].components(separatedBy: "\n")[0]
    commands.handle("approve \(code)")
    check(decisions.count == 1 && decisions[0].0 == "native-one" && decisions[0].1,
      "A phone decision targets one exact native approval, not another agent")
    commands.handle("approve \(code)")
    check(decisions.count == 1, "The same decision cannot be submitted twice")
    store.requestApproval(id: "native-two", runId: task.runId, conversationId: nil,
      command: "rm old-file", description: "Remove old file", riskLevel: "normal")
    commands.handle("deny \(code)")
    check(decisions.count == 1, "An old code cannot approve or deny a newer request on the same task")

    let secondRun = store.runs.first { $0.id == task.runId }!
    let secondText = commands.approvalText(for: secondRun)!
    let secondCode = secondText.components(separatedBy: "approve ")[1].components(separatedBy: "\n")[0]
    store.requestApproval(id: "native-three", runId: task.runId, conversationId: nil,
      command: "git push", description: "New operation", riskLevel: "normal")
    commands.handle("approve \(secondCode)")
    check(decisions.count == 1, "An unconsumed approval code cannot authorize a replacement request")
    let thirdRun = store.runs.first { $0.id == task.runId }!
    let thirdCode = commands.approvalText(for: thirdRun)!.components(separatedBy: "approve ")[1].components(separatedBy: "\n")[0]
    store.resolveApproval(id: "native-three")
    commands.handle("approve \(thirdCode)")
    check(decisions.count == 1, "A resolved approval cannot be acted on")

    let request = AgentQuestionEnvelope(id: "request-one", runId: task.runId!, conversationId: "conversation",
      agent: "codex", taskTitle: "Task", questions: [
        .init(id: "q1", header: "Choose", question: "Which variant?",
          options: [.init(label: "Minimal", description: nil), .init(label: "Detailed", description: nil)], isSecret: false)
      ])
    questions.requests = [request]
    store.waitForAnswer(runId: task.runId!, question: "Which variant?")
    let questionRun = store.runs.first { $0.id == task.runId }!
    let text = commands.questionText(for: questionRun)!
    let choiceCode = text.components(separatedBy: "choose ")[1].components(separatedBy: " ")[0]
    check(text.contains("1. Minimal") && text.contains("2. Detailed"), "Question choices are numbered")
    commands.handle("choose \(choiceCode) 2")
    check(questions.submitted == request.id && questions.drafts[request.id]?["q1"] == "Detailed",
      "A choice preserves the native request, question ID, and option label")
    questions.submitting.removeAll()
    questions.requests = [.init(id: "request-two", runId: task.runId!, conversationId: "conversation",
      agent: "codex", taskTitle: "Task", questions: request.questions)]
    commands.handle("choose \(choiceCode) 1")
    check(questions.drafts["request-two"] == nil, "A stale question code cannot answer a replacement prompt")
    check(decisions.count == 1, "Choosing a question never grants unrelated approvals")
  }
}
