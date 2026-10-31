import CoreImage
import Foundation

@main
struct MessagesRemoteTests {
  @MainActor static var checks = 0
  @MainActor static func check(_ condition: @autoclosure () -> Bool, _ description: String) {
    guard condition() else { fatalError(description) }
    checks += 1
  }

  @MainActor static func main() async throws {
    try pairingTests()
    metadataTests()
    accountTests()
    decisionTests()
    authorizationTests()
    activityTests()
    controlTests()
    await pollTests()
    print("Messages Remote: \(checks) checks passed")
  }

  @MainActor static func fixture() -> (MessagesRemoteController, FixtureMessagesRPC, MessagesRemoteSettings, String) {
    let name = "detach-messages-test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    let settings = MessagesRemoteSettings(defaults: defaults)
    let rpc = FixtureMessagesRPC()
    return (MessagesRemoteController(rpc: rpc, settings: settings), rpc, settings, name)
  }

  @MainActor static func pairingTests() throws {
    let now = Date()
    let session = MessagesPairingSession(agentAddress: "agent+tag@example.com", now: now,
      token: "0123456789ABCDEF0123456789ABCDEF")!
    check(session.accepts(session.messageText.lowercased(), at: now), "Pairing is case insensitive")
    check(!session.accepts(session.messageText, at: now.addingTimeInterval(301)), "Pairing expires")
    check(!session.accepts("pair 153403", at: now), "Old screenshot code is rejected")
    check(MessagesPairingSession(agentAddress: "bad address") == nil, "Invalid QR recipient is rejected")
    check(URLComponents(url: session.composeURL, resolvingAgainstBaseURL: false)?.queryItems?
      .first(where: { $0.name == "body" })?.value == session.messageText, "QR preserves pairing body")
    check(session.composeURL.absoluteString.contains("agent+tag@example.com"), "QR preserves email alias")
    check(!MessagesIncomingMessage.sameSender("person123@example.com", "+123"), "Email digits cannot match a phone")
    check(MessagesIncomingMessage.sameSender("+1 (415) 555-0123", "+14155550123"), "Phone formatting is normalized")

    let image = MessagesQRCode.image(for: session.composeURL.absoluteString)!
    let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(),
      options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
    let decoded = detector.features(in: CIImage(cgImage: image).transformed(
      by: CGAffineTransform(scaleX: 6, y: 6))).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    check(decoded.contains(session.composeURL.absoluteString), "Rendered QR decodes to the exact recipient and token")

    let (controller, rpc, settings, name) = fixture()
    defer { controller.stop(); UserDefaults.standard.removePersistentDomain(forName: name) }
    rpc.holdWatch = true
    controller.beginPairing(agentAddress: "agent@example.com")
    check(controller.pairing == nil && controller.state == .connecting, "QR is hidden until watch is ready")
    check(rpc.calls.first(where: { $0.0 == "watch.subscribe" })?.1["participants"] == nil,
      "Pairing does not prefilter the phone by a guessed sender")
    rpc.holdWatch = false
    rpc.waitingWatch?(.success(["subscription": rpc.subscription]))
    let pairing = controller.pairing!
    rpc.emit("pair old-code", id: 1)
    check(controller.pairingHint?.contains("not current") == true, "Old codes produce feedback")
    rpc.emit(pairing.messageText, id: 2, fromMe: true)
    check(!controller.isPaired && controller.pairingHint?.contains("sent message") == true, "Own outgoing echoes cannot pair")
    rpc.emit(pairing.messageText, id: 3, group: true)
    check(!controller.isPaired, "Group messages cannot pair")
    rpc.emit(pairing.messageText, id: 4, sender: "+14155550123")
    check(controller.isPaired && controller.state == .ready, "Actual phone sender pairs despite different agent email")
    check(settings.sender == "+14155550123" && settings.chatID == 42, "Actual sender and conversation are persisted")
    check(rpc.sent.count == 1, "One pairing acknowledgement is sent")
    check(rpc.calls.first(where: { $0.0 == "chats.get" })?.1["chat_id"] as? Int == 42,
      "Unqualified watch identifiers are verified using the exact chat metadata")
    let watch = rpc.calls.filter { $0.0 == "watch.subscribe" }.last!
    check(watch.1["chat_id"] as? Int == 42, "After pairing only the verified conversation is watched")
    rpc.emit(pairing.messageText, id: 4)
    rpc.emit("status", id: 5, fromMe: true)
    rpc.emit("status", id: 6, subscription: 1)
    check(rpc.sent.count == 1, "Duplicate messages, echoes, and old subscriptions are ignored")

    let (failed, failedRPC, failedSettings, failedName) = fixture()
    defer { failed.stop(); UserDefaults.standard.removePersistentDomain(forName: failedName) }
    failedRPC.sendFails = true
    failed.beginPairing(agentAddress: "agent@example.com")
    failedRPC.emit(failed.pairing!.messageText)
    check(!failed.isPaired && !failedSettings.enabled, "A failed outbound acknowledgement cannot report Connected")
    check(failed.pairingHint?.contains("reply was not confirmed") == true, "Outbound permission failure is explained")
    check(failedRPC.sent.count == 1, "Delivery timeout is never retried automatically")

    let (cancelled, cancelledRPC, cancelledSettings, cancelledName) = fixture()
    defer { cancelled.stop(); UserDefaults.standard.removePersistentDomain(forName: cancelledName) }
    cancelledRPC.holdSend = true
    cancelled.beginPairing(agentAddress: "agent@example.com")
    cancelledRPC.emit(cancelled.pairing!.messageText)
    check(!cancelled.isPaired, "Waiting for reply is not Connected")
    cancelled.stop()
    cancelledRPC.waitingSend?(.success(["ok": true]))
    check(cancelledSettings.chatID == nil && cancelled.state == .off, "Late callbacks cannot pair after cancellation")
  }

