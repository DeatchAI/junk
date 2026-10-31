import Foundation

extension MessagesRemoteTests {
  @MainActor static func questionPollTests() async {
    let fixture = PollFixture()
    defer { fixture.close() }
    let task = ChatRequest(text: "Design the page", runId: "QUESTIONS-1", agent: "codex")
    fixture.store.begin(task)
    let request = AgentQuestionEnvelope(id: "native-questions", runId: task.runId!, conversationId: "original",
      agent: "codex", taskTitle: "Design the page", questions: [
        .init(id: "style", header: "Style", question: "Which style?",
          options: [.init(label: "Minimal", description: nil), .init(label: "Detailed", description: nil)], isSecret: false),
        .init(id: "theme", header: "Theme", question: "Which theme?",
          options: [.init(label: "Light", description: nil), .init(label: "Dark", description: nil)], isSecret: false)
      ])
    let center = AgentQuestionCenter.shared
    center.requests = [request]
    fixture.store.waitForAnswer(runId: task.runId!, question: "Which style?")
    await settlePolls()
    check(fixture.sender.sent.count == 2, "A multi-question request emits one poll per choice question")
    fixture.rpc.vote("POLL-1", id: 900, ids: ["option-1"])
    await settlePolls()
    check(center.drafts[request.id]?["style"] == "Detailed", "The first poll saves the exact native option label")
    check(!center.submitting.contains(request.id), "A partial multi-question answer is not submitted")
    fixture.rpc.vote("POLL-2", id: 901)
    await settlePolls()
    check(center.drafts[request.id]?["theme"] == "Light" && center.submitting.contains(request.id),
      "All answers submit through the existing native request ID")
    fixture.rpc.vote("POLL-2", id: 902, ids: ["option-1"])
    await settlePolls()
    check(center.drafts[request.id]?["theme"] == "Light", "A consumed question poll cannot change a submitted answer")

    let secret = PollFixture()
    defer { secret.close() }
    secret.store.begin(ChatRequest(text: "Private", runId: "PRIVATE-1", agent: "codex"))
    center.requests = [.init(id: "private-request", runId: "PRIVATE-1", conversationId: "private",
      agent: "codex", taskTitle: nil, questions: [
        .init(id: "secret", header: "Private", question: "Fixture private prompt",
          options: [.init(label: "Sensitive", description: nil), .init(label: "Other", description: nil)], isSecret: true)
      ])]
    secret.store.waitForAnswer(runId: "PRIVATE-1", question: "Private input")
    await settlePolls()
    check(secret.sender.sent.isEmpty && !secret.rpc.sent.joined().contains("Fixture private prompt"),
      "Private prompts and options never leave the Mac")

    let mixed = PollFixture()
    defer { mixed.close() }
    mixed.store.begin(ChatRequest(text: "Mixed", runId: "MIXED-1", agent: "codex"))
    center.requests = [.init(id: "mixed-request", runId: "MIXED-1", conversationId: "mixed",
      agent: "codex", taskTitle: nil, questions: [
        .init(id: "choice", header: "Choice", question: "Choose a size",
          options: [.init(label: "Small", description: nil), .init(label: "Large", description: nil)], isSecret: false),
        .init(id: "text", header: "Text", question: "What should it say?", options: nil, isSecret: false)
      ])]
    mixed.store.waitForAnswer(runId: "MIXED-1", question: "Choose a size")
    await settlePolls()
    check(mixed.sender.sent.count == 1, "Mixed requests still get their eligible native poll")
    check(mixed.rpc.sent.joined().contains("What should it say?") && !mixed.rpc.sent.joined().contains("Choose a size"),
      "Only the free-text question gets a text fallback")

    let long = PollFixture()
    defer { long.close() }
    long.store.begin(ChatRequest(text: "Long action", runId: "LONG-1", agent: "codex"))
    let command = "python -c " + String(repeating: "fixture-code ", count: 200)
    long.store.requestApproval(id: "long-approval", runId: "LONG-1", conversationId: nil,
      command: command, description: "Update the icon", riskLevel: "normal")
    await settlePolls()
    check(long.sender.sent.first?.details?.contains(command) == true, "Long commands retain their full review details")
    check(long.sender.sent.first?.caption.count ?? 10_000 < 1_000, "Long actions use a compact poll caption")
    check(long.sender.sent.first?.caption.contains("Read the attached details") == true,
      "The phone user is directed to review full details before voting")

    var applied = 0
    let sender = FixturePollSender()
    let coordinator = MessagesPollCoordinator(sender: sender, isPending: { _ in true },
      apply: { _, _ in applied += 1; return true }, notice: { _ in }, settleNanoseconds: 70_000_000)
    let base = MessagesPollDecision.make(target: .test, heading: "Expiry", question: "Choose",
      options: ["A", "B"], lifetime: 300)!
    let expiring = MessagesPollDecision(id: base.id, target: base.target, caption: base.caption,
      options: base.options, details: nil, expiresAt: .now.addingTimeInterval(0.04))
    try! await coordinator.send(expiring, chatID: 42, recipient: "+14155550123")
    let rpc = FixtureMessagesRPC()
    rpc.onMessage = { if let message = MessagesIncomingMessage($0) { coordinator.receive(message) } }
    rpc.vote("POLL-1", id: 1_000)
    await settlePolls(100_000_000)
    check(applied == 0, "A decision expiring during vote settling cannot dispatch")
    coordinator.reset()
  }
}
