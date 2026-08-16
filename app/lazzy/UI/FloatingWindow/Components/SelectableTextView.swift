import AppKit
import SwiftUI

// MARK: - Text Block for Rendering

/// Represents a text block to be rendered in NSTextView
enum SelectableTextBlock: Equatable, Hashable {
  case paragraph(String)
  case heading(level: Int, text: String)
  case blockquote(String)
  case listItem(text: String, index: Int, ordered: Bool, indentLevel: Int)
}

// MARK: - Selectable Text View

struct SelectableTextView: NSViewRepresentable {
  let blocks: [SelectableTextBlock]
  let baseWidth: CGFloat
  @ObservedObject var theme: ThemeManager

  // Cache key not strictly needed for basic implementation but good for future reuse compatibility
  var cacheKey: String? = nil

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> SelectableNSTextView {
    let textView = SelectableNSTextView()
    textView.isEditable = false
    textView.isSelectable = true
    textView.isRichText = true
    textView.delegate = context.coordinator
    textView.drawsBackground = false
    textView.backgroundColor = .clear
    textView.textContainerInset = .zero

    // Allow vertical resizing for content, but NOT horizontal
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false

    // Constrain max size to prevent horizontal expansion
    textView.maxSize = NSSize(width: baseWidth, height: CGFloat.greatestFiniteMagnitude)
    textView.minSize = NSSize(width: 0, height: 0)

    // Remove text container padding to align perfectly
    textView.textContainer?.lineFragmentPadding = 0

    // Track the text view width so wrapping follows the SwiftUI width we set
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.textContainer?.containerSize = NSSize(
      width: baseWidth, height: CGFloat.greatestFiniteMagnitude
    )
    textView.frame.size.width = baseWidth

    // Ensure autoresizing doesn't expand width
    textView.autoresizingMask = [.height]

    // Apply theme selection color
    let selectionColor = NSColor(theme.accentColor).withAlphaComponent(0.3)
    textView.selectedTextAttributes = [
      .backgroundColor: selectionColor
    ]
    textView.linkTextAttributes = [
      .foregroundColor: NSColor.linkColor,
      .underlineStyle: NSUnderlineStyle.single.rawValue,
      .underlineColor: NSColor.linkColor.withAlphaComponent(0.72),
    ]

    return textView
  }

  func updateNSView(_ textView: SelectableNSTextView, context: Context) {
    // Always keep container and view width in sync with SwiftUI width
    textView.textContainer?.containerSize = NSSize(
      width: baseWidth, height: CGFloat.greatestFiniteMagnitude
    )
    textView.maxSize = NSSize(width: baseWidth, height: CGFloat.greatestFiniteMagnitude)
    if textView.frame.size.width != baseWidth {
      textView.frame.size.width = baseWidth
    }

    // Check if blocks or theme changed
    if context.coordinator.blocks != blocks
      || context.coordinator.themeFingerprint != theme.fingerprint
    {
      let formatted = context.coordinator.buildAttributedString(
        blocks: blocks,
        theme: theme,
        baseWidth: baseWidth
      )
      textView.textStorage?.setAttributedString(formatted)

      // Force layout to determine height if needed
      textView.layoutManager?.ensureLayout(for: textView.textContainer!)

      context.coordinator.blocks = blocks
      context.coordinator.themeFingerprint = theme.fingerprint
    }

    textView.linkTextAttributes = [
      .foregroundColor: NSColor.linkColor,
      .underlineStyle: NSUnderlineStyle.single.rawValue,
      .underlineColor: NSColor.linkColor.withAlphaComponent(0.72),
    ]
  }

  // MARK: - Coordinator

  class Coordinator: NSObject, NSTextViewDelegate {
    var parent: SelectableTextView
    var blocks: [SelectableTextBlock] = []
    var themeFingerprint: String = ""

    init(_ parent: SelectableTextView) {
      self.parent = parent
      super.init()
    }

    func buildAttributedString(
      blocks: [SelectableTextBlock], theme: ThemeManager, baseWidth: CGFloat
    ) -> NSAttributedString {
      let result = NSMutableAttributedString()
      let fontSize: CGFloat = 14
      let font = markdownFont(size: fontSize)
      let textColor = NSColor(theme.textColor)

      let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: textColor,
      ]