  @MainActor static func metadataTests() {
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("fixtures")
    var nativeEvent = try! JSONSerialization.jsonObject(with:
      Data(contentsOf: fixtures.appendingPathComponent("unqualified-watch.json"))) as! [String: Any]
    let nativeChat = try! JSONSerialization.jsonObject(with:
      Data(contentsOf: fixtures.appendingPathComponent("unqualified-chat.json"))) as! [String: Any]
    var nativeParams = nativeEvent["params"] as! [String: Any]
    var nativeMessage = nativeParams["message"] as! [String: Any]
    check(nativeMessage["service"] == nil
      && (nativeMessage["chat_guid"] as? String)?.hasPrefix("any;") == true
      && nativeChat["service"] as? String == "iMessage",
      "Real bundled-helper fixture proves that GUID prefix is not the chat service")
    let (nativeController, nativeRPC, _, nativeDomain) = fixture()
    defer { nativeController.stop(); UserDefaults.standard.removePersistentDomain(forName: nativeDomain) }
    nativeRPC.chatOverride = nativeChat
    nativeController.beginPairing(agentAddress: "fixture-agent@example.com")
    nativeMessage["text"] = nativeController.pairing!.messageText
    nativeParams["message"] = nativeMessage
    nativeParams["subscription"] = nativeRPC.subscription
    nativeEvent["params"] = nativeParams
    nativeRPC.onMessage?(nativeEvent)
    check(nativeController.isPaired && nativeRPC.sent.count == 1,
      "Driver-produced unqualified payload completes verified pairing")

    let (controller, rpc, _, name) = fixture()
    defer { controller.stop(); UserDefaults.standard.removePersistentDomain(forName: name) }
    controller.beginPairing(agentAddress: "agent@example.com")
    rpc.emit(controller.pairing!.messageText, chatGUID: "")
    check(controller.isPaired, "A missing GUID prefix cannot reject an otherwise verified iMessage")
    let store = DetachedRunStore(), controls = DetachedRunControls()
    controller.configure(store: store, controls: controls)
    rpc.emit("status", id: 11, chatGUID: "any;-;agent@example.com")
    check(rpc.sent.last?.contains("No live activities") == true,
      "Commands from the paired chat do not rely on an iMessage GUID prefix")

    for service in ["SMS", "RCS", "any", ""] {
      let (candidate, transport, settings, domain) = fixture()
      transport.chatService = service
      candidate.beginPairing(agentAddress: "agent@example.com")
      transport.emit(candidate.pairing!.messageText, chatGUID: "iMessage;-;agent@example.com")
      check(!candidate.isPaired && !settings.enabled && transport.sent.isEmpty,
        "A GUID prefix cannot override an unverified or non-iMessage chat service")
      check(candidate.state == .pairing && candidate.pairingHint != nil,
        "Rejected chat metadata leaves an actionable pairing status")
      candidate.stop()
      UserDefaults.standard.removePersistentDomain(forName: domain)
    }

    let (group, groupRPC, _, groupDomain) = fixture()
    defer { group.stop(); UserDefaults.standard.removePersistentDomain(forName: groupDomain) }
    groupRPC.chatIsGroup = true
    group.beginPairing(agentAddress: "agent@example.com")
    groupRPC.emit(group.pairing!.messageText, group: false)
    check(!group.isPaired && groupRPC.sent.isEmpty, "Authoritative group metadata overrides direct-shaped notifications")

    let (outsider, outsiderRPC, _, outsiderDomain) = fixture()
    defer { outsider.stop(); UserDefaults.standard.removePersistentDomain(forName: outsiderDomain) }
    outsiderRPC.chatParticipants = ["another@example.com"]
    outsider.beginPairing(agentAddress: "agent@example.com")
    outsiderRPC.emit(outsider.pairing!.messageText)
    check(!outsider.isPaired && outsiderRPC.sent.isEmpty, "Sender must be in the exact verified chat")

    let (cancelled, cancelledRPC, settings, cancelledDomain) = fixture()
    defer { cancelled.stop(); UserDefaults.standard.removePersistentDomain(forName: cancelledDomain) }
    cancelledRPC.holdChatLookup = true
    cancelled.beginPairing(agentAddress: "agent@example.com")
    cancelledRPC.emit(cancelled.pairing!.messageText)
    check(cancelled.state == .connecting && !cancelled.isPaired, "Metadata lookup does not prematurely report Connected")
    cancelled.stop()
    cancelledRPC.waitingChat?(.success(["id": 42, "service": "iMessage",
      "is_group": false, "participants": ["+14155550123"]]))
    check(settings.chatID == nil && cancelledRPC.sent.isEmpty, "Cancelled metadata callbacks cannot pair or send")
  }

