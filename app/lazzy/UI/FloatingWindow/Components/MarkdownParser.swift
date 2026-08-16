import Foundation
import SwiftUI

enum ContentSegment: Identifiable {
  case textGroup([SelectableTextBlock])
  case codeBlock(code: String, language: String?)
  case image(url: URL, alt: String?)

  var id: String {
    switch self {
    case .textGroup(let blocks):
      return "text-\(blocks.hashValue)"
    case .codeBlock(let code, let language):
      return "code-\(language ?? "plain")-\(code.hashValue)"
    case .image(let url, _):
      return "img-\(url.absoluteString)"
    }
  }
}

final class MarkdownParser {
  static let shared = MarkdownParser()

  private static let imagePattern = try! NSRegularExpression(
    pattern: #"^!\[([^\]]*)\]\((\S+?)(?:\s+"[^"]*")?\)$"#
  )
  private static let unorderedListPattern = try! NSRegularExpression(
    pattern: #"^(\s*)[-+*]\s+(.+)$"#
  )
  private static let orderedListPattern = try! NSRegularExpression(
    pattern: #"^(\s*)(\d+)[.)]\s+(.+)$"#
  )

  private init() {}

  func parse(_ text: String) -> [ContentSegment] {
    var segments: [ContentSegment] = []
    var textBlocks: [SelectableTextBlock] = []
    var paragraphLines: [String] = []
    var codeLines: [String] = []
    var codeLanguage: String?
    var codeFenceLength = 0
    var canContinueListItem = false

    func flushParagraph() {
      guard !paragraphLines.isEmpty else { return }
      textBlocks.append(.paragraph(paragraphLines.joined(separator: " ")))
      paragraphLines.removeAll(keepingCapacity: true)
    }

    func flushTextBlocks() {
      flushParagraph()
      guard !textBlocks.isEmpty else { return }
      segments.append(.textGroup(textBlocks))
      textBlocks.removeAll(keepingCapacity: true)
    }

    func appendBlockquote(_ content: String) {
      if let last = textBlocks.last, case .blockquote(let existing) = last {
        textBlocks[textBlocks.count - 1] = .blockquote(existing + " " + content)
      } else {
        textBlocks.append(.blockquote(content))
      }
    }

    let lines = text.components(separatedBy: .newlines)

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if codeFenceLength > 0 {
        if closingFenceLength(in: trimmed) >= codeFenceLength {
          segments.append(
            .codeBlock(code: codeLines.joined(separator: "\n"), language: codeLanguage)
          )
          codeLines.removeAll(keepingCapacity: true)
          codeLanguage = nil
          codeFenceLength = 0
        } else {
          codeLines.append(line)
        }
        continue
      }

      if let fence = openingFence(in: trimmed) {
        flushTextBlocks()
        codeFenceLength = fence.length
        codeLanguage = normalizedLanguage(fence.info)
        continue
      }

      if trimmed.isEmpty {
        flushParagraph()
        canContinueListItem = false
        continue
      }

      if let image = standaloneImage(in: trimmed) {
        flushTextBlocks()
        segments.append(image)
        canContinueListItem = false
        continue
      }

      if let heading = heading(in: trimmed) {
        flushParagraph()
        textBlocks.append(.heading(level: heading.level, text: heading.text))
        canContinueListItem = false
        continue
      }

      if trimmed == "---" || trimmed == "***" || trimmed == "___" {
        flushParagraph()
        canContinueListItem = false
        continue
      }

      if trimmed.hasPrefix(">") {
        flushParagraph()
        let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        appendBlockquote(content)
        canContinueListItem = false
        continue
      }

      if let listItem = listItem(in: line) {
        flushParagraph()
        textBlocks.append(listItem)
        canContinueListItem = true
        continue
      }

      if !paragraphLines.isEmpty {
        paragraphLines.append(trimmed)
      } else if canContinueListItem, let last = textBlocks.last,
        case .listItem(let existing, let index, let ordered, let indentLevel) = last
      {
        // A non-list line immediately after a list item is its wrapped continuation.
        textBlocks[textBlocks.count - 1] = .listItem(
          text: existing + " " + trimmed,
          index: index,
          ordered: ordered,
          indentLevel: indentLevel
        )
      } else {
        paragraphLines = [trimmed]
        canContinueListItem = false
      }
    }

    if codeFenceLength > 0 {
      segments.append(.codeBlock(code: codeLines.joined(separator: "\n"), language: codeLanguage))
    } else {
      flushTextBlocks()
    }

    return segments
  }

  private func openingFence(in line: String) -> (length: Int, info: String)? {
    let length = line.prefix(while: { $0 == "`" }).count
    guard length >= 3 else { return nil }
    let info = String(line.dropFirst(length)).trimmingCharacters(in: .whitespaces)
    return (length, info)
  }

  private func closingFenceLength(in line: String) -> Int {
    let length = line.prefix(while: { $0 == "`" }).count
    guard length >= 3 else { return 0 }
    let remainder = line.dropFirst(length)
    return remainder.allSatisfy(\.isWhitespace) ? length : 0
  }

  private func normalizedLanguage(_ info: String) -> String? {
    guard !info.isEmpty else { return nil }
    let language = info.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? info
    return language.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
  }

  private func standaloneImage(in line: String) -> ContentSegment? {
    let range = NSRange(location: 0, length: (line as NSString).length)
    guard
      let match = Self.imagePattern.firstMatch(in: line, range: range),
      let urlRange = Range(match.range(at: 2), in: line),
      let url = URL(string: String(line[urlRange]))
    else {
      return nil
    }

    let alt = Range(match.range(at: 1), in: line).map { String(line[$0]) }
    return .image(url: url, alt: alt)
  }

  private func heading(in line: String) -> (level: Int, text: String)? {
    let level = line.prefix(while: { $0 == "#" }).count
    guard (1...6).contains(level) else { return nil }
    let remainder = line.dropFirst(level)
    guard remainder.first?.isWhitespace == true else { return nil }

    var content = String(remainder).trimmingCharacters(in: .whitespaces)
    content = content.replacingOccurrences(
      of: #"\s+#+\s*$"#,
      with: "",
      options: .regularExpression
    )
    return (level, content)
  }

  private func listItem(in line: String) -> SelectableTextBlock? {
    let range = NSRange(location: 0, length: (line as NSString).length)

    if let match = Self.unorderedListPattern.firstMatch(in: line, range: range),
      let whitespaceRange = Range(match.range(at: 1), in: line),
      let contentRange = Range(match.range(at: 2), in: line)
    {
      return .listItem(
        text: String(line[contentRange]),
        index: 0,
        ordered: false,
        indentLevel: indentLevel(for: String(line[whitespaceRange]))
      )
    }

    if let match = Self.orderedListPattern.firstMatch(in: line, range: range),
      let whitespaceRange = Range(match.range(at: 1), in: line),
      let indexRange = Range(match.range(at: 2), in: line),
      let contentRange = Range(match.range(at: 3), in: line)
    {
      return .listItem(
        text: String(line[contentRange]),
        index: Int(line[indexRange]) ?? 1,
        ordered: true,
        indentLevel: indentLevel(for: String(line[whitespaceRange]))
      )
    }

    return nil
  }

  private func indentLevel(for whitespace: String) -> Int {
    let columns = whitespace.reduce(into: 0) { result, character in
      result += character == "\t" ? 2 : 1
    }
    return columns / 2
  }
}
