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
      .foregroundColor: NSColor(theme.accentColor),
      .underlineStyle: NSUnderlineStyle.single.rawValue,
      .underlineColor: NSColor(theme.accentColor).withAlphaComponent(0.65),
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
      .foregroundColor: NSColor(theme.accentColor),
      .underlineStyle: NSUnderlineStyle.single.rawValue,
      .underlineColor: NSColor(theme.accentColor).withAlphaComponent(0.65),
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

      // Font setup
      // Use the custom font if available, fallback to system
      let fontSize: CGFloat = 14
      let font =
        NSFont(name: "Geist-Regular", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
      let textColor = NSColor(theme.textColor)

      let paragraphStyle = NSMutableParagraphStyle()
      paragraphStyle.lineSpacing = 5
      paragraphStyle.paragraphSpacing = 12
      paragraphStyle.lineBreakMode = .byWordWrapping

      let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: textColor,
        .paragraphStyle: paragraphStyle,
      ]

      for (index, block) in blocks.enumerated() {
        var blockString: NSAttributedString

        switch block {
        case .paragraph(let text):
          blockString = renderMarkdownText(text, baseAttributes: attributes, theme: theme)

        case .heading(let level, let text):
          let headingSize = fontSize + CGFloat(4 - min(level, 3)) * 2  // Simple scaling
          let headingFont =
            NSFont(name: "Geist-Regular", size: headingSize)
            ?? NSFont.boldSystemFont(ofSize: headingSize)

          var headingAttrs = attributes
          headingAttrs[.font] = headingFont
          // Reduce paragraph spacing after headings slightly
          let headingStyle = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
          headingStyle.paragraphSpacing = 8
          headingStyle.lineBreakMode = .byWordWrapping
          headingAttrs[.paragraphStyle] = headingStyle

          blockString = renderMarkdownText(text, baseAttributes: headingAttrs, theme: theme)

        case .blockquote(let text):
          let style = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
          style.headIndent = 12
          style.firstLineHeadIndent = 12
          style.lineBreakMode = .byWordWrapping

          var modifiedAttrs = attributes
          modifiedAttrs[.paragraphStyle] = style
          modifiedAttrs[.foregroundColor] = NSColor(theme.secondaryTextColor)

          blockString = renderMarkdownText(text, baseAttributes: modifiedAttrs, theme: theme)

        case .listItem(let text, _, _, let indentLevel):
          let style = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
          let indent = CGFloat(indentLevel + 1) * 16
          style.headIndent = indent
          style.firstLineHeadIndent = indent - 10
          style.tabStops = [NSTextTab(textAlignment: .left, location: indent, options: [:])]
          style.lineBreakMode = .byWordWrapping

          var listAttrs = attributes
          listAttrs[.paragraphStyle] = style

          let bullet = "•\t"
          let content = renderMarkdownText(text, baseAttributes: listAttrs, theme: theme)
          let fullString = NSMutableAttributedString(string: bullet, attributes: listAttrs)
          fullString.append(content)
          blockString = fullString
        }

        result.append(blockString)

        // Add newline between blocks if not last
        if index < blocks.count - 1 {
          result.append(NSAttributedString(string: "\n", attributes: attributes))
        }
      }

      return result
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

    // Inline markdown parser - strips syntax and applies styles
    func renderMarkdownText(
      _ text: String, baseAttributes: [NSAttributedString.Key: Any], theme: ThemeManager
    ) -> NSAttributedString {
      let result = NSMutableAttributedString()
      let remaining = text

      // Links come first so labels are styled as one interactive reference
      // instead of being split into plain brackets and inline styles.
      let pattern = #"\[([^\]]+)\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)|(\*\*(.+?)\*\*)|(\*(.+?)\*)|(`([^`]+)`)"#
      guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return attributedPlainText(text, baseAttributes: baseAttributes, theme: theme)
      }

      var lastEnd = remaining.startIndex
      let nsString = remaining as NSString
      let matches = regex.matches(
        in: remaining, range: NSRange(location: 0, length: nsString.length))

      for match in matches {
        let matchRange = Range(match.range, in: remaining)!

        // Append text before this match
        if lastEnd < matchRange.lowerBound {
          let plainText = String(remaining[lastEnd..<matchRange.lowerBound])
          result.append(attributedPlainText(plainText, baseAttributes: baseAttributes, theme: theme))
        }

        // Determine which group matched and apply appropriate style
        if match.range(at: 1).location != NSNotFound,
          let innerRange = Range(match.range(at: 2), in: remaining)
        {
          let labelRange = Range(match.range(at: 1), in: remaining)!
          result.append(
            attributedReference(
              label: String(remaining[labelRange]),
              target: String(remaining[innerRange]),
              baseAttributes: baseAttributes,
              theme: theme
            )
          )
        } else if match.range(at: 3).location != NSNotFound,
          let innerRange = Range(match.range(at: 4), in: remaining)
        {
          // Bold: **text**
          let innerText = String(remaining[innerRange])
          var boldAttrs = baseAttributes
          if let font = baseAttributes[.font] as? NSFont {
            boldAttrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
          }
          result.append(NSAttributedString(string: innerText, attributes: boldAttrs))
        } else if match.range(at: 5).location != NSNotFound,
          let innerRange = Range(match.range(at: 6), in: remaining)
        {
          // Italic: *text*
          let innerText = String(remaining[innerRange])
          var italicAttrs = baseAttributes
          if let font = baseAttributes[.font] as? NSFont {
            italicAttrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
          }
          result.append(NSAttributedString(string: innerText, attributes: italicAttrs))
        } else if match.range(at: 7).location != NSNotFound,
          let innerRange = Range(match.range(at: 8), in: remaining)
        {
          // Code: `text`
          let innerText = String(remaining[innerRange])
          var codeAttrs = baseAttributes
          codeAttrs[.font] = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
          codeAttrs[.backgroundColor] = NSColor(theme.secondaryTextColor).withAlphaComponent(0.1)
          result.append(NSAttributedString(string: innerText, attributes: codeAttrs))
        }

        lastEnd = matchRange.upperBound
      }

      // Append remaining text after last match
      if lastEnd < remaining.endIndex {
        let plainText = String(remaining[lastEnd...])
        result.append(attributedPlainText(plainText, baseAttributes: baseAttributes, theme: theme))
      }

      return result
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
      let accent = NSColor(theme.accentColor)
      attributes[.foregroundColor] = accent
      attributes[.backgroundColor] = accent.withAlphaComponent(0.12)
      attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
      attributes[.underlineColor] = accent.withAlphaComponent(0.65)
      if let font = baseAttributes[.font] as? NSFont {
        attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
      }

      if target.hasPrefix("/") {
        let path = target.split(separator: "#", maxSplits: 1).first.map(String.init) ?? target
        attributes[.link] = URL(fileURLWithPath: path)
      } else if let url = URL(string: target), url.scheme != nil {
        attributes[.link] = url
      }
      return NSAttributedString(string: label, attributes: attributes)
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
    size.height += 4  // minimal padding
    return size
  }
}

// Helper for theme observation
extension ThemeManager {
  fileprivate var fingerprint: String {
    "\(textColor.hashValue)-\(backgroundColor.hashValue)"
  }

}