  @MainActor static func drain() { RunLoop.current.run(until: Date().addingTimeInterval(0.03)) }

  @MainActor static func activityTests() {
    let store = DetachedRunStore()
    var forwarded: [String] = []
    let relay = MessagesActivityRelay(store: store) { forwarded.append($0) }
    var questionID = "question-one"
    relay.questionIdentity = { _ in questionID }
    relay.setEnabled(true)
    let a = ChatRequest(text: "Fix app", runId: "AAAAAAAA-1111", workspacePath: "/Projects/App", agent: "codex")
    let b = ChatRequest(text: "Update docs", runId: "BBBBBBBB-2222", workspacePath: "/Projects/Docs", agent: "claude")
    store.begin(a); store.begin(b)
    for index in 1...8 {
      store.begin(.init(text: "Task \(index)", runId: "parallel-\(index)", agent: "codex"))
    }
    drain()
    check(forwarded.isEmpty, "Starting ten agents sends no automatic messages")
    for index in 1...30 {
      let event = try! JSONDecoder().decode(AgentActivityEvent.self,
        from: Data("{\"agent\":\"codex\",\"kind\":\"command\",\"phase\":\"started\",\"title\":\"Running check \(index)\",\"userFacing\":true}".utf8))
      store.apply(.init(runId: a.runId, conversationId: nil, status: "Progress \(index)", toolName: nil,
        event: event))
      drain()
    }
    check(forwarded.isEmpty, "Every progress event stays silent, including user-facing tool changes")
    store.waitForAnswer(runId: a.runId!, question: "Which variant?"); drain()
    check(forwarded.count == 1 && forwarded.last?.contains("Needs your answer") == true,
      "A clarification sends one notification")
    store.waitForAnswer(runId: a.runId!, question: "Same request, revised title"); drain()
    check(forwarded.count == 1, "Question title updates do not duplicate the same request")
    questionID = "question-two"
    store.waitForAnswer(runId: a.runId!, question: "Same request, revised title"); drain()
    check(forwarded.count == 2, "A new question request is not hidden by identical wording")
    store.resumeAfterAnswer(runId: a.runId!); drain()
    check(forwarded.count == 2, "Returning to work sends no message")
    store.requestApproval(id: "approval-one", runId: a.runId, conversationId: nil,
      command: "git push", description: "Push changes", riskLevel: "normal"); drain()
    check(forwarded.count == 3 && forwarded.last?.contains("Approval needed") == true,
      "A pending approval is forwarded once")
    store.requestApproval(id: "approval-one", runId: a.runId, conversationId: nil,
      command: "git push", description: "Push changes", riskLevel: "normal"); drain()
    check(forwarded.count == 3, "Repeated pending approvals do not duplicate notifications")
    store.resolveApproval(id: "approval-one"); drain()
    let result = String(repeating: "Earlier progress and planning. ", count: 500) + "\n\nFixed the login issue."
    relay.recordResult(runID: a.runId!, text: result)
    store.complete(runId: a.runId, conversationId: "conv-a"); drain()
    check(forwarded.count == 4 && forwarded.last?.contains("Fixed the login issue.") == true,
      "One compact result includes the concluding response")
    check(forwarded.last!.count < 1_500 && !forwarded.last!.contains("Earlier progress and planning."),
      "A long transcript is a bounded ending excerpt, not several message chunks")
    store.markReviewed(conversationId: "conv-a"); drain()
    check(forwarded.count == 4, "Reviewing a result does not resend it")
    store.fail(runId: b.runId, message: "Provider disconnected"); drain()
    check(forwarded.count == 5 && forwarded.last?.contains("Provider disconnected") == true,
      "A failed task sends one terminal outcome")
    check(forwarded.contains { $0.contains("App") } && forwarded.contains { $0.contains("Docs") },
      "Outcomes from every project use the same channel")
    relay.setEnabled(false)
    store.begin(.init(text: "Off", runId: "CCCCCCCC-3333", workspacePath: "/Other", agent: "pi")); drain()
    check(forwarded.count == 5, "Disabling forwarding takes effect")
    relay.setEnabled(true); drain()
    check(forwarded.count == 5, "Reconnect stays quiet for working agents and old completions")
  }

