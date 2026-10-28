import AppKit
import SwiftUI
@testable import Detach

/// The exact Debug module with isolated preferences, sample data and no provider process.
@MainActor final class ThinInterfaceDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow?
  private var manager: WebSocketManager?

  func applicationDidFinishLaunching(_ notification: Notification) {
    UserDefaults.standard.setVolatileDomain([
      "appearance_preset": "lazzydark", "appearance_mode": "Solid",
      "appearance_bg_color": "#000000", "appearance_fg_color": "#FFFFFF",
    ], forName: UserDefaults.argumentDomain)
    ThemeManager.shared.refreshFromSettings()
    DetachSettings.setPermissionMode(.native, for: "codex")
    let manager = WebSocketManager()
    manager.isConnecting = true
    manager.session?.invalidateAndCancel()
    manager.session = nil
    manager.lastContextSummary = ChatContextSummary(runId: "sample", userCharacters: 100,
      instructionCharacters: 0, attachmentCharacters: 0, fileCount: 0, toolServerCount: 1, permissionMode: "native")
    manager.workflows = [SavedWorkflow(id: "sample", title: "Review changes", prompt: "Review the diff.", kind: "workflow")]
    self.manager = manager
    let controller = FloatingWindowController(wsManager: manager, selectedAgent: "codex", selectedModel: nil)
    let root = VStack(spacing: 0) {
      FloatingChatToolbarView(fastMode: .constant(false), inputText: .constant(""), selectedMode: .constant("Codex"),
        canSend: false, wsManager: manager, controller: controller,
        onAttach: {}, onHistory: {}, onNewChat: {}, onStartIndexing: {}, onVoiceInput: {}, onSend: {})
        .padding(16)
      Divider()
      SettingsView(wsManager: manager)
    }
    let window = NSWindow(contentRect: NSRect(x: 130, y: 100, width: 940, height: 750),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Detach native interface check · isolated sample data"
    window.contentView = NSHostingView(rootView: root)
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    self.window = window
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct ThinInterfaceRegression {
  @MainActor static func main() {
    let app = NSApplication.shared
    let delegate = ThinInterfaceDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
    withExtendedLifetime(delegate) {}
  }
}
