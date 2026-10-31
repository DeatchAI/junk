import Foundation

/// Counts reported plan steps, never elapsed time or inferred task completion.
struct DetachedRunProgress: Equatable {
  let completed: Int
  let total: Int

  var fraction: Double { Double(completed) / Double(total) }
  var label: String { "\(completed)/\(total) steps" }

  init?(event: AgentActivityEvent?) {
    guard let event, event.userFacing, event.phase != "failed", let details = event.details else { return nil }
    let items: [ActivityJSONValue]?
    if case .array(let values) = details["items"], event.kind == "plan" { items = values }
    else if case .array(let values) = details["plan"], event.kind == "plan" { items = values }
    else { items = nil }
    guard let items, !items.isEmpty else { return nil }
    var completed = 0
    for item in items {
      guard case .object(let step) = item else { return nil }
      if case .bool(let done) = step["completed"] {
        if done { completed += 1 }
      } else if case .string(let status) = step["status"],
        ["pending", "in_progress", "completed"].contains(status) {
        if status == "completed" { completed += 1 }
      } else { return nil }
    }
    self.completed = completed
    total = items.count
  }
}
