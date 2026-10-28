import CryptoKit
import Foundation

/// Stable editor markers are rendered as atoms and resolved before any request is sent.
struct ComposerInlineToken: Equatable, Identifiable {
  let id: String
  let marker: String
  let label: String
  let symbol: String
  let replacement: String

  static func file(_ attachment: ChatAttachment) -> Self {
    let id = "file:\(attachment.id.uuidString)"
    let symbol = attachment.conversationID != nil ? "bubble.left"
      : attachment.fileRequest.mimeType == "inode/directory" ? "folder" : "doc.text"
    return Self(id: id, marker: "[[\(id)]]", label: attachment.fileName,
      symbol: symbol, replacement: "@\(attachment.fileName)")
  }

  static func context(_ context: DetectedContent) -> Self {
    let digest = SHA256.hash(data: Data((context.text ?? "").utf8))
      .map { String(format: "%02x", $0) }.joined()
    let id = "context:\(digest)"
    return Self(id: id, marker: "[[\(id)]]", label: "Selected text", symbol: "text.quote",
      replacement: "@Selected-text")
  }

  static func mention(id: String, name: String, symbol: String) -> Self {
    let marker = "@\(name.replacingOccurrences(of: " ", with: "-"))"
    return Self(id: id, marker: marker, label: name, symbol: symbol, replacement: marker)
  }

  static func resolve(_ text: String, tokens: [Self]) -> String {
    tokens.reduce(text) { $0.replacingOccurrences(of: $1.marker, with: $1.replacement) }
  }

  static func contains(_ token: Self, in text: String) -> Bool {
    if token.marker.hasPrefix("[[") { return text.contains(token.marker) }
    return text.range(of: #"(^|\s)\#(NSRegularExpression.escapedPattern(for: token.marker))(?=\s|$)"#,
      options: .regularExpression) != nil
  }

  static func addingMissingFiles(to text: String, attachments: [ChatAttachment], contexts: [DetectedContent]) -> String {
    var text = text
    let tokens = attachments.filter { !$0.canPreviewMedia }.map(Self.file) + contexts.map(Self.context)
    for token in tokens where !contains(token, in: text) {
      if token.id.hasPrefix("file:"), let range = text.range(of: token.replacement) {
        text.replaceSubrange(range, with: token.marker)
      } else {
        if !text.isEmpty && text.last?.isWhitespace != true { text += " " }
        text += token.marker + " "
      }
    }
    return text
  }

  static func removingMissingFiles(from text: String, attachments: [ChatAttachment]) -> String {
    let markers = Set(attachments.filter(\.isAvailable).map { Self.file($0).marker })
    guard let pattern = try? NSRegularExpression(pattern: #"\[\[file:[A-Fa-f0-9-]{36}\]\]"#) else { return text }
    var result = text
    for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
      guard let range = Range(match.range, in: result), !markers.contains(String(result[range])) else { continue }
      result.removeSubrange(range)
    }
    return result
  }
}

enum ComposerInlineSelection {
  case file(ChatAttachment), context(DetectedContent), skill(SkillAttachment)
  case tab(BrowserTabAttachment), mcp(ComposerMCPAttachment), command(SlashCommandAlias)

  var token: ComposerInlineToken {
    switch self {
    case .file(let file): return .file(file)
    case .context(let context): return .context(context)
    case .skill(let skill): return .mention(id: "skill:\(skill.id)", name: skill.name, symbol: "wand.and.stars")
    case .tab(let tab):
      let name = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
      return .mention(id: "tab:\(tab.id)", name: name.isEmpty ? "chrome-tab-\(tab.id)" : name, symbol: "globe")
    case .mcp(let mcp): return .mention(id: "mcp:\(mcp.id)", name: mcp.name, symbol: mcp.systemImage)
    case .command(let command):
      return ComposerInlineToken(id: "command:\(command.id)", marker: "/\(command.command)",
        label: command.command, symbol: "slash.circle", replacement: "/\(command.command)")
    }
  }
}

extension ComposerDraft {
  var inlineSelections: [ComposerInlineSelection] {
    attachments.filter { !$0.canPreviewMedia }.map(ComposerInlineSelection.file)
      + contexts.map(ComposerInlineSelection.context) + skills.map(ComposerInlineSelection.skill)
      + browserTabs.map(ComposerInlineSelection.tab) + mcpAttachments.map(ComposerInlineSelection.mcp)
      + commands.map(ComposerInlineSelection.command)
  }

  var resolvedText: String { ComposerInlineToken.resolve(text, tokens: inlineSelections.map(\.token)) }
}
