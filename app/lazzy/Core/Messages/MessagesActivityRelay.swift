import Combine
import Foundation

/// Only outcomes and requests for a decision leave the shared all-project activity store.
@MainActor
final class MessagesActivityRelay {
  private weak var store: DetachedRunStore?
  private let send: (String) -> Void
  private var observation: AnyCancellable?
  private var states: [String: String] = [:]
  private var results: [String: String] = [:]
  private var resultOrder: [String] = []
  private(set) var isEnabled = false
  var questionText: ((DetachedAgentRun) -> String?)?
  var questionIdentity: ((DetachedAgentRun) -> String?)?
  var decision: ((DetachedAgentRun) -> Bool)?
  var approvalText: ((DetachedAgentRun) -> String?)?

  init(store: DetachedRunStore, send: @escaping (String) -> Void) {
    self.store = store
    self.send = send
    observation = store.$runs.receive(on: RunLoop.main)
      .sink { [weak self] in self?.consume($0) }
  }

  func setEnabled(_ enabled: Bool) {
    guard enabled != isEnabled else { return }
    isEnabled = enabled
    states.removeAll()
    guard enabled, let store else { results.removeAll(); resultOrder.removeAll(); return }
    // Do not replay old completions. Current unanswered decisions remain useful on reconnect.
    for run in store.runs where !run.isActive { states[run.id] = fingerprint(run) }
    consume(store.runs)
  }

  func recordResult(runID: String, text: String) {
    guard isEnabled, !text.isEmpty else { return }
    if results[runID] == nil { resultOrder.append(runID) }
    results[runID] = MessagesNotificationText.resultPreview(text)
    while resultOrder.count > 100 { results[resultOrder.removeFirst()] = nil }
  }

  private func consume(_ runs: [DetachedAgentRun]) {
    guard isEnabled else { return }
    for run in runs.filter({ !$0.isDebugPreview }).sorted(by: { $0.startedAt < $1.startedAt }) {
      let signature = fingerprint(run)
      guard states[run.id] != signature else { continue }
      states[run.id] = signature
      switch run.state {
      case .completed, .failed:
        send(notification(for: run))
      case .awaitingApproval:
        if run.approval != nil, decision?(run) != true { send(notification(for: run)) }
      case .awaitingCredential:
        if run.credential != nil { send(notification(for: run)) }
      case .awaitingInput:
        if questionIdentity == nil || questionIdentity?(run) != nil {
          if decision?(run) != true { send(notification(for: run)) }
        }
      case .running, .stopping, .stopped:
        break
      }
    }
    let ids = Set(runs.map(\.id))
    states = states.filter { ids.contains($0.key) }
  }

  private func fingerprint(_ run: DetachedAgentRun) -> String {
    let interrupt: String
    switch run.state {
    case .awaitingInput: interrupt = questionIdentity?(run) ?? run.status
    case .awaitingApproval: interrupt = run.approval?.id ?? ""
    case .awaitingCredential: interrupt = run.credential?.id ?? ""
    default: interrupt = ""
    }
    return run.stateLabel + interrupt
  }

  func notification(for run: DetachedAgentRun) -> String {
    var lines = [Self.heading(run), MessagesNotificationText.title(run.taskTitle), run.stateLabel]
    switch run.state {
    case .completed:
      if let summary = run.outcome.summary { lines.append(summary) }
      if let result = results[run.id] { lines.append(result) }
      lines.append("Reply: reply \(Self.shortID(run)) <message>")
    case .awaitingInput:
      lines.append(questionText?(run) ?? "Open Detach on your Mac to answer.")
    case .awaitingApproval:
      lines.append(approvalText?(run) ?? "\(run.currentActivity)\nReview this approval on your Mac.")
    case .awaitingCredential:
      lines.append("Confirm private access on your Mac.")
    case .failed:
      lines.append(MessagesNotificationText.resultPreview(run.currentActivity))
      lines.append("Continue: reply \(Self.shortID(run)) <message>")
    case .running, .stopping, .stopped: break
    }
    return lines.filter { !$0.isEmpty }.joined(separator: "\n")
  }

  static func shortID(_ run: DetachedAgentRun) -> String {
    String(normalize(run.id).prefix(8))
  }

  static func normalize(_ value: String) -> String {
    value.filter { $0.isLetter || $0.isNumber }.uppercased()
  }

  static func heading(_ run: DetachedAgentRun) -> String {
    "#\(shortID(run)) · \(AgentProvider.displayName(for: run.agent)) · \(MessagesNotificationText.title(run.projectLabel))"
  }
}