  @MainActor static func controlTests() {
    let store = DetachedRunStore(), controls = DetachedRunControls()
    let a = ChatRequest(text: "Task A", runId: "AAAAAAAA-1111", conversationId: "conv-a",
      workspacePath: "/Projects/A", permissionMode: "default", model: "original-model", agent: "codex",
      mcpServerIds: ["original-tools"])
    let b = ChatRequest(text: "Task B", runId: "BBBBBBBB-2222", conversationId: "conv-b",
      workspacePath: "/Projects/B", agent: "claude")
    let first = WebSocketManager(), second = WebSocketManager()
    first.activeChatRequest = a; first.currentConversationId = "conv-a"
    second.activeChatRequest = b; second.currentConversationId = "conv-b"
    controls.register(a, manager: first); controls.register(b, manager: second)
    store.begin(a); store.begin(b)
    var replies: [String] = []
    let questions = AgentQuestionCenter()
    let commands = MessagesActivityCommands(store: store, controls: controls, questions: questions) { replies.append($0) }
    commands.handle("stop BBBBBBBB")
    check(first.stopped == 0 && second.stopped == 1, "Stop targets the selected activity owner")
    store.complete(runId: a.runId, conversationId: "conv-a"); first.isStreaming = false
    commands.handle("reply AAAAAAAA Please add keyboard support")
    check(first.resumed?.text == "Please add keyboard support", "Phone follow-up reaches the existing task")
    check(first.resumed?.agent == "codex" && first.resumed?.workspacePath == "/Projects/A", "Follow-up retains provider and project")
    check(first.resumed?.permissionMode == "default" && first.resumed?.model == "original-model"
      && first.resumed?.mcpServerIds == ["original-tools"], "Follow-up retains permissions and capabilities")
    check(second.resumed == nil, "Follow-up cannot switch to a different agent")
    let request = AgentQuestionEnvelope(id: "question-request", runId: b.runId!, conversationId: "conv-b",
      agent: "claude", taskTitle: "Task B", questions: [
        .init(id: "q1", header: "Choose", question: "Which color?", options: nil, isSecret: false)
      ])
    questions.requests = [request]
    store.waitForAnswer(runId: b.runId!, question: "Which color?")
    commands.handle("reply BBBBBBBB monochrome")
    check(questions.submitted == request.id && questions.drafts[request.id]?["q1"] == "monochrome",
      "Question replies preserve the exact request and question IDs")
    let secret = AgentQuestionEnvelope(id: "secret", runId: b.runId!, conversationId: "conv-b",
      agent: "claude", taskTitle: "Secret", questions: [
        .init(id: "s1", header: "Private", question: "Sensitive prompt", options: nil, isSecret: true)
      ])
    questions.requests = [secret]; questions.submitting.removeAll()
    check(!commands.questionText(for: store.runs.first { $0.id == b.runId }!)!.contains("Sensitive prompt"),
      "Private question content is not forwarded")
    commands.handle("reply BBBBBBBB private-value")
    check(questions.drafts[secret.id] == nil, "Private answers are not accepted over Messages")
    commands.handle("start new work")
    check(replies.last?.contains("every project") == true, "Messages Remote has no standalone project session")
  }
}
