import Foundation

extension MessagesRemoteTests {
  @MainActor static func settlePolls(_ nanoseconds: UInt64 = 90_000_000) async {
    try? await Task.sleep(nanoseconds: nanoseconds)
    drain()
  }

  @MainActor static func pollTests() async {
    let fixture = PollFixture()
    defer { fixture.close() }
    fixture.approval()
    await settlePolls()
    check(fixture.sender.sent.count == 1, "A pending approval emits one native poll")
    check(fixture.rpc.sent.isEmpty, "A native decision does not duplicate the old approval text")
    check(fixture.sender.sent.first?.options == ["Approve once", "Deny"], "Approval options preserve one-time scope")
    check(fixture.sender.sent.first?.caption.contains("git diff --check") == true, "The poll exposes the action being approved")
    fixture.rpc.vote("POLL-1", id: 100, sender: "outsider@example.com")
    fixture.rpc.vote("POLL-1", id: 101, fromMe: true)
    fixture.rpc.vote("POLL-1", id: 102, chatID: 999)
    fixture.rpc.vote("POLL-1", id: 103, group: true)
    fixture.rpc.vote("POLL-1", id: 104, subscription: 999)
    await settlePolls()
    check(fixture.decisions.isEmpty, "Only the paired incoming direct conversation can vote")
    fixture.rpc.vote("POLL-1", id: 105)
    await settlePolls()
    check(fixture.decisions.count == 1 && fixture.decisions[0].0 == "approval-a" && fixture.decisions[0].1,
      "A phone vote reaches the exact native approval callback")
    fixture.rpc.vote("POLL-1", id: 105)
    fixture.rpc.vote("POLL-1", id: 106, ids: ["option-1"])
    await settlePolls()
    check(fixture.decisions.count == 1, "Duplicate and changed votes cannot repeat a consumed approval")

    let changed = PollFixture()
    defer { changed.close() }
    changed.approval()
    await settlePolls()
    changed.rpc.vote("POLL-1", id: 200)
    changed.rpc.vote("POLL-1", id: 201, ids: ["option-1"])
    await settlePolls()
    check(changed.decisions.count == 1 && !changed.decisions[0].1, "A changed vote settles before dispatch")

    let multiple = PollFixture()
    defer { multiple.close() }
    multiple.approval()
    await settlePolls()
    multiple.rpc.vote("POLL-1", id: 300, ids: ["option-0", "option-1"])
    await settlePolls()
    check(multiple.decisions.isEmpty, "Multi-selection cannot grant an approval")
    multiple.rpc.vote("POLL-1", id: 301, ids: ["newly-added-choice"])
    await settlePolls()
    check(multiple.decisions.isEmpty, "An added option is never mapped by display position")
    multiple.rpc.vote("POLL-1", id: 302)
    multiple.rpc.vote("POLL-1", id: 303, ids: [])
    await settlePolls()
    check(multiple.decisions.isEmpty, "Removing a vote cancels its pending dispatch")
    multiple.rpc.vote("POLL-1", id: 304, participants: ["someone-else@example.com"])
    await settlePolls()
    check(multiple.decisions.isEmpty, "Another participant's snapshot cannot authorize the paired sender")
    multiple.rpc.vote("POLL-1", id: 305, ids: ["option-1"])
    await settlePolls()
    check(multiple.decisions.count == 1 && !multiple.decisions[0].1, "A corrected single original choice can deny")

    let stale = PollFixture()
    defer { stale.close() }
    stale.approval()
    await settlePolls()
    stale.store.requestApproval(id: "replacement", runId: "AAAAAAAA-1111", conversationId: nil,
      command: "git push", description: "New action", riskLevel: "normal")
    stale.rpc.vote("POLL-1", id: 400)
    await settlePolls()
    check(stale.decisions.isEmpty, "An old poll cannot authorize a replacement request on the same task")
    stale.rpc.vote("POLL-2", id: 401, ids: ["option-1"])
    await settlePolls()
    check(stale.decisions.first?.0 == "replacement" && stale.decisions.first?.1 == false,
      "The newer poll retains its own request identity")

    let reconnect = PollFixture()
    defer { reconnect.close() }
    reconnect.approval()
    await settlePolls()
    reconnect.controller.disable()
    reconnect.rpc.vote("POLL-1", id: 500)
    reconnect.controller.enablePairedConnection()
    await settlePolls()
    reconnect.rpc.vote("POLL-1", id: 501)
    await settlePolls()
    check(reconnect.decisions.isEmpty, "Disconnect revokes old poll bindings even after reconnect")

    let early = PollFixture()
    defer { early.close() }
    early.sender.delay = 60_000_000
    early.sender.onSending = { [weak early] _, guid in early?.rpc.vote(guid, id: 600) }
    early.approval()
    await settlePolls(200_000_000)
    check(early.decisions.count == 1, "A fast vote is buffered until the outgoing poll identity is confirmed")

    let serial = PollFixture()
    defer { serial.close() }
    serial.sender.delay = 50_000_000
    serial.approval()
    serial.approval("approval-b", runID: "BBBBBBBB-2222")
    await settlePolls(250_000_000)
    check(serial.sender.sent.count == 2 && serial.sender.maximumInFlight == 1,
      "Concurrent agents share one native Messages automation lane")
    serial.rpc.vote("POLL-2", id: 700, ids: ["option-1"])
    await settlePolls()
    check(serial.decisions.first?.0 == "approval-b", "A vote is not routed to whichever agent is currently selected")

    let failed = PollFixture()
    defer { failed.close() }
    failed.sender.failure = ImsgRPCClient.RPCError.timedOut
    failed.approval()
    await settlePolls()
    check(failed.sender.sent.count == 1 && failed.controller.pollStatus != nil,
      "An uncertain UI send pauses polls without retrying")
    failed.rpc.vote("POLL-1", id: 800)
    await settlePolls()
    check(failed.decisions.isEmpty, "An unconfirmed outgoing poll never gains authority")

    let noAccess = PollFixture()
    defer { noAccess.close() }
    noAccess.sender.hasAccess = false
    noAccess.controller.refreshPollAccess()
    noAccess.approval()
    await settlePolls()
    check(noAccess.sender.sent.isEmpty && noAccess.rpc.sent.last?.contains("Open Detach") == true,
      "Denied Accessibility keeps the native decision on the Mac")

    let cancelled = PollFixture()
    defer { cancelled.close() }
    cancelled.sender.delay = 300_000_000
    cancelled.approval()
    await settlePolls(40_000_000)
    cancelled.controller.stop()
    await settlePolls(100_000_000)
    check(cancelled.sender.inFlight == 0 && !cancelled.controller.isSendingPoll,
      "Stopping Messages cancels automation without leaving a second sender running")

    let removed = PollFixture()
    defer { removed.close() }
    removed.approval()
    await settlePolls()
    removed.rpc.vote("POLL-1", id: 850)
    removed.rpc.vote("POLL-1", id: 851, eventType: "removed")
    await settlePolls()
    check(removed.decisions.isEmpty, "An explicit native removal cannot be interpreted as selecting Approve")

    let realContract = PollFixture()
    defer { realContract.close() }
    realContract.sender.guidOverride = "NATIVE-FIXTURE-POLL"
    realContract.sender.optionIDs = ["fixture-yes", "fixture-no"]
    realContract.approval("real-driver-contract")
    await settlePolls()
    realContract.rpc.onMessage?(nativePollFixture("native-poll-vote.json"))
    await settlePolls()
    check(realContract.decisions.count == 1 && realContract.decisions[0].0 == "real-driver-contract" &&
      !realContract.decisions[0].1,
      "Actual bundled-driver vote JSON selects the paired sender's Deny, not the compatibility first voter's Approve")

    await pollRecoveryTests()
    await questionPollTests()
    pollIdentityTests()
  }
}
