import AppKit

enum ComposerTokenText {
  static func serialized(_ text: NSAttributedString, readable: Bool = false) -> String {
    let result = NSMutableAttributedString(attributedString: text)
    var replacements: [(NSRange, String)] = []
    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
      guard let attachment = value as? ComposerTokenAttachment else { return }
      replacements.append((range, readable ? attachment.token.replacement : attachment.token.marker))
    }
    for (range, replacement) in replacements.reversed() { result.replaceCharacters(in: range, with: replacement) }
    return result.string
  }

  static func render(_ text: String, tokens: [ComposerInlineToken], font: NSFont,
                     color: NSColor, maximumWidth: CGFloat) -> NSAttributedString {
    let result = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    var matches: [(NSRange, ComposerInlineToken)] = []
    for token in tokens {
      let pattern = token.marker.hasPrefix("[[") ? NSRegularExpression.escapedPattern(for: token.marker)
        : #"(?<!\S)\#(NSRegularExpression.escapedPattern(for: token.marker))(?=\s|$)"#
      guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
      for match in expression.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
        matches.append((match.range, token))
      }
    }
    var replacedStart = result.length
    for (range, token) in matches.sorted(by: { $0.0.location > $1.0.location }) where NSMaxRange(range) <= replacedStart {
      let attachment = ComposerTokenAttachment(token: token, font: font, color: color, maximumWidth: maximumWidth)
      result.replaceCharacters(in: range, with: NSAttributedString(attachment: attachment))
      replacedStart = range.location
    }
    return result
  }

  static func rawOffset(_ offset: Int, in text: NSAttributedString) -> Int {
    var raw = min(max(offset, 0), text.length)
    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: min(max(offset, 0), text.length))) { value, _, _ in
      guard let attachment = value as? ComposerTokenAttachment else { return }
      raw += attachment.token.marker.utf16.count - 1
    }
    return raw
  }

  static func displayOffset(_ rawOffset: Int, in text: NSAttributedString) -> Int {
    var extra = 0
    var result: Int?
    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, stop in
      guard let attachment = value as? ComposerTokenAttachment else { return }
      let start = range.location + extra
      if rawOffset <= start { result = rawOffset - extra; stop.pointee = true; return }
      let end = start + attachment.token.marker.utf16.count
      if rawOffset < end { result = range.location + 1; stop.pointee = true; return }
      extra += attachment.token.marker.utf16.count - 1
    }
    return min(max(result ?? rawOffset - extra, 0), text.length)
  }
}

final class ComposerTokenAttachment: NSTextAttachment {
  let token: ComposerInlineToken

  init(token: ComposerInlineToken, font: NSFont, color: NSColor, maximumWidth: CGFloat) {
    self.token = token
    super.init(data: nil, ofType: nil)
    attachmentCell = ComposerTokenCell(token: token, font: font, color: color, maximumWidth: maximumWidth)
  }

  required init?(coder: NSCoder) { return nil }
}

private final class ComposerTokenCell: NSTextAttachmentCell {
  let token: ComposerInlineToken
  let labelFont: NSFont
  let color: NSColor
  nonisolated let width: CGFloat

  init(token: ComposerInlineToken, font: NSFont, color: NSColor, maximumWidth: CGFloat) {
    self.token = token; self.labelFont = font; self.color = color
    width = min(maximumWidth, min(220, ceil((token.label as NSString).size(withAttributes: [.font: font]).width) + 31))
    super.init(textCell: token.label)
  }

  required init(coder: NSCoder) { fatalError("Composer tokens are not archived") }
  nonisolated override func cellSize() -> NSSize { NSSize(width: max(40, width), height: 23) }
  nonisolated override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -5) }

  override func draw(withFrame frame: NSRect, in controlView: NSView?) {
    let rect = frame.insetBy(dx: 0, dy: 1)
    color.withAlphaComponent(0.1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
    let icon = NSImage(systemSymbolName: token.symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(paletteColors: [color.withAlphaComponent(0.7)]))
    icon?.draw(in: NSRect(x: rect.minX + 6, y: rect.midY - 6, width: 12, height: 12))
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingMiddle
    (token.label as NSString).draw(in: NSRect(x: rect.minX + 23, y: rect.midY - labelFont.ascender / 2 - 2,
      width: rect.width - 29, height: labelFont.ascender - labelFont.descender + 2), withAttributes: [
        .font: labelFont, .foregroundColor: color.withAlphaComponent(0.9), .paragraphStyle: paragraph])
  }
}
