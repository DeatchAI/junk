import Foundation

/// A decision code refers to one native request, never whichever task is currently selected.
@MainActor
final class MessagesDecisionChoices {
  enum Choice: Equatable {
    case approval(runID: String, requestID: String)
    case question(runID: String, requestID: String, questionID: String)
  }
  private struct Entry {
    let code: String
    let choice: Choice
    let createdAt: Date
  }
  private var entries: [Entry] = []

  func code(for choice: Choice, at now: Date = .now) -> String {
    entries.removeAll { now.timeIntervalSince($0.createdAt) >= lifetime($0.choice) }
    if let existing = entries.first(where: { $0.choice == choice }) { return existing.code }
    var code: String
    repeat { code = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)) }
    while entries.contains(where: { $0.code == code })
    entries.append(.init(code: code, choice: choice, createdAt: now))
    if entries.count > 100 { entries.removeFirst() }
    return code
  }

  func choice(for code: String, at now: Date = .now) -> Choice? {
    guard let entry = entries.first(where: { $0.code == code.uppercased() }),
      now.timeIntervalSince(entry.createdAt) < lifetime(entry.choice) else { return nil }
    return entry.choice
  }

  func remove(_ code: String) { entries.removeAll { $0.code == code.uppercased() } }
  func reset() { entries.removeAll() }

  private func lifetime(_ choice: Choice) -> TimeInterval {
    switch choice {
    case .approval: 60
    case .question: 86_400
    }
  }
}
