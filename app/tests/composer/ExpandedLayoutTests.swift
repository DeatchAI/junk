import AppKit

@main struct ExpandedLayoutTests {
  @MainActor static func main() {
    _ = NSApplication.shared
    let displays = [
      NSRect(x: 0, y: 25, width: 1440, height: 850),
      NSRect(x: -1920, y: -600, width: 1920, height: 1050),
      NSRect(x: 1440, y: 200, width: 1280, height: 650),
    ]
    for screen in displays {
      for x in [screen.minX - 100, screen.midX, screen.maxX - 60] {
        let original = NSRect(x: x, y: screen.minY - 100, width: 520, height: 280)
        let expanded = FloatingChatWindowLayout.frame(from: original, visibleFrame: screen, expanded: true)
        let usable = screen.insetBy(dx: 20, dy: 20)
        assert(usable.contains(expanded), "Expanded panels must remain inside their own display")
        assert(expanded.width == FloatingChatWindowLayout.width)
        let compact = FloatingChatWindowLayout.frame(from: expanded, visibleFrame: screen, expanded: false)
        assert(usable.contains(compact) && compact.height == 280, "Collapsing preserves screen bounds")
        let resized = FloatingChatWindowLayout.resize(NSSize(width: 900, height: 5000), visibleFrame: screen, expanded: true)
        assert(resized.width == 520 && resized.height == usable.height)
        let small = FloatingChatWindowLayout.resize(NSSize(width: 100, height: 100), visibleFrame: screen, expanded: true)
        assert(small.width == 520 && small.height == 280)
        let compactSize = FloatingChatWindowLayout.resize(NSSize(width: 520, height: 164), visibleFrame: screen, expanded: false)
        assert(compactSize.height == 164, "Compact panels must fit their visible content without an invisible drag boundary")
      }
    }
    let panel = FloatingComposerPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 280),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.fixedContentWidth = 520
    panel.styleMask.insert(.resizable)
    panel.setFrame(NSRect(x: 0, y: 0, width: 900, height: 700), display: false)
    assert(panel.contentRect(forFrameRect: panel.frame).width == 520)
    assert(panel.contentView!.bounds.height == 700)
    panel.styleMask.remove(.resizable)
    panel.setContentSize(NSSize(width: 1000, height: 280))
    assert(panel.contentView!.bounds.size == NSSize(width: 520, height: 280))
    panel.minSize.height = FloatingChatWindowLayout.compactMinimumHeight
    panel.setContentSize(NSSize(width: 520, height: 164))
    assert(panel.contentView!.bounds.height == 164, "The native panel must shrink to the composer")
    let usable = NSRect(x: 0, y: 80, width: 1400, height: 700)
    panel.expandedScreenBounds = usable
    panel.setFrame(NSRect(x: 300, y: -4000, width: 1000, height: 9000), display: false)
    assert(panel.frame.height == usable.height && panel.frame.minY == usable.minY,
      "A content fitting request must not grow the native panel below the display")
    panel.setFrame(NSRect(x: 300, y: 100, width: 520, height: 9000), display: false, animate: false)
    assert(panel.frame.height == usable.height && panel.frame.minY == usable.minY)
    panel.setContentSize(NSSize(width: 1000, height: 12000))
    assert(panel.contentView!.bounds.height == usable.height,
      "Direct content-size requests must enforce the same expanded height limit")
    panel.expandedScreenBounds = nil
    panel.setContentSize(NSSize(width: 520, height: 164))
    assert(panel.frame.height == 164, "Collapsing must release the expanded constraint")
    ExpandedViewportTests.run()
    print("Expanded/collapsed bounds, secondary displays, resize limits and native panel dimensions passed")
  }
}