      for (index, block) in blocks.enumerated() {
        let isLast = index == blocks.count - 1
        let nextIsList = !isLast && blocks[index + 1].isListItem
        let blockString: NSAttributedString
        let terminalAttributes: [NSAttributedString.Key: Any]

        switch block {
        case .paragraph(let text):
          let style = paragraphStyle(lineSpacing: 3, paragraphSpacing: 8)
          var attributes = baseAttributes
          attributes[.paragraphStyle] = style
          blockString = renderMarkdownText(text, baseAttributes: attributes, theme: theme)
          terminalAttributes = attributes

        case .heading(let level, let text):
          let headingSize: CGFloat
          switch level {
          case 1: headingSize = 20
          case 2: headingSize = 18
          case 3: headingSize = 16
          case 4: headingSize = 15
          default: headingSize = 14
          }

          let style = paragraphStyle(
            lineSpacing: 2,
            paragraphSpacing: 6,
            paragraphSpacingBefore: index == 0 ? 0 : (level <= 2 ? 10 : 7)
          )
          var attributes = baseAttributes
          attributes[.font] = markdownFont(size: headingSize, bold: true)
          attributes[.paragraphStyle] = style
          blockString = renderMarkdownText(text, baseAttributes: attributes, theme: theme)
          terminalAttributes = attributes

        case .blockquote(let text):
          let style = paragraphStyle(lineSpacing: 3, paragraphSpacing: 8)
          style.headIndent = 15
          style.firstLineHeadIndent = 15
          var attributes = baseAttributes
          attributes[.paragraphStyle] = style
          attributes[.foregroundColor] = NSColor(theme.secondaryTextColor)

          let quote = NSMutableAttributedString(
            string: "▏ ",
            attributes: [
              .font: markdownFont(size: fontSize, bold: true),
              .foregroundColor: NSColor(theme.textColor).withAlphaComponent(0.18),
              .paragraphStyle: style,
            ]
          )
          quote.append(renderMarkdownText(text, baseAttributes: attributes, theme: theme))
          blockString = quote
          terminalAttributes = attributes

        case .listItem(let text, let index, let ordered, let indentLevel):
          let style = paragraphStyle(
            lineSpacing: 3,
            paragraphSpacing: nextIsList ? 3 : 8
          )
          let firstIndent = CGFloat(indentLevel) * 16 + 2
          let contentIndent = firstIndent + (ordered ? 22 : 16)
          style.firstLineHeadIndent = firstIndent
          style.headIndent = contentIndent
          style.tabStops = [
            NSTextTab(textAlignment: .left, location: contentIndent, options: [:])
          ]

          var attributes = baseAttributes
          attributes[.paragraphStyle] = style

          let marker = ordered ? "\(index).\t" : "•\t"
          let content = renderMarkdownText(text, baseAttributes: attributes, theme: theme)
          let fullString = NSMutableAttributedString(string: marker, attributes: attributes)
          fullString.append(content)
          blockString = fullString
          terminalAttributes = attributes
        }

        result.append(blockString)

        if !isLast {
          result.append(NSAttributedString(string: "\n", attributes: terminalAttributes))
        }
      }

      return result
    }

    private func paragraphStyle(
      lineSpacing: CGFloat,
      paragraphSpacing: CGFloat,
      paragraphSpacingBefore: CGFloat = 0
    ) -> NSMutableParagraphStyle {
      let style = NSMutableParagraphStyle()
      style.lineSpacing = lineSpacing
      style.paragraphSpacing = paragraphSpacing
      style.paragraphSpacingBefore = paragraphSpacingBefore
      style.lineBreakMode = .byWordWrapping
      return style
    }

    private func markdownFont(size: CGFloat, bold: Bool = false) -> NSFont {
      let font = NSFont(name: "Geist-Regular", size: size) ?? NSFont.systemFont(ofSize: size)
      guard bold else { return font }
      return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
      guard let url = link as? URL else { return false }

      if url.isFileURL {
        NSWorkspace.shared.activateFileViewerSelecting([url])
      } else {
        NSWorkspace.shared.open(url)
      }
      return true
    }

