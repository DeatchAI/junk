import AppKit

/// Native selectable code, with synchronized scrolling and aligned replacement blocks.
final class GitDiffEditor: NSView {
  private let panes = [NSScrollView(), NSScrollView()]
  private let editors = [GitCodeTextView(), GitCodeTextView()]
  private var observers: [NSObjectProtocol] = []
  private var synchronizing = false
  private var split = true
  private var lastText: String?
  private var lastForeground: NSColor?
  private var lastBackground: NSColor?
  private var dividerColor = NSColor.separatorColor

  override init(frame: NSRect) {
    super.init(frame: frame)
    for index in panes.indices {
      let scroll = panes[index], editor = editors[index]
      scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
      scroll.autohidesScrollers = true; scroll.borderType = .noBorder
      scroll.documentView = editor
      scroll.contentView.postsBoundsChangedNotifications = true
      addSubview(scroll)
      observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
        object: scroll.contentView, queue: .main) { [weak self] _ in self?.synchronize(from: index) })
      editor.setAccessibilityLabel(index == 0 ? "Code before changes" : "Code after changes")
    }
  }

  convenience init() { self.init(frame: .zero) }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }

  override func layout() {
    super.layout()
    let width = split ? floor((bounds.width - 1) / 2) : bounds.width
    panes[0].frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
    panes[1].frame = NSRect(x: width + 1, y: 0, width: max(0, bounds.width - width - 1), height: bounds.height)
    sizeDocuments()
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if split {
      dividerColor.setFill()
      NSRect(x: floor((bounds.width - 1) / 2), y: 0, width: 1, height: bounds.height).fill()
    }
  }

  func update(text: String, foreground: NSColor, background: NSColor, split: Bool) {
    guard text != lastText || foreground != lastForeground || background != lastBackground || self.split != split else { return }
    let reset = text != lastText || self.split != split
    lastText = text; lastForeground = foreground; lastBackground = background; self.split = split
    dividerColor = foreground.withAlphaComponent(0.10)
    panes[1].isHidden = !split
    let rows = GitDiffLines.aligned(text)
    for index in panes.indices {
      panes[index].backgroundColor = background
      let editor = editors[index]
      editor.backgroundColor = background; editor.ink = foreground
      editor.rows = split ? rows.map { row in
        GitCodeTextView.Row(line: index == 0 ? row.before : row.after, section: row.section, unified: false, oldNumbers: index == 0)
      } : GitDiffLines.parse(text).compactMap { line in
        if line.kind == .metadata {
          guard !line.text.isEmpty, !line.text.hasPrefix("diff --git "), !line.text.hasPrefix("index "),
            !line.text.hasPrefix("--- "), !line.text.hasPrefix("+++ ") else { return nil }
          return GitCodeTextView.Row(line: nil, section: line.text, unified: true)
        }
        return GitCodeTextView.Row(line: line, section: nil, unified: true)
      }
      editor.render()
      if reset { panes[index].contentView.scroll(to: .zero) }
    }
    editors[0].setAccessibilityLabel(split ? "Code before changes" : "Unified code diff")
    needsLayout = true; needsDisplay = true
  }

  private func sizeDocuments() {
    let width = max(panes[0].contentSize.width, editors.map(\.requiredWidth).max() ?? 0)
    for index in panes.indices {
      editors[index].setFrameSize(NSSize(width: width,
        height: max(panes[index].contentSize.height, CGFloat(editors[index].rows.count) * GitCodeTextView.rowHeight + 24)))
    }
  }

  private func synchronize(from index: Int) {
    guard split, !synchronizing else { return }
    synchronizing = true
    let other = panes[1 - index]
    other.contentView.scroll(to: panes[index].contentView.bounds.origin)
    other.reflectScrolledClipView(other.contentView)
    synchronizing = false
  }
}
