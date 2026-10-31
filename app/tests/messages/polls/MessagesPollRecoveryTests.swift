import Foundation

extension MessagesRemoteTests {
  @MainActor static func pollRecoveryTests() async {
    func question(_ fixture: PollFixture, runID: String) {
      fixture.store.begin(ChatRequest(text: "Clarification demo", runId: runID, agent: "codex"))
      AgentQuestionCenter.shared.requests = [.init(id: "request-" + runID, runId: runID,
        conversationId: "demo-conversation-" + runID, agent: "codex", taskTitle: nil, questions: [
          .init(id: "style", header: "Style", question: "Which version should the demo report use?",
            options: [.init(label: "Minimal", description: nil), .init(label: "Detailed", description: nil),
              .init(label: "Both", description: nil)], isSecret: false)
        ])]
      fixture.store.waitForAnswer(runId: runID, question: "Which version?")
    }

    let sequence = PollFixture()
    defer { sequence.close() }
    question(sequence, runID: "FIRST-CLARIFICATION")
    await settlePolls()
    sequence.rpc.vote("POLL-1", id: 2_000, ids: ["option-1"])
    await settlePolls()
    check(AgentQuestionCenter.shared.submitting.contains("request-FIRST-CLARIFICATION"),
      "The first clarification poll submits its real answer")

    sequence.sender.failure = MessagesPollSendFailure.notSubmitted("Verified draft cleared before Return")
    sequence.approval("demo-approval", runID: "SECOND-APPROVAL")
    await settlePolls()
    check(!sequence.controller.pollsPaused && sequence.sender.sent.count == 2,
      "A cleaned-up unsent approval does not disable subsequent polls")
    sequence.rpc.vote("POLL-2", id: 2_001)
    await settlePolls()
    check(sequence.decisions.isEmpty, "A failed approval poll cannot authorize its action")

    sequence.sender.failure = nil
    question(sequence, runID: "THIRD-CLARIFICATION")
    await settlePolls()
    check(sequence.sender.sent.count == 3 && sequence.sender.sent.last?.options == ["Minimal", "Detailed", "Both"],
      "Clarification, failed approval, clarification keeps using native polls")
    check(sequence.controller.pollStatus == nil, "A later successful poll clears the previous transient error")
    check(!sequence.rpc.sent.joined().contains("Choose: choose"),
      "Recovery never silently emits the numbered clarification fallback")
    sequence.rpc.vote("POLL-3", id: 2_002, ids: ["option-2"])
    await settlePolls()
    check(AgentQuestionCenter.shared.drafts["request-THIRD-CLARIFICATION"]?["style"] == "Both",
      "The later clarification vote still reaches the correct request")

    let queued = PollFixture()
    defer { queued.close() }
    queued.sender.delay = 30_000_000
    queued.sender.failure = MessagesPollSendFailure.notSubmitted("Unsent draft removed")
    queued.sender.onSending = { [weak queued] _, _ in
      if queued?.sender.sent.count == 2 { queued?.sender.failure = nil }
    }
    queued.approval("queued-a", runID: "QUEUE-A")
    queued.approval("queued-b", runID: "QUEUE-B")
    await settlePolls(200_000_000)
    check(queued.sender.sent.count == 2 && queued.sender.maximumInFlight == 1,
      "A recoverable failure releases the queue for the next agent without overlapping automation")
    queued.rpc.vote("POLL-2", id: 2_003, ids: ["option-1"])
    await settlePolls()
    check(queued.decisions.first?.0 == "queued-b" && queued.decisions.first?.1 == false,
      "The second queued approval retains its own callback after the first fails")

    let uncertain = PollFixture()
    defer { uncertain.close() }
    uncertain.sender.failure = MessagesPollSendFailure.needsReview("Return was attempted")
    uncertain.approval()
    await settlePolls()
    check(uncertain.controller.pollsPaused, "An uncertain submission still requires review before another attempt")
    question(uncertain, runID: "AFTER-UNCERTAIN")
    await settlePolls()
    check(uncertain.sender.sent.count == 1 && uncertain.rpc.sent.last?.contains("Resume interactive polls") == true,
      "An unresolved submission explains recovery without another native send")
    check(!uncertain.rpc.sent.joined().contains("Choose: choose") &&
      !uncertain.rpc.sent.joined().contains("Minimal"),
      "Paused native polls use a compact notice instead of dumping choices and command codes")

    let noAccess = PollFixture()
    defer { noAccess.close() }
    noAccess.sender.hasAccess = false
    noAccess.controller.refreshPollAccess()
    question(noAccess, runID: "NO-ACCESS")
    await settlePolls()
    check(noAccess.sender.sent.isEmpty && noAccess.rpc.sent.last?.contains("Allow Detach") == true &&
      !noAccess.rpc.sent.joined().contains("Choose: choose"),
      "A clarification with missing Accessibility access stays compact and explains the next step")

    #if DEBUG
    let delivery = PollFixture()
    defer { delivery.close() }
    delivery.sender.delay = 20_000_000
    delivery.controller.sendConsecutiveTestPolls()
    delivery.controller.sendConsecutiveTestPolls()
    await settlePolls(200_000_000)
    check(delivery.sender.sent.map { $0.options.count } == [3, 2] && delivery.sender.maximumInFlight == 1,
      "The Debug delivery check serializes exactly two differently sized polls and rejects double clicks")
    check(delivery.sender.sent.allSatisfy { if case .test = $0.target { return true }; return false },
      "Both delivery checks are harmless test targets rather than native agent permissions")
    delivery.rpc.vote("POLL-2", id: 3_000)
    await settlePolls()
    check(delivery.decisions.isEmpty && delivery.controller.pollStatus?.contains("Approve once") == true,
      "Voting Approve in the delivery check confirms reception without approving any agent action")
    #endif
  }
}
