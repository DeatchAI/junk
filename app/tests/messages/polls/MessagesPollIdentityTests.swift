import Foundation

extension MessagesRemoteTests {
  @MainActor static func pollIdentityTests() {
    let decision = MessagesPollDecision.make(target: .test, heading: "Task", question: "Pick",
      options: ["One", "Two"], lifetime: 60)!
    let poll: [String: Any] = ["kind": "created", "poll_guid": "GUID-1", "question": decision.caption,
      "options": [["id": "a", "text": "One"], ["id": "b", "text": "Two"]]]
    let row: [String: Any] = ["id": 50, "chat_id": 42, "guid": "guid-1", "is_from_me": true, "poll": poll]
    func count(_ value: [String: Any], after: Int = 40) -> Int {
      MessagesNativePollSender.createdPolls(in: ["messages": [value]], after: after,
        decision: decision, chatID: 42).count
    }
    check(count(row) == 1, "Poll binding requires the outgoing row, exact caption, and exact option IDs")
    check(count(row, after: 50) == 0, "A historical poll cannot bind to a new decision")
    for (key, value) in [("chat_id", 99 as Any), ("is_from_me", false as Any), ("guid", "different" as Any)] {
      var other = row; other[key] = value
      check(count(other) == 0, "Wrong \(key) cannot bind an outgoing poll")
    }
    for (key, value) in [("question", "Other" as Any), ("original_guid", "old-poll" as Any),
      ("options", [["id": "a", "text": "One"], ["id": "a", "text": "Two"]] as Any)] {
      var other = row, changed = poll; changed[key] = value; other["poll"] = changed
      check(count(other) == 0, "Ambiguous poll \(key) cannot bind a decision")
    }
    let realCreated = MessagesIncomingMessage(nativePollFixture("native-poll-created.json"))!
    let realVote = MessagesIncomingMessage(nativePollFixture("native-poll-vote.json"))!
    let realUnvote = MessagesIncomingMessage(nativePollFixture("native-poll-unvote.json"))!
    check(realCreated.poll?.question == "Detach synthetic approval [fixture]",
      "Native title-less polls get their caption from the real bundled driver's history output")
    check(realVote.poll?.votes?.count == 2 && realVote.poll?.votes?.last?.optionID == "fixture-no",
      "The actual driver emits the full snapshot, including the paired sender's second entry")
    check(realUnvote.poll?.votes?.isEmpty == true, "The actual driver encodes an empty unvote snapshot safely")

    let store = DetachedRunStore(), controls = DetachedRunControls(), questions = AgentQuestionCenter()
    let commands = MessagesActivityCommands(store: store, controls: controls, questions: questions) { _ in }
    commands.approvalResponse = { _, _ in true }
    let task = ChatRequest(text: "Snapshot", runId: "SNAPSHOT-1", agent: "codex")
    store.begin(task)
    store.requestApproval(id: "unchanged-id", runId: task.runId, conversationId: nil,
      command: "git diff --check", description: "Check", riskLevel: "normal")
    let decisionBefore = commands.polls(for: store.runs[0])[0]
    check(commands.isPending(decisionBefore), "The original native action matches its immutable poll snapshot")
    store.requestApproval(id: "unchanged-id", runId: task.runId, conversationId: nil,
      command: "git push", description: "Push instead", riskLevel: "normal")
    check(!commands.isPending(decisionBefore), "Changed action contents cannot reuse an approval poll even with the same request ID")

    let legacy: [String: Any] = ["kind": "vote", "poll_guid": "guid-1",
      "vote": ["option_id": "a", "participant": "+14155550123"]]
    check(MessagesNativePoll(legacy)?.votes == nil, "The compatibility first-vote field alone never grants authority")
    check(MessagesNativePoll(["kind": "vote", "poll_guid": "guid-1"])?.votes?.isEmpty == true,
      "The pinned driver's empty unvote snapshot is recognized")
    let malformed: [String: Any] = ["kind": "vote", "votes": [
      ["option_id": "a", "participant": "+14155550123"], ["option_id": "b"]]]
    check(MessagesNativePoll(malformed)?.votes == nil, "A partly decoded snapshot is not treated as one valid selection")
    check(MessagesNativePoll.guid("p:0/guid-1") == "GUID-1", "Native part-prefixed poll references normalize exactly")
  }
  @MainActor static func nativePollFixture(_ name: String) -> [String: Any] {
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return try! JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("fixtures/\(name)"))) as! [String: Any]
  }

}
