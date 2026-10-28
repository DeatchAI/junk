import AppKit
import SwiftUI
@testable import Detach

/// Links the rebuilt app instead of substituting a simplified chat view.
/// Run as a separate app: synthetic history, isolated preferences, no runtime.
@MainActor final class ComposerRegressionDelegate: NSObject, NSApplicationDelegate {
  private var controller: FloatingWindowController?
  private var manager: WebSocketManager?
  private let output = URL(fileURLWithPath: "/tmp/detach-composer-regression")

  func applicationDidFinishLaunching(_ notification: Notification) {
    try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let menu = NSMenu()
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    let item = NSMenuItem()
    item.submenu = appMenu
    menu.addItem(item)
    NSApp.mainMenu = menu
    UserDefaults.standard.setVolatileDomain([
      "appearance_preset": "lazzydark", "appearance_mode": "Solid",
      "appearance_bg_color": "#000000", "appearance_fg_color": "#FFFFFF",
    ], forName: UserDefaults.argumentDomain)
    ThemeManager.shared.refreshFromSettings()

    let manager = WebSocketManager()
    manager.isConnecting = true
    manager.session?.invalidateAndCancel()
    manager.session = nil
    self.manager = manager
    let controller = FloatingWindowController(wsManager: manager, selectedAgent: "codex", selectedModel: nil)
    self.controller = controller
    controller.show(at: NSPoint(x: 450, y: 450), with: nil)
    controller.chatWindow?.title = "Detach composer regression"
    controller.toggleExpansion()

    // Populate the actual history callback after the real view has appeared.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.loadHistory() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.exerciseContentFitting() }
  }

  private func loadHistory() {
    guard let manager else { return }
    let id = "synthetic-composer-regression"
    manager.currentConversationId = id
    let response = String(repeating:
      "A long response with **formatted text**, a `code reference`, and several sentences that wrap over multiple lines. This is synthetic conversation data for the native layout regression.\n\n",
      count: 8)
    let messages = (0..<8).flatMap { index in
      [Message(id: "u-\(index)", conversation_id: id, role: "user",
        content: "Message \(index): inspect the long conversation", parts: nil, created_at: 0),
       Message(id: "a-\(index)", conversation_id: id, role: "assistant",
        content: response, parts: nil, created_at: 0)]
    }
    manager.onConversationLoaded?(
      Conversation(id: id, title: "Synthetic long conversation", created_at: 0, updated_at: 0), messages)
  }

  private func exerciseContentFitting() {
    validate("loaded-history")
    // NSWindow.maxSize alone does not constrain this AppKit entry point.
    controller?.chatWindow?.setContentSize(NSSize(width: 520, height: 12000))
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      self.validate("content-fitting")
      withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { self.controller?.toggleExpansion() }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { self.controller?.toggleExpansion() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
          self.validate("reexpanded")
          try? "Passed: actual chat view, delayed long-history load, native content fitting, animated collapse and expansion."
            .write(to: self.output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        }
      }
    }
  }

  private func validate(_ name: String) {
    guard let panel = controller?.chatWindow, let host = panel.contentView,
      let screen = panel.screen else { fatalError("Missing native window or display") }
    host.layoutSubtreeIfNeeded()
    let views = descendants(host)
    let renderedText = views.compactMap { $0 as? SelectableNSTextView }
    precondition(renderedText.count >= 8, "History must be rendered by the actual Markdown component")
    guard let editor = views.first(where: { $0 is ComposerNSTextView }) else { fatalError("Missing real composer") }
    let editorFrame = editor.convert(editor.bounds, to: host)
    let usable = screen.visibleFrame.insetBy(dx: 20, dy: 20)
    precondition(panel.frame.minY >= usable.minY - 1 && panel.frame.maxY <= usable.maxY + 1,
      "Expanded native window escaped the display")
    precondition(editorFrame.minY >= 0 && editorFrame.maxY <= host.bounds.height - 60,
      "Composer and its toolbar must remain inside the actual native viewport")
    let report = "panel=\(panel.frame)\nhost=\(host.bounds)\neditor=\(editorFrame)\nrenderedResponses=\(renderedText.count)"
    try? report.write(to: output.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
    if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try? bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent(name + ".png"))
    }
  }

  private func descendants(_ parent: NSView) -> [NSView] {
    parent.subviews.flatMap { [$0] + descendants($0) }
  }
}

@main struct FullComposerWindowRegression {
  @MainActor static func main() {
    let app = NSApplication.shared
    let delegate = ComposerRegressionDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
    withExtendedLifetime(delegate) {}
  }
}
