import Foundation

@MainActor final class FixturePollSender: MessagesPollSending {
  var hasAccess = true
  var sent: [MessagesPollDecision] = []
  var delay: UInt64 = 0
  var failure: Error?
  var guidOverride: String?
  var optionIDs: [String]?
  var inFlight = 0
  var maximumInFlight = 0
  var onSending: ((MessagesPollDecision, String) -> Void)?

  func send(_ decision: MessagesPollDecision, chatID: Int, recipient: String,
    isPending: @escaping () -> Bool) async throws -> MessagesCreatedPoll {
    guard isPending() else { throw CancellationError() }
    sent.append(decision)
    inFlight += 1
    maximumInFlight = max(maximumInFlight, inFlight)
    defer { inFlight -= 1 }
    let guid = guidOverride ?? "POLL-\(sent.count)"
    onSending?(decision, guid)
    if delay > 0 { try await Task.sleep(nanoseconds: delay) }
    if let failure { throw failure }
    guard isPending() else { throw CancellationError() }
    return MessagesCreatedPoll(guid: guid, options: decision.options.enumerated().map {
      .init(id: optionIDs?[$0.offset] ?? "option-\($0.offset)", text: $0.element)
    })
  }
}

extension FixtureMessagesRPC {
  func vote(_ guid: String, id: Int, ids: [String] = ["option-0"], sender: String = "+14155550123",
    chatID: Int = 42, fromMe: Bool = false, group: Bool = false, subscription: Int? = nil,
    participants: [String]? = nil, kind: String = "vote", eventType: String = "selected") {
    var poll: [String: Any] = ["kind": kind, "poll_guid": guid, "original_guid": guid]
    if !ids.isEmpty {
      poll["votes"] = ids.enumerated().map { index, id in
        ["option_id": id, "participant": participants?[index] ?? sender, "event_type": eventType]
      }
      poll["vote"] = ["option_id": ids[0], "participant": sender]
    }
    onMessage?(["jsonrpc": "2.0", "method": "message", "params": [
      "subscription": subscription ?? self.subscription,
      "message": ["id": id, "chat_id": chatID, "sender": sender, "text": "",
        "is_from_me": fromMe, "is_group": group, "poll": poll]
    ]])
  }
}

@MainActor
final class PollFixture {
  let store = DetachedRunStore()
  let controls = DetachedRunControls()
  let rpc = FixtureMessagesRPC()
  let sender = FixturePollSender()
  let domain = "detach-poll-fixture.\(UUID())"
  let settings: MessagesRemoteSettings
  let controller: MessagesRemoteController
  var decisions: [(String, Bool)] = []

  init() {
    settings = MessagesRemoteSettings(defaults: UserDefaults(suiteName: domain)!)
    settings.pair(chatID: 42, sender: "+14155550123")
    settings.pollsEnabled = true
    controller = MessagesRemoteController(rpc: rpc, settings: settings,
      pollSender: sender, voteDelayNanoseconds: 20_000_000)
    AgentQuestionCenter.shared.requests = []
    AgentQuestionCenter.shared.drafts = [:]
    AgentQuestionCenter.shared.submitting = []
    controller.configure(store: store, controls: controls, approvalResponse: { [weak self] id, allowed in
      guard let self else { return false }
      self.decisions.append((id, allowed))
      self.store.resolveApproval(id: id)
      return true
    })
    controller.resumeIfPaired()
  }

  func approval(_ id: String = "approval-a", runID: String = "AAAAAAAA-1111") {
    store.begin(ChatRequest(text: "Fix the test", runId: runID, agent: "codex"))
    store.requestApproval(id: id, runId: runID, conversationId: nil, command: "git diff --check",
      description: "Check the changes", riskLevel: "normal")
  }

  func close() {
    controller.stop()
    UserDefaults.standard.removePersistentDomain(forName: domain)
    AgentQuestionCenter.shared.requests = []
    AgentQuestionCenter.shared.drafts = [:]
    AgentQuestionCenter.shared.submitting = []
  }
}
