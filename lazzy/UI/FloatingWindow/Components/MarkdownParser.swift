import Foundation
import SwiftUI

enum ContentSegment: Identifiable {
  case textGroup([SelectableTextBlock])
  case codeBlock(code: String, language: String?)
  case image(url: URL, alt: String?)

  var id: String {
    switch self {
    case .textGroup(let blocks):
      // fast hash for id
      return "text-\(blocks.count)-\(blocks.first.hashValue)"
    case .codeBlock(let code, _):
      return "code-\(code.hashValue)"
    case .image(let url, _):
      return "img-\(url.absoluteString)"
    }
  }
}

class MarkdownParser {
  static let shared = MarkdownParser()

  func parse(_ text: String) -> [ContentSegment] {
    var segments: [ContentSegment] = []
    var currentTextBlocks: [SelectableTextBlock] = []

    // Pre-process text to separate code blocks vs normal text
    // This is a naive line-by-line parser. For robust markdown, we'd use a real parser (like Apple's Markdown framework or Ink),
    // but for this specific "Text + Code + Image" usage, manual is fine.

    let lines = text.components(separatedBy: .newlines)
    var inCodeBlock = false
    var codeBlockContent = ""
    var codeBlockLanguage: String? = nil

    var i = 0
    while i < lines.count {
      let line = lines[i]
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // CODETAG detection
      if trimmed.hasPrefix("```") {
        if inCodeBlock {
          // End of code block
          // Flush any pending text blocks first (though unlikely to be any while inside code block)
          if !currentTextBlocks.isEmpty {
            segments.append(.textGroup(currentTextBlocks))
            currentTextBlocks = []
          }

          segments.append(
            .codeBlock(
              code: codeBlockContent.trimmingCharacters(in: .newlines), language: codeBlockLanguage)
          )
          codeBlockContent = ""
          codeBlockLanguage = nil
          inCodeBlock = false
        } else {
          // Start of code block
          // Flush pending text blocks
          if !currentTextBlocks.isEmpty {
            segments.append(.textGroup(currentTextBlocks))
            currentTextBlocks = []
          }

          inCodeBlock = true
          codeBlockLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
          if codeBlockLanguage?.isEmpty == true { codeBlockLanguage = nil }
        }
      } else if inCodeBlock {
        codeBlockContent += line + "\n"
      } else {
        // Check for Image: ![alt](url)
        // We assume images are on their own line for this simple parser, or we just extract them.
        // Regex to find image
        let imageRegex = try? NSRegularExpression(pattern: "!\\[(.*?)\\]\\((.*?)\\)")
        if let regex = imageRegex,
          let match = regex.firstMatch(
            in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count))
        {
          // Flush text
          if !currentTextBlocks.isEmpty {
            segments.append(.textGroup(currentTextBlocks))
            currentTextBlocks = []
          }

          if let urlRange = Range(match.range(at: 2), in: trimmed),
            let url = URL(string: String(trimmed[urlRange]))
          {
            let altRange = Range(match.range(at: 1), in: trimmed)
            let alt = altRange.map { String(trimmed[$0]) }
            segments.append(.image(url: url, alt: alt))
          }
        } else {
          // Text Block Processing
          if trimmed.isEmpty {
            // blank line, maybe just space? ignore for block list unless handling spacing explicitly
          } else if trimmed.hasPrefix("#") {
            let level = trimmed.prefix(while: { $0 == "#" }).count
            let content = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
            currentTextBlocks.append(.heading(level: level, text: content))
          } else if trimmed.hasPrefix(">") {
            let content = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            currentTextBlocks.append(.blockquote(content))
          } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            currentTextBlocks.append(
              .listItem(text: content, index: 0, ordered: false, indentLevel: 0))
          } else if let match = trimmed.range(of: "^\\d+\\.\\s", options: .regularExpression) {
            let content = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            currentTextBlocks.append(
              .listItem(text: content, index: 1, ordered: true, indentLevel: 0))
          } else {
            // Paragraph
            // Check if we should append to previous paragraph or start new
            // Simple logic: assume new line is new block for now, or new paragraph.
            // Markdown standard says adjacent lines are one paragraph.
            // For simplicity in this chat context, we treats separated lines as paragraphs often,
            // but let's try to merge if previous was paragraph.
            if let last = currentTextBlocks.last, case .paragraph(let oldText) = last {
              // This is a continuation
              currentTextBlocks[currentTextBlocks.count - 1] = .paragraph(oldText + " " + trimmed)
            } else {
              currentTextBlocks.append(.paragraph(trimmed))
            }
          }
        }
      }
      i += 1
    }

    // Flush remaining
    if inCodeBlock {
      // Unclosed code block
      segments.append(.codeBlock(code: codeBlockContent, language: codeBlockLanguage))
    } else if !currentTextBlocks.isEmpty {
      segments.append(.textGroup(currentTextBlocks))
    }

    return segments
  }
}
