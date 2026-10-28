import Foundation

/// Summarize only explicit provider evidence; a finished turn alone proves no checks passed.
struct DetachedRunOutcome: Equatable, Codable {
  var changedFiles: Set<String> = []
  var passedChecks: Set<String> = []

  mutating func record(_ event: AgentActivityEvent?) {
    guard let event, event.phase == "completed", let details = event.details else { return }
    if event.kind == "file_change" {
      for key in ["path", "file_path", "filePath"] {
        if case .string(let path) = details[key], !path.isEmpty { changedFiles.insert(path) }
      }
      if case .array(let changes) = details["changes"] {
        for change in changes {
          if case .object(let item) = change, case .string(let path) = item["path"] {
            changedFiles.insert(path)
          }
        }
      }
    }
    if event.kind == "command", case .number(let code) = details["exitCode"], code == 0,
      case .string(let command) = details["command"],
      command.range(of: #"\b(test|pytest|vitest|jest)\b"#, options: .regularExpression) != nil {
      passedChecks.insert(event.id ?? command)
    }
  }

  var summary: String? {
    var values: [String] = []
    if !changedFiles.isEmpty { values.append("\(changedFiles.count) \(changedFiles.count == 1 ? "file" : "files") changed") }
    if !passedChecks.isEmpty { values.append("\(passedChecks.count) \(passedChecks.count == 1 ? "check" : "checks") passed") }
    return values.isEmpty ? nil : values.joined(separator: " · ")
  }
}
