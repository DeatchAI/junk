import AppKit
import CoreText
import SwiftUI

/// Actual SwiftUI components with fixtures; no personal history, network or visible windows.
@main struct HistoryVisualPreview {
  @MainActor static func main() throws {
    _ = NSApplication.shared
    let variant = CommandLine.arguments[2]
    let preset: ThemePreset = variant.contains("dark") || variant.contains("glass") ? .lazzydark : .lazzywhite
    UserDefaults.standard.setVolatileDomain([
      "appearance_preset": preset.rawValue,
      "appearance_mode": variant.contains("glass") ? AppearanceMode.glassy.rawValue : AppearanceMode.solid.rawValue,
      HistoryGrouping.settingsKey: variant.hasPrefix("agent") ? HistoryGrouping.agent.rawValue : HistoryGrouping.workingDirectory.rawValue,
    ], forName: UserDefaults.argumentDomain)
    ThemeManager.shared.refreshFromSettings()
    if let font = Bundle.main.url(forResource: "Geist-Regular", withExtension: "ttf") {
      CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
    }
    let directory = URL(fileURLWithPath: CommandLine.arguments[1])
    let manager = WebSocketManager(); let now = Int(Date().timeIntervalSince1970 * 1000)
    func chat(_ id: String, _ title: String, _ provider: String, _ age: Int, folder: String = "/Users/you/Projects/lazzy-v2", resumable: Bool = true) -> Conversation {
      Conversation(id: id, title: title, created_at: now - age, updated_at: now - age, provider: provider,
        workspacePath: folder, origin: "provider", canResume: resumable)
    }
    manager.conversations = [
      chat("one", "Polish Notch Browser glass UI", "codex", 0, folder: "/Users/you/Projects/swift-notch"),
      chat("two", "Rebuild Notch Browser launch teaser", "codex", 60_000, folder: "/Users/you/Projects/swift-notch"),
      chat("three", "Fix tab icons and hover cards", "claude", 100_000, folder: "/Users/you/Projects/swift-notch"),
      chat("four", "Review Notch Browser improvements", "opencode", 200_000, folder: "/Users/you/Projects/swift-notch", resumable: false),
      chat("five", "Simplify browser onboarding", "pi", 300_000, folder: "/Users/you/Projects/swift-notch"),
      chat("six", "Polish browser controls", "codex", 320_000, folder: "/Users/you/Projects/swift-notch"),
      chat("seven", "Review Mac app launch readiness", "codex", 340_000),
      chat("eight", "Add live activity setting", "claude", 350_000),
      chat("nine", "Improve provider integration errors", "codex", 360_000),
      Conversation(id: "legacy", title: "Preserved Detach conversation", created_at: now - 400_000, updated_at: now - 400_000, origin: "legacy"),
    ]
    manager.currentConversationId = "one"
    let state = manager.providerHistory
    state.handle(ProviderHistoryEvent.parse(Data("{\"type\":\"provider_history_status\",\"indexedChats\":6,\"revision\":1}".utf8))!, using: manager)
    func render<V: View>(_ name: String, width: CGFloat, height: CGFloat, view: V) throws {
      let bounds = NSRect(x: 0, y: 0, width: width, height: height)
      let host = NSHostingView(rootView: view.frame(width: width, height: height))
      let window = NSWindow(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
      window.contentView = host; host.frame = bounds; host.layoutSubtreeIfNeeded()
      RunLoop.current.run(until: Date().addingTimeInterval(0.8))
      guard let bitmap = host.bitmapImageRepForCachingDisplay(in: bounds) else { fatalError("No native bitmap") }
      host.cacheDisplay(in: bounds, to: bitmap)
      guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
      try data.write(to: directory.appendingPathComponent(name + ".png"))
      withExtendedLifetime(window) {}
    }
    let panel = HistoryPanelView(wsManager: manager, controller: HistoryWindowController(),
      onSelectConversation: { _ in }, onClose: {})
    try render("warmup-\(variant)", width: 360, height: 640, view: panel)
    try render("history-\(variant)", width: 360, height: 640, view: panel)
    let match = Conversation(id: "body-result", title: "A different title", created_at: now, updated_at: now,
      provider: "claude", origin: "provider", canResume: true, searchSnippet: "…the exact phrase found in a message, across all your agents…")
    try render("title-only-search-row-\(variant)", width: 330, height: 60, view:
      HistoryRowView(conversation: match, isSelected: true, onSelect: {}, onHide: {}).padding(12)
        .background(ThemeManager.shared.backgroundColor).preferredColorScheme(HistoryPanelSurface.colorScheme(for: ThemeManager.shared)))
    // Exercise the exact click-routing handler with isolated native windows, not personal app UI.
    let owner = NSPanel(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    let other = NSPanel(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    let child = NSPanel(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    owner.addChildWindow(child, ordered: .above)
    var dismissals = 0
    let monitor = HistoryClickAwayMonitor()
    monitor.start(for: owner) { dismissals += 1 }
    monitor.handleLocalClick(in: owner); monitor.handleLocalClick(in: child)
    assert(dismissals == 0)
    NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: nil)
    monitor.handleLocalClick(in: other); assert(dismissals == 0, "Keep row context menus usable")
    NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: nil)
    monitor.handleLocalClick(in: other); assert(dismissals == 1)
    monitor.handleExternalClick(); assert(dismissals == 2)
    monitor.stop(); monitor.handleLocalClick(in: other); monitor.handleExternalClick()
    assert(dismissals == 2, "Hidden windows must remove their click observers")
    owner.removeChildWindow(child)
    print("Rendered minimal directory history and verified native click-away routing: \(variant)")
  }
}
