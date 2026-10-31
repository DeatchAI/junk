import Foundation

enum MessagesNotificationText {
  static func title(_ text: String) -> String {
    let singleLine = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return String(singleLine.prefix(80)) + (singleLine.count > 80 ? "…" : "")
  }

  /// A bounded tail excerpt includes the concluding response without sending the whole transcript.
  /// This is formatting, not a generated summary or a claim that the transcript has a final channel.
  static func resultPreview(_ text: String, limit: Int = 1_000) -> String {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.count > limit else { return text }
    let tail = String(text.suffix(limit))
    let boundary = tail.range(of: "\n\n")?.upperBound ?? tail.firstIndex(of: " ").map { tail.index(after: $0) }
    return "Result excerpt:\n… " + String(boundary.map { tail[$0...] } ?? tail[...])
      + "\nFull result in Detach."
  }
}
