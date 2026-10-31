import Foundation

/// A poll is a one-shot decision on an exact native request. Its displayed labels are never authority.
@MainActor
final class MessagesPollCoordinator {
  struct Binding {
    let decision: MessagesPollDecision
    let optionIDs: [String]
  }
  private let sender: MessagesPollSending
  private let isPending: (MessagesPollDecision) -> Bool
  private let apply: (MessagesPollDecision, Int) -> Bool
  private let notice: (String) -> Void
  private var bindings: [String: Binding] = [:]
  private var settling: [String: Task<Void, Never>] = [:]
  private var latestRows: [String: Int] = [:]
  private var warned = Set<String>()
  private var earlyVotes: [MessagesIncomingMessage] = []
  private var sending = false
  private var generation = UUID()
  var settleNanoseconds: UInt64 = 900_000_000

  init(sender: MessagesPollSending, isPending: @escaping (MessagesPollDecision) -> Bool,
    apply: @escaping (MessagesPollDecision, Int) -> Bool, notice: @escaping (String) -> Void,
    settleNanoseconds: UInt64 = 900_000_000) {
    self.sender = sender
    self.isPending = isPending
    self.apply = apply
    self.notice = notice
    self.settleNanoseconds = settleNanoseconds
  }

  func reset() {
    generation = UUID()
    settling.values.forEach { $0.cancel() }
    settling.removeAll(); bindings.removeAll(); latestRows.removeAll()
    earlyVotes.removeAll(); warned.removeAll()
    sending = false
  }

  func pending(_ decision: MessagesPollDecision) -> Bool {
    Date() < decision.expiresAt && isPending(decision)
  }

  func send(_ decision: MessagesPollDecision, chatID: Int, recipient: String) async throws {
    guard pending(decision) else { return }
    let epoch = generation
    sending = true
    defer { if epoch == generation { sending = false } }
    let created = try await sender.send(decision, chatID: chatID, recipient: recipient) { [weak self] in
      self?.generation == epoch && self?.pending(decision) == true
    }
    guard epoch == generation, pending(decision),
      created.options.map(\.text) == decision.options,
      Set(created.options.map(\.id)).count == decision.options.count,
      let guid = MessagesNativePoll.guid(created.guid), bindings[guid] == nil else { return }
    bindings[guid] = Binding(decision: decision, optionIDs: created.options.map(\.id))
    let buffered = earlyVotes
    earlyVotes.removeAll()
    for message in buffered { receive(message) }
    prune()
  }

  /// Called only after the controller verifies subscription, paired sender, direct chat, and direction.
  func receive(_ message: MessagesIncomingMessage) {
    guard let poll = message.poll,
      let guid = poll.originalGUID ?? poll.guid,
      poll.guid == nil || poll.originalGUID == nil || poll.guid == poll.originalGUID else { return }
    guard let binding = bindings[guid] else {
      if sending, earlyVotes.count < 50 { earlyVotes.append(message) }
      return
    }
    if poll.kind == "created" {
      let original = zip(binding.optionIDs, binding.decision.options)
      guard original.allSatisfy({ id, text in poll.options.contains { $0.id == id && $0.text == text } }) else {
        settling.removeValue(forKey: guid)?.cancel()
        bindings[guid] = nil
        notice("The poll changed. Review this decision on your Mac.")
        return
      }
      return
    }
    guard message.id > (latestRows[guid] ?? 0) else { return }
    latestRows[guid] = message.id
    settling.removeValue(forKey: guid)?.cancel()
    guard pending(binding.decision) else { bindings[guid] = nil; return }
    guard poll.kind == "vote" else { return }
    guard let votes = poll.votes else { return }
    // A full snapshot may include other participants; only the authenticated row sender can decide.
    let own = votes.filter { MessagesIncomingMessage.sameSender($0.participant, message.sender) }
    let grouped = Dictionary(grouping: own, by: \.optionID)
    guard !grouped.values.contains(where: { Set($0.map(\.isSelected)).count > 1 }) else { return }
    let ids = Set(own.filter(\.isSelected).map(\.optionID))
    guard ids.count == 1, let id = ids.first, let index = binding.optionIDs.firstIndex(of: id) else {
      if !ids.isEmpty, warned.insert(guid).inserted {
        notice("Choose one of the original poll options. Multiple choices or added options cannot submit a decision.")
      }
      return
    }
    let epoch = generation
    settling[guid] = Task { @MainActor [weak self] in
      guard let self else { return }
      do { try await Task.sleep(nanoseconds: self.settleNanoseconds) } catch { return }
      guard self.generation == epoch, self.latestRows[guid] == message.id,
        self.pending(binding.decision) else { return }
      // Consume before entering the native response path, including synchronous callbacks.
      self.bindings[guid] = nil
      self.settling[guid] = nil
      self.latestRows[guid] = nil
      self.warned.remove(guid)
      _ = self.apply(binding.decision, index)
    }
  }

  private func prune() {
    while bindings.count > 200, let oldest = bindings.min(by: { $0.value.decision.expiresAt < $1.value.decision.expiresAt })?.key {
      settling.removeValue(forKey: oldest)?.cancel()
      bindings[oldest] = nil; latestRows[oldest] = nil; warned.remove(oldest)
    }
    for (guid, binding) in bindings where !pending(binding.decision) {
      settling.removeValue(forKey: guid)?.cancel()
      bindings[guid] = nil; latestRows[guid] = nil; warned.remove(guid)
    }
  }
}
