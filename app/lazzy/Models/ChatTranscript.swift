import Foundation

/// Shared by compact replies, expanded chat and every provider's saved history.
enum ChatTranscript {
  struct Segment: Identifiable {
    let id: Int
    var parts: [MessagePart]
    var isActivity: Bool { parts.first?.type == "activity" }
    var summary: String {
      let failures = parts.filter { $0.status == "failed" }.count
      if failures > 0 { return "\(parts.count) activities · \(failures) failed" }
      let kinds = Set(parts.compactMap(\.kind))
      if kinds == ["command"] { return parts.count == 1 ? "Ran command" : "Ran \(parts.count) commands" }
      if kinds == ["file_change"] { return "Updated files" }
      if kinds.isSubset(of: ["read", "search"]) { return "Read and searched files" }
      if kinds.contains("command") { return "Read files, ran commands" }
      return parts.count == 1 ? "Used a tool" : "Used \(parts.count) tools"
    }
  }

  static func segments(_ parts: [MessagePart]) -> [Segment] {
    var result: [Segment] = []
    for part in parts where part.type == "activity" || (part.type == "text" && !(part.text ?? "").isEmpty) {
      if part.type == "activity", result.last?.isActivity == true {
        result[result.count - 1].parts.append(part)
      } else { result.append(Segment(id: result.count, parts: [part])) }
    }
    return result
  }

  static func parts(text: String, structured: [MessagePart]?) -> [MessagePart] {
    if let structured, structured.contains(where: { $0.type == "text" || $0.type == "activity" }) { return structured }
    return text.isEmpty ? [] : [MessagePart(type: "text", text: text)]
  }

  static func readableText(_ parts: [MessagePart]) -> String {
    parts.filter { $0.type == "text" }.compactMap(\.text).joined(separator: "\n\n")
  }
}

