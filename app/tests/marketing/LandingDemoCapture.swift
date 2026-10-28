import AppKit
import Foundation
import SwiftUI
@testable import Detach

/// Runs the compiled production views with fictional content and no agent/runtime connection.
@MainActor final class LandingCaptureDelegate: NSObject, NSApplicationDelegate {
  private var controller: FloatingWindowController!
  private var manager: WebSocketManager!
  private let history = HistoryWindowController()
  private let runs = DetachedRunStore()
  private let controls = DetachedRunControls()
  private lazy var island = ActivityIslandWindowController(runStore: runs, controls: controls)
  private let directory = URL(fileURLWithPath: "/tmp/detach-landing-native")
  private var image: ChatAttachment!
  private var code: ChatAttachment!

  func applicationDidFinishLaunching(_ notification: Notification) {
    try! Foundation.FileManager().createDirectory(at: directory, withIntermediateDirectories: true)
    UserDefaults.standard.setVolatileDomain([
      "appearance_preset": "Lazzy Dark", "appearance_mode": "Solid",
      "appearance_accent_color": "#FFFFFF", "ai_zero_data_retention": true,
      "composer.working-directory.path.v1": directory.appendingPathComponent("acme").path,
    ], forName: UserDefaults.argumentDomain)
    ThemeManager.shared.refreshFromSettings()
    for name in ["acme", "portfolio", "side-project"] {
      let folder = directory.appendingPathComponent(name)
      try! Foundation.FileManager().createDirectory(at: folder, withIntermediateDirectories: true)
      ComposerProjectLibrary.shared.remember(folder)
    }
    makeAttachments()
    manager = WebSocketManager(); manager.isConnecting = true
    manager.session?.invalidateAndCancel(); manager.session = nil; manager.isConnected = true
    manager.agentCapabilities = [
      AgentCapability(id: "codex", displayName: "Codex", installed: true, executablePath: nil, authHint: nil,
        models: [AgentModelCapability(id: "gpt-6.1-sol", displayName: "GPT-6.1 Sol",
          reasoningEfforts: ["low", "medium", "high"], defaultReasoningEffort: "medium", reasoningLabel: "Effort")],
        defaultModel: "gpt-6.1-sol"),
      AgentCapability(id: "claude", displayName: "Claude", installed: true, executablePath: nil, authHint: nil,
        models: [AgentModelCapability(id: "sonnet", displayName: "Sonnet", reasoningEfforts: nil,
          defaultReasoningEffort: nil, reasoningLabel: nil)], defaultModel: "sonnet"),
    ]
    history.wsManager = manager
    manager.conversations = ["Polish the landing page", "Review checkout flow", "Add a little breathing room",
      "Build the project page", "Simplify navigation"].enumerated().map { index, title in
        Conversation(id: "demo-\(index)", title: title, created_at: 0, updated_at: 0,
          provider: index == 1 ? "claude" : "codex", workspacePath: directory.appendingPathComponent(index < 3 ? "acme" : "portfolio").path,
          origin: "provider", canResume: true)
      }
    controller = FloatingWindowController(wsManager: manager, selectedAgent: "codex", selectedModel: "gpt-6.1-sol")
    installMenu(); empty()
    NSApp.activate(ignoringOtherApps: true)
  }

  private func present(text: String = "", attachments: [ChatAttachment] = [], messages: [ChatMessage] = []) {
    history.hide(); island.hide()
    controller.show(at: NSPoint(x: 520, y: 540), with: nil)
    let response = messages.last?.aiResponse ?? ""
    controller.chatWindow?.contentView = FirstClickHostingView(rootView:
      FloatingChatView(controller: controller, wsManager: manager, onClose: { self.controller.hide() },
        pendingAttachments: attachments, inputText: text, messages: messages, lastCompletedResponse: response))
    controller.chatWindow?.title = "Detach Native Demo"
    controller.chatWindow?.makeKeyAndOrderFront(nil)
  }

