import AppKit

final class GitCodeTextView: NSTextView {
  struct Row {
    let line: GitDiffLine?
    let section: String?
    let unified: Bool
    var oldNumbers = false
  }
  static let rowHeight: CGFloat = 21
  var rows: [Row] = []
  var ink = NSColor.labelColor
  private(set) var requiredWidth: CGFloat = 0
  private let retainedStorage: NSTextStorage

  override init(frame: NSRect = .zero, textContainer: NSTextContainer? = nil) {
    let storage = textContainer?.layoutManager?.textStorage ?? NSTextStorage()
    let layout = textContainer?.layoutManager ?? NSLayoutManager()
    let container = textContainer ?? NSTextContainer(containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
    if layout.textStorage == nil { storage.addLayoutManager(layout) }
    if container.layoutManager == nil { layout.addTextContainer(container) }
    retainedStorage = storage
    super.init(frame: frame, textContainer: container)
    isEditable = false; isSelectable = true; isRichText = false
    isAutomaticLinkDetectionEnabled = false; isAutomaticSpellingCorrectionEnabled = false
    isHorizontallyResizable = true; isVerticallyResizable = true
    minSize = .zero; maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    self.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    self.textContainer?.widthTracksTextView = false
    textContainerInset = NSSize(width: 12, height: 12)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func render() {
    let palette = GitReviewPalette(background: backgroundColor)
    let content = NSMutableAttributedString(string: "")
    let paragraph = NSMutableParagraphStyle()
    paragraph.minimumLineHeight = Self.rowHeight; paragraph.maximumLineHeight = Self.rowHeight
    paragraph.tabStops = []; paragraph.defaultTabInterval = 30
    let base: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
      .foregroundColor: ink, .paragraphStyle: paragraph, .ligature: 0]
    for row in rows {
      if let section = row.section {
        var attributes = base
        attributes[.foregroundColor] = palette.blue.withAlphaComponent(0.75)
        content.append(NSAttributedString(string: "      ⋯  \(section)\n", attributes: attributes))
        continue
      }
      let line = row.line
      let number = row.unified ? line?.newLine ?? line?.oldLine : row.oldNumbers ? line?.oldLine : line?.newLine
      let digits = number.map(String.init) ?? ""
      let marker = line?.kind == .addition ? "+" : line?.kind == .deletion ? "−" : " "
      var gutter = base; gutter[.foregroundColor] = ink.withAlphaComponent(0.35)
      if line?.kind == .addition { gutter[.foregroundColor] = palette.addition }
      if line?.kind == .deletion { gutter[.foregroundColor] = palette.deletion }
      content.append(NSAttributedString(string: String(repeating: " ", count: max(0, 5 - digits.count)) + digits + "  " + marker + "  ", attributes: gutter))
      let code = line.map { String($0.text.dropFirst()) } ?? ""
      var attributes = base
      if code.trimmingCharacters(in: .whitespaces).hasPrefix("//") || code.trimmingCharacters(in: .whitespaces).hasPrefix("# ") {
        attributes[.foregroundColor] = ink.withAlphaComponent(0.5)
      }
      content.append(GitCodeHighlighting.code(code, attributes: attributes, palette: palette))
    }
    textStorage?.setAttributedString(content)
    if let container = textContainer, let layout = layoutManager {
      layout.ensureLayout(for: container)
      requiredWidth = layout.usedRect(for: container).width + 30
    }
    needsDisplay = true
  }

  override func drawBackground(in rect: NSRect) {
    super.drawBackground(in: rect)
    let palette = GitReviewPalette(background: backgroundColor)
    let first = max(0, Int((rect.minY - 12) / Self.rowHeight))
    let last = min(rows.count, Int(ceil((rect.maxY - 12) / Self.rowHeight)) + 1)
    guard first < last else { return }
    for index in first..<last {
      let row = rows[index], y = 12 + CGFloat(index) * Self.rowHeight
      let region = NSRect(x: 0, y: y, width: bounds.width, height: Self.rowHeight)
      if row.section != nil {
        palette.blue.withAlphaComponent(0.035).setFill(); region.fill()
      } else if row.line == nil {
        ink.withAlphaComponent(0.025).setFill(); region.fill()
        NSGraphicsContext.saveGraphicsState()
        region.clip(); ink.withAlphaComponent(0.055).setStroke()
        let stripes = NSBezierPath()
        for x in stride(from: -Self.rowHeight, to: bounds.width, by: 9) {
          stripes.move(to: NSPoint(x: x, y: y + Self.rowHeight))
          stripes.line(to: NSPoint(x: x + Self.rowHeight, y: y))
        }
        stripes.stroke(); NSGraphicsContext.restoreGraphicsState()
      } else if row.line?.kind == .addition || row.line?.kind == .deletion {
        let color = row.line?.kind == .addition ? palette.addition : palette.deletion
        color.withAlphaComponent(palette.rowOpacity).setFill(); region.fill()
        color.withAlphaComponent(0.85).setFill()
        NSRect(x: 0, y: y, width: 2, height: Self.rowHeight).fill()
      }
    }
  }
}
