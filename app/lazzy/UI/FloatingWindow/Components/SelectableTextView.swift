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
  }

  // MARK: - Coordinator

  class Coordinator {
    var parent: SelectableTextView
    var blocks: [SelectableTextBlock] = []
    var themeFingerprint: String = ""

    init(_ parent: SelectableTextView) {
      self.parent = parent
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

    // Inline markdown parser - strips syntax and applies styles
    func renderMarkdownText(
      _ text: String, baseAttributes: [NSAttributedString.Key: Any], theme: ThemeManager
    ) -> NSAttributedString {
      let result = NSMutableAttributedString()
      var remaining = text

      // Pattern to match: **bold**, *italic*, `code`, or plain text
      let pattern = #"(\*\*(.+?)\*\*)|(\*(.+?)\*)|(`([^`]+)`)"#
      guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return NSAttributedString(string: text, attributes: baseAttributes)
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
          result.append(NSAttributedString(string: plainText, attributes: baseAttributes))
        }

        // Determine which group matched and apply appropriate style
        if match.range(at: 1).location != NSNotFound,
          let innerRange = Range(match.range(at: 2), in: remaining)
        {
          // Bold: **text**
          let innerText = String(remaining[innerRange])
          var boldAttrs = baseAttributes
          if let font = baseAttributes[.font] as? NSFont {
            boldAttrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
          }
          result.append(NSAttributedString(string: innerText, attributes: boldAttrs))
        } else if match.range(at: 3).location != NSNotFound,
          let innerRange = Range(match.range(at: 4), in: remaining)
        {
          // Italic: *text*
          let innerText = String(remaining[innerRange])
          var italicAttrs = baseAttributes
          if let font = baseAttributes[.font] as? NSFont {
            italicAttrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
          }
          result.append(NSAttributedString(string: innerText, attributes: italicAttrs))
        } else if match.range(at: 5).location != NSNotFound,
          let innerRange = Range(match.range(at: 6), in: remaining)
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
        result.append(NSAttributedString(string: plainText, attributes: baseAttributes))
      }

      return result
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