  @objc private func empty() { present() }
  @objc private func attachments() { present(text: "Give this page a little more breathing room.", attachments: [image, code]) }
  @objc private func conversation() {
    let prompts = ["Polish the landing page. Keep the typography quiet and give the layout more breathing room.",
      "Use this reference for the project cards. Keep the existing spacing system."]
    let answers = ["I’ll check the current layout and refine the spacing, type, and project cards.",
      "Updated the project cards with more room around the images, quieter labels, and consistent spacing. The layout stays balanced on smaller screens."]
    let messages = prompts.enumerated().map { index, prompt in
      ChatMessage(userMessageId: "u-\(index)", userPrompt: prompt, context: nil, aiResponse: answers[index],
        attachments: index == 1 ? [image, code] : [], branchReference:
          ConversationMessageReference(messageId: "u-\(index)", promptHash: ConversationPrompt.fingerprint(prompt), canBranch: true))
    }
    present(messages: messages)
  }
  @objc private func activity() { controller.hide(); history.hide(); runs.showDebugScenario(.multiAgent); island.showDebugPreview() }
  @objc private func approval() { controller.hide(); history.hide(); runs.showDebugScenario(.approval); island.showApproval() }
  @objc private func showHistory() { manager.isConnected = false; history.show() }
  @objc private func light() { ThemeManager.shared.preset = .lazzywhite }
  @objc private func dark() { ThemeManager.shared.preset = .lazzydark }
  @objc private func capture() {
    for (index, window) in NSApp.windows.filter({ $0.isVisible && $0.contentView != nil }).enumerated() {
      let host = window.contentView!; host.layoutSubtreeIfNeeded()
      guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try? bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("native-\(index).png"))
    }
  }

  private func makeAttachments() {
    let artwork = NSImage(size: NSSize(width: 480, height: 320))
    artwork.lockFocus(); NSColor(white: 0.91, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 480, height: 320).fill()
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 38, weight: .regular), .foregroundColor: NSColor.black]
    ("Acme.\nMake room for\nwhat matters." as NSString).draw(at: NSPoint(x: 34, y: 106), withAttributes: attributes)
    NSColor.black.setFill(); NSBezierPath(roundedRect: NSRect(x: 34, y: 38, width: 110, height: 5), xRadius: 2, yRadius: 2).fill()
    artwork.unlockFocus()
    let url = directory.appendingPathComponent("reference.png")
    let bitmap = NSBitmapImageRep(data: artwork.tiffRepresentation!)!
    try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
    image = AttachmentHelper.createAttachment(from: url)!
    let codeURL = directory.appendingPathComponent("page.tsx")
    try! "export default function Page() { return <main>Acme</main>; }".write(to: codeURL, atomically: true, encoding: .utf8)
    code = AttachmentHelper.createAttachment(from: codeURL)!
  }

  private func installMenu() {
    let bar = NSMenu(); let item = NSMenuItem(); let menu = NSMenu()
    for (name, action, key) in [
      ("Empty composer", #selector(empty), "1"), ("Attachments", #selector(attachments), "2"),
      ("Conversation", #selector(conversation), "3"), ("Activity island", #selector(activity), "4"),
      ("Approval", #selector(approval), "5"), ("History", #selector(showHistory), "6"),
      ("Light", #selector(light), "l"), ("Dark", #selector(dark), "d"), ("Save native render", #selector(capture), "s")] {
      let entry = NSMenuItem(title: name, action: action, keyEquivalent: key); entry.target = self; menu.addItem(entry)
    }
    menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    item.submenu = menu; bar.addItem(item); NSApp.mainMenu = bar
  }
}

@main struct LandingDemoCapture {
  @MainActor static func main() {
    let app = NSApplication.shared; let delegate = LandingCaptureDelegate(); app.delegate = delegate
    app.setActivationPolicy(.regular); app.finishLaunching(); app.run(); withExtendedLifetime(delegate) {}
  }
}
