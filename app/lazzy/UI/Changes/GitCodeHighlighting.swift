import AppKit

enum GitCodeHighlighting {
  // One pass keeps comment/string contents from being recolored as keywords.
  private static let tokens = try? NSRegularExpression(pattern: #"(?<comment>//.*$|/\*.*?(?:\*/|$))|(?<string>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`)|(?<keyword>\b(?:actor|as|async|await|break|case|catch|class|const|continue|default|defer|do|else|enum|export|extension|false|final|for|from|func|function|guard|if|implements|import|in|init|interface|is|let|new|nil|null|override|private|protected|protocol|public|return|self|static|struct|super|switch|throw|throws|true|try|type|undefined|var|where|while)\b)|(?<type>\b[A-Z][A-Za-z0-9_]*\b)|(?<number>\b\d+(?:\.\d+)?\b)"#)

  static func code(_ text: String, attributes: [NSAttributedString.Key: Any], palette: GitReviewPalette) -> NSAttributedString {
    let result = NSMutableAttributedString(string: text + "\n", attributes: attributes)
    let matches = tokens?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
    for match in matches {
      let color: NSColor
      if match.range(withName: "comment").location != NSNotFound {
        color = (attributes[.foregroundColor] as? NSColor ?? .labelColor).withAlphaComponent(0.5)
      } else if match.range(withName: "string").location != NSNotFound { color = palette.modified }
      else if match.range(withName: "keyword").location != NSNotFound { color = palette.purple }
      else if match.range(withName: "type").location != NSNotFound { color = palette.teal }
      else { color = palette.blue }
      result.addAttribute(.foregroundColor, value: color, range: match.range)
    }
    return result
  }
}
