import AppKit
import ApplicationServices

@MainActor
final class MessagesNativePollSender: MessagesPollSending {
  private let rpc: MessagesRPCTransport
  var hasAccess: Bool { AXIsProcessTrusted() }
  init(rpc: MessagesRPCTransport) { self.rpc = rpc }

  func send(_ decision: MessagesPollDecision, chatID: Int, recipient: String,
    isPending: @escaping () -> Bool) async throws -> MessagesCreatedPoll {
    let previousApp = NSWorkspace.shared.frontmostApplication
    var touchedMessages = false
    defer {
      if touchedMessages,
        let current = NSWorkspace.shared.frontmostApplication,
        ["com.apple.MobileSMS", "com.apple.iChat"].contains(current.bundleIdentifier ?? ""),
        let previousApp, previousApp.processIdentifier != current.processIdentifier {
        previousApp.activate(options: [])
      }
    }
    guard hasAccess else { throw PollUIError.unavailable("Allow Detach in Accessibility to send interactive polls.") }
    guard !PollAccessibility.isScreenLocked else { throw PollUIError.screenLocked }
    let chat = try await rpc.call("chats.get", ["chat_id": chatID])
    guard let identity = MessagesChatIdentity(chat),
      identity.rejectionReason(chatID: chatID, sender: recipient) == nil else {
      throw PollUIError.unavailable("The paired Messages conversation could not be verified.")
    }
    let before = try await rpc.call("messages.history", ["chat_id": chatID, "limit": 20])
    let baseline = (before["messages"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? Int }.max() ?? 0
    let directory = try requestDirectory(decision.id)
    let requestURL = directory.appendingPathComponent("request.json")
    try PollSendAttempt.requireUnattempted(beside: requestURL)
    try JSONEncoder().encode(decision.request).write(to: requestURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: requestURL.path)
    guard isPending() else { throw CancellationError() }

    if let details = decision.details {
      touchedMessages = true
      let attachment = directory.appendingPathComponent("Decision details.txt")
      try Data(details.utf8).write(to: attachment, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: attachment.path)
      let result = try await rpc.call("send", ["chat_id": chatID, "file": attachment.path,
        "text": "Details for \(String(decision.id.uuidString.prefix(12))). Review before voting.",
        "transport": "applescript"])
      guard result["ok"] as? Bool == true else { throw ImsgRPCClient.RPCError.invalidResponse }
    }
    guard isPending() else { throw CancellationError() }
    let identifiers = ["com.apple.MobileSMS", "com.apple.iChat"]
    if !NSWorkspace.shared.runningApplications.contains(where: { identifiers.contains($0.bundleIdentifier ?? "") }) {
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.MobileSMS")
        ?? URL(fileURLWithPath: "/System/Applications/Messages.app")
      guard NSWorkspace.shared.open(url) else { throw PollUIError.unavailable("Could not open Messages.") }
      for _ in 0..<40 {
        guard isPending() else { throw CancellationError() }
        if NSWorkspace.shared.runningApplications.contains(where: { identifiers.contains($0.bundleIdentifier ?? "") }) { break }
        try await Task.sleep(nanoseconds: 100_000_000)
      }
    }
    touchedMessages = true
    let workflow = try PollWorkflow(recipient: recipient, navigate: true)
    workflow.ax.canContinue = { isPending() && Date() < decision.expiresAt }
    workflow.trace = { Self.record($0, beside: requestURL) }
    workflow.ax.trace = { Self.record($0, beside: requestURL) }
    do {
      try await workflow.prepare(decision.request)
      _ = try await workflow.sendPrepared(decision.request, requestURL: requestURL)
    } catch {
      let attempted = FileManager.default.fileExists(atPath: requestURL.appendingPathExtension("send-attempt").path)
      // A cancelled connection must not mutate a newer sender's desktop.
      if error is CancellationError { throw error }
      let cleaned: Bool
      if attempted { cleaned = false }
      else { cleaned = await workflow.discardOwnedDraft() }
      let reason = "\(workflow.phase): \(error.localizedDescription)"
      Self.record(reason, beside: requestURL)
      if cleaned { throw MessagesPollSendFailure.notSubmitted(reason) }
      throw MessagesPollSendFailure.needsReview(reason)
    }

    // Reads may retry while the native caption arrives. The send is never retried.
    for _ in 0..<8 {
      try Task.checkCancellation()
      let response = try await rpc.call("messages.history", ["chat_id": chatID, "limit": 30])
      let matches = Self.createdPolls(in: response, after: baseline, decision: decision, chatID: chatID)
      if matches.count == 1 { return matches[0] }
      if matches.count > 1 { break }
      try await Task.sleep(nanoseconds: 250_000_000)
    }
    throw PollUIError.unavailable("The poll was sent, but its identity was not confirmed. Review this decision on your Mac.")
  }

  static func createdPolls(in response: [String: Any], after baseline: Int,
    decision: MessagesPollDecision, chatID: Int) -> [MessagesCreatedPoll] {
    (response["messages"] as? [[String: Any]] ?? []).compactMap { raw in
      guard let id = raw["id"] as? Int, id > baseline,
        raw["chat_id"] as? Int == chatID, raw["is_from_me"] as? Bool == true,
        raw["type"] == nil, let data = raw["poll"] as? [String: Any],
        let poll = MessagesNativePoll(data), poll.kind == "created", poll.originalGUID == nil,
        let guid = poll.guid, guid == MessagesNativePoll.guid(raw["guid"] as? String),
        poll.question == decision.caption, poll.options.map(\.text) == decision.options,
        Set(poll.options.map(\.id)).count == decision.options.count else { return nil }
      return MessagesCreatedPoll(guid: guid, options: poll.options)
    }
  }

  private static func record(_ message: String, beside request: URL) {
    let url = request.deletingLastPathComponent().appendingPathComponent("automation.log")
    if !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
    }
    guard let handle = try? FileHandle(forWritingTo: url) else { return }
    defer { try? handle.close() }
    try? handle.seekToEnd()
    try? handle.write(contentsOf: Data("\(Date().timeIntervalSince1970) \(message)\n".utf8))
  }

  private func requestDirectory(_ id: UUID) throws -> URL {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("DetachMessagesPolls", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    // Receipts survive uncertain sends for this session; private details expire after a day.
    for url in (try? FileManager.default.contentsOfDirectory(at: base,
      includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
      let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
      if let modified, Date().timeIntervalSince(modified) > 86_400 { try? FileManager.default.removeItem(at: url) }
    }
    let directory = base.appendingPathComponent(id.uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    return directory
  }
}