    func renderMarkdownText(
      _ text: String, baseAttributes: [NSAttributedString.Key: Any], theme: ThemeManager
    ) -> NSAttributedString {
      let result = NSMutableAttributedString()
      var cursor = text.startIndex
      var plainStart = cursor

      func flushPlain(until end: String.Index) {
        guard plainStart < end else { return }
        result.append(
          attributedPlainText(
            String(text[plainStart..<end]),
            baseAttributes: baseAttributes,
            theme: theme
          )
        )
      }

      func appendStyled(
        range: Range<String.Index>,
        attributes: [NSAttributedString.Key: Any]
      ) {
        result.append(
          renderMarkdownText(
            String(text[range]),
            baseAttributes: attributes,
            theme: theme
          )
        )
      }

      while cursor < text.endIndex {
        let character = text[cursor]

        if character == "\\" {
          let escapedIndex = text.index(after: cursor)
          guard escapedIndex < text.endIndex else {
            cursor = escapedIndex
            continue
          }
          flushPlain(until: cursor)
          result.append(
            attributedPlainText(
              String(text[escapedIndex]),
              baseAttributes: baseAttributes,
              theme: theme
            )
          )
          cursor = text.index(after: escapedIndex)
          plainStart = cursor
          continue
        }

        if character == "`" {
          let fenceLength = delimiterRunLength(in: text, from: cursor, character: "`")
          let contentStart = text.index(cursor, offsetBy: fenceLength)
          let delimiter = String(repeating: "`", count: fenceLength)
          if let closingRange = text.range(
            of: delimiter,
            range: contentStart..<text.endIndex
          ) {
            flushPlain(until: cursor)
            var code = String(text[contentStart..<closingRange.lowerBound])
              .replacingOccurrences(of: "\n", with: " ")
            if code.hasPrefix(" "), code.hasSuffix(" "), code.count > 2,
              !code.trimmingCharacters(in: .whitespaces).isEmpty
            {
              code.removeFirst()
              code.removeLast()
            }

            var attributes = baseAttributes
            attributes[.font] = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
            attributes[.foregroundColor] = NSColor(theme.textColor).withAlphaComponent(0.94)
            attributes[.backgroundColor] = NSColor(theme.textColor).withAlphaComponent(0.075)
            attributes[.ligature] = 0
            result.append(NSAttributedString(string: code, attributes: attributes))

            cursor = closingRange.upperBound
            plainStart = cursor
            continue
          }
        }

        if character == "[",
          let labelEnd = text[cursor...].firstIndex(of: "]"),
          text.index(after: labelEnd) < text.endIndex,
          text[text.index(after: labelEnd)] == "(",
          let destinationEnd = text[text.index(labelEnd, offsetBy: 2)...].firstIndex(of: ")")
        {
          let labelStart = text.index(after: cursor)
          let destinationStart = text.index(labelEnd, offsetBy: 2)
          let rawDestination = String(text[destinationStart..<destinationEnd])
          let destination = rawDestination.components(separatedBy: " \"").first ?? rawDestination

          flushPlain(until: cursor)
          let label = NSMutableAttributedString(
            attributedString: renderMarkdownText(
              String(text[labelStart..<labelEnd]),
              baseAttributes: baseAttributes,
              theme: theme
            )
          )
          applyReferenceStyle(to: label, target: destination)
          result.append(label)

          cursor = text.index(after: destinationEnd)
          plainStart = cursor
          continue
        }

        if text[cursor...].hasPrefix("**") {
          let contentStart = text.index(cursor, offsetBy: 2)
          if let closingRange = text.range(of: "**", range: contentStart..<text.endIndex) {
            flushPlain(until: cursor)
            var attributes = baseAttributes
            if let font = baseAttributes[.font] as? NSFont {
              attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            appendStyled(
              range: contentStart..<closingRange.lowerBound,
              attributes: attributes
            )
            cursor = closingRange.upperBound
            plainStart = cursor
            continue
          }
        }

        if text[cursor...].hasPrefix("~~") {
          let contentStart = text.index(cursor, offsetBy: 2)
          if let closingRange = text.range(of: "~~", range: contentStart..<text.endIndex) {
            flushPlain(until: cursor)
            var attributes = baseAttributes
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = NSColor(theme.secondaryTextColor)
            appendStyled(
              range: contentStart..<closingRange.lowerBound,
              attributes: attributes
            )
            cursor = closingRange.upperBound
            plainStart = cursor
            continue
          }
        }

        if character == "*" {
          let contentStart = text.index(after: cursor)
          if let closingIndex = text[contentStart...].firstIndex(of: "*") {
            flushPlain(until: cursor)
            var attributes = baseAttributes
            if let font = baseAttributes[.font] as? NSFont {
              attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
            appendStyled(range: contentStart..<closingIndex, attributes: attributes)
            cursor = text.index(after: closingIndex)
            plainStart = cursor
            continue
          }
        }

        cursor = text.index(after: cursor)
      }

      flushPlain(until: text.endIndex)

      return result
    }

    private func delimiterRunLength(
      in text: String,
      from start: String.Index,
      character: Character
    ) -> Int {
      var index = start
      var count = 0
      while index < text.endIndex, text[index] == character {
        count += 1
        index = text.index(after: index)
      }
      return count
    }

    private func attributedPlainText(
      _ text: String,
      baseAttributes: [NSAttributedString.Key: Any],
      theme: ThemeManager
    ) -> NSAttributedString {
      let result = NSMutableAttributedString()
      let pattern = #"(?:(?:https?|file)://[^\s<>()]+)|(?:(?:(?:[A-Za-z0-9._-]+/)*[A-Za-z0-9_-]+\.(?:swift|m|mm|h|ts|tsx|js|jsx|json|md|py|go|rs|java|kt|css|html|yaml|yml|sh|rb|sql|c|cpp|cc|hpp))(?:\s*\(line\s+\d+\)|:\d+)?)"#
      guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return NSAttributedString(string: text, attributes: baseAttributes)
      }

      let fullRange = NSRange(location: 0, length: (text as NSString).length)
      var cursor = 0
      for match in regex.matches(in: text, range: fullRange) {
        if cursor < match.range.location {
          result.append(
            NSAttributedString(
              string: (text as NSString).substring(with: NSRange(location: cursor, length: match.range.location - cursor)),
              attributes: baseAttributes
            )
          )
        }

        let rawReference = (text as NSString).substring(with: match.range)
        let reference = rawReference.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        result.append(
          attributedReference(
            label: reference,
            target: reference,
            baseAttributes: baseAttributes,
            theme: theme
          )
        )
        let trailing = String(rawReference.dropFirst(reference.count))
        if !trailing.isEmpty {
          result.append(NSAttributedString(string: trailing, attributes: baseAttributes))
        }
        cursor = NSMaxRange(match.range)
      }

      if cursor < fullRange.length {
        result.append(
          NSAttributedString(
            string: (text as NSString).substring(from: cursor),
            attributes: baseAttributes
          )
        )
      }
      return result
    }

    private func attributedReference(
      label: String,
      target: String,
      baseAttributes: [NSAttributedString.Key: Any],
      theme: ThemeManager
    ) -> NSAttributedString {
      var attributes = baseAttributes
      attributes[.foregroundColor] = NSColor.linkColor
      attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
      attributes[.underlineColor] = NSColor.linkColor.withAlphaComponent(0.72)

      if let url = referenceURL(for: target) {
        attributes[.link] = url
      }
      return NSAttributedString(string: label, attributes: attributes)
    }

    private func applyReferenceStyle(to string: NSMutableAttributedString, target: String) {
      guard string.length > 0 else { return }
      let range = NSRange(location: 0, length: string.length)
      string.addAttributes(
        [
          .foregroundColor: NSColor.linkColor,
          .underlineStyle: NSUnderlineStyle.single.rawValue,
          .underlineColor: NSColor.linkColor.withAlphaComponent(0.72),
        ],
        range: range
      )
      if let url = referenceURL(for: target) {
        string.addAttribute(.link, value: url, range: range)
      }
    }

    private func referenceURL(for target: String) -> URL? {
      if target.hasPrefix("/") {
        let withoutFragment = target.split(separator: "#", maxSplits: 1).first.map(String.init) ?? target
        let path =
          withoutFragment.replacingOccurrences(
            of: #"(?:\s+\(line\s+\d+\)|:\d+)$"#,
            with: "",
            options: .regularExpression
          )
        return URL(fileURLWithPath: path)
      }

      guard let url = URL(string: target), url.scheme != nil else { return nil }
      return url
    }
  }
}

// Subclass to aid debugging if needed
class SelectableNSTextView: NSTextView {
  override var intrinsicContentSize: NSSize {
    guard let layoutManager = layoutManager, let textContainer = textContainer else {
      return super.intrinsicContentSize
    }
    layoutManager.ensureLayout(for: textContainer)
    var size = layoutManager.usedRect(for: textContainer).size
    size.height += 1
    return size
  }
}

// Helper for theme observation
extension ThemeManager {
  fileprivate var fingerprint: String {
    "\(textColor.hashValue)-\(backgroundColor.hashValue)"
  }

}

private extension SelectableTextBlock {
  var isListItem: Bool {
    if case .listItem = self {
      return true
    }
    return false
  }
}
