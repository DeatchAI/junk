import Foundation

struct GitDiffLine {
  enum Kind { case context, addition, deletion, metadata }
  let text: String
  let oldLine: Int?
  let newLine: Int?
  let kind: Kind
  var display: String {
    guard kind != .metadata else { return text }
    let old = oldLine.map(String.init) ?? "", new = newLine.map(String.init) ?? ""
    return String(repeating: " ", count: max(0, 5 - old.count)) + old + " "
      + String(repeating: " ", count: max(0, 5 - new.count)) + new + "  " + text
  }
}

enum GitDiffLines {
  struct Row {
    let before: GitDiffLine?
    let after: GitDiffLine?
    let section: String?
  }

  /// Pair replacement blocks and insert blank rows so both panes stay aligned.
  static func aligned(_ text: String) -> [Row] {
    var rows: [Row] = [], removed: [GitDiffLine] = [], added: [GitDiffLine] = []
    func flush() {
      for index in 0..<max(removed.count, added.count) {
        rows.append(Row(before: index < removed.count ? removed[index] : nil,
          after: index < added.count ? added[index] : nil, section: nil))
      }
      removed.removeAll(); added.removeAll()
    }
    for line in parse(text) {
      switch line.kind {
      case .deletion:
        if !added.isEmpty { flush() }
        removed.append(line)
      case .addition: added.append(line)
      case .context:
        flush(); rows.append(Row(before: line, after: line, section: nil))
      case .metadata:
        flush()
        if line.text.hasPrefix("@@") {
          let parts = line.text.components(separatedBy: "@@")
          let location = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
          let context = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespaces) : ""
          rows.append(Row(before: nil, after: nil, section: context.isEmpty ? location : context))
        } else if !line.text.isEmpty, !line.text.hasPrefix("diff --git "), !line.text.hasPrefix("index "),
          !line.text.hasPrefix("--- "), !line.text.hasPrefix("+++ ") {
          rows.append(Row(before: nil, after: nil, section: line.text))
        }
      }
    }
    flush()
    return rows
  }

  static func parse(_ text: String) -> [GitDiffLine] {
    var old = 0, new = 0, inHunk = false
    return text.components(separatedBy: "\n").map { line in
      if line.hasPrefix("@@") {
        let pieces = line.split(separator: " ")
        if pieces.count >= 3,
          let oldPart = pieces[1].dropFirst().split(separator: ",").first,
          let newPart = pieces[2].dropFirst().split(separator: ",").first,
          let oldStart = Int(oldPart), let newStart = Int(newPart) {
          old = oldStart; new = newStart; inHunk = true
        }
        return GitDiffLine(text: line, oldLine: nil, newLine: nil, kind: .metadata)
      }
      if line.hasPrefix("diff --git ") || line.hasPrefix("--- ") || line.hasPrefix("+++ ") {
        inHunk = false
        return GitDiffLine(text: line, oldLine: nil, newLine: nil, kind: .metadata)
      }
      guard inHunk else { return GitDiffLine(text: line, oldLine: nil, newLine: nil, kind: .metadata) }
      if line.hasPrefix("+") {
        defer { new += 1 }
        return GitDiffLine(text: line, oldLine: nil, newLine: new, kind: .addition)
      }
      if line.hasPrefix("-") {
        defer { old += 1 }
        return GitDiffLine(text: line, oldLine: old, newLine: nil, kind: .deletion)
      }
      if line.hasPrefix(" ") {
        defer { old += 1; new += 1 }
        return GitDiffLine(text: line, oldLine: old, newLine: new, kind: .context)
      }
      return GitDiffLine(text: line, oldLine: nil, newLine: nil, kind: .metadata)
    }
  }
}
