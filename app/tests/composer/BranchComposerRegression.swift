import AppKit
import Combine
import SwiftUI
@testable import Detach

/// The production view linked from the Debug app, with isolated native histories and no model calls.
@MainActor final class BranchPreviewDelegate: NSObject, NSApplicationDelegate {
  private var controller: FloatingWindowController!
  private var manager: WebSocketManager!
  private var cancellable: AnyCancellable?
  private var history: [String: [Message]] = [:]
  private var family: [ConversationBranch] = []
  private let output = URL(fileURLWithPath: "/tmp/detach-branch-preview")
  private var didStart = false
  private var failNextBranch = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard !didStart else { return }; didStart = true
    try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    UserDefaults.standard.setVolatileDomain([
      "appearance_preset": "Lazzy Dark", "appearance_mode": "Solid",
      "appearance_accent_color": "#FFFFFF", "ai_zero_data_retention": false,
      "composer.working-directory.path.v1": output.path,
    ], forName: UserDefaults.argumentDomain)
    ThemeManager.shared.refreshFromSettings()
    installMenu()
    runDraftChecks()

    let image = makeImage()
    let codeURL = output.appendingPathComponent("Composer.swift")
    try! "struct Composer {}".write(to: codeURL, atomically: true, encoding: .utf8)
    let code = AttachmentHelper.createAttachment(from: codeURL)!
    let prompts = ["Use this **layout reference**.\n\n- Keep the composer compact.\n- Give the editor room.",
      "## Spacing\n\n" + String(repeating: "Keep controls reachable and render attachments clearly.\n\n", count: 35),
      "Keep this later message on the original branch."]
    let messages = prompts.enumerated().map { index, text in
      ChatMessage(userMessageId: "parent-u\(index)", userPrompt: text, context: [],
        aiResponse: "Response \(index + 1): the original conversation stays available.",
        attachments: index == 1 ? [image, code] : [], branchReference: reference("parent-u\(index)", text))
    }
    family = [ConversationBranch(id: "branch-parent", parentId: nil, messageNumber: nil, title: "Original")]
    history["branch-parent"] = nativeMessages(messages, id: "branch-parent")
    SentMessageAttachmentStore.save(messages, conversationID: "branch-parent")
    manager = WebSocketManager()
    manager.isConnecting = true
    manager.session?.invalidateAndCancel(); manager.session = nil
    manager.isConnected = true
    manager.currentConversationId = "branch-parent"
    manager.currentConversation = conversation("branch-parent")
    manager.conversationBranchState = state("branch-parent")
    manager.addChatSentListener { [weak self] request in self?.receive(request) }
    cancellable = manager.$currentConversationId.sink { [weak self] id in
      guard let self, let id else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        guard self.manager.currentConversationId == id, !self.manager.isStreaming,
          let messages = self.history[id] else { return }
        self.manager.onConversationLoaded?(self.conversation(id), messages)
        self.manager.conversationBranchState = self.state(id)
      }
    }
    controller = FloatingWindowController(wsManager: manager, selectedAgent: "codex", selectedModel: nil)
    controller.show(at: NSPoint(x: 500, y: 500), with: nil)
    let view = FloatingChatView(controller: controller, wsManager: manager,
      onClose: { [weak self] in self?.controller.hide() },
      pendingAttachments: [code], inputText: "My unfinished draft \(ComposerInlineToken.file(code).marker)",
      messages: messages, lastCompletedResponse: messages.last!.aiResponse!)
    controller.chatWindow?.contentView = FirstClickHostingView(rootView: view)
    controller.chatWindow?.title = "Detach Branch Preview"
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.capture() }
  }

  private func reference(_ id: String, _ text: String) -> ConversationMessageReference {
    ConversationMessageReference(messageId: id, promptHash: ConversationPrompt.fingerprint(text), canBranch: true)
  }

  private func nativeMessages(_ messages: [ChatMessage], id: String) -> [Message] {
    messages.enumerated().flatMap { index, message in [
      Message(id: message.userMessageId ?? "\(id)-u\(index)", conversation_id: id, role: "user",
        content: message.userPrompt, parts: nil, created_at: 0),
      Message(id: "\(id)-a\(index)", conversation_id: id, role: "assistant",
        content: message.aiResponse ?? "", parts: nil, created_at: 0),
    ] }
  }

  private func conversation(_ id: String) -> Conversation {
    Conversation(id: id, title: "Native branch fixture", created_at: 0, updated_at: 0,
      provider: "codex", workspacePath: output.path, origin: "provider", canResume: true)
  }

  private func state(_ id: String) -> ConversationBranchState {
    ConversationBranchState(type: "conversation_branch_state", conversationId: id, branches: family,
      messages: (history[id] ?? []).filter(\.isUser).map { reference($0.id, $0.content) })
  }

  private func receive(_ request: ChatRequest) {
    try! JSONEncoder().encode(request).write(to: output.appendingPathComponent("request.json"))
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      if self.failNextBranch {
        self.failNextBranch = false; self.manager.isStreaming = false
        self.manager.onError?("The isolated branch creation failed. Your edit is still in the composer.")
        return
      }
      let parent = self.manager.currentConversationId!
      let old = self.history[parent]!
      let selected = request.branchFrom.flatMap { target in old.firstIndex { $0.id == target.messageId } }
      let id = request.branchFrom == nil ? parent : "branch-child-\(self.family.count)"
      if let selected {
        precondition(ConversationPrompt.fingerprint(old[selected].content) == request.branchFrom!.promptHash)
        self.history[id] = Array(old.prefix(selected))
        self.family.append(ConversationBranch(id: id, parentId: parent,
          messageNumber: old.prefix(selected + 1).filter(\.isUser).count, title: "Edited path"))
      }
      let answer = "The edited path has its own response. The original later messages remain on the other branch."
      self.history[id, default: []] += [
        Message(id: "\(id)-edited-user", conversation_id: id, role: "user", content: request.displayText ?? request.text, parts: nil, created_at: 0),
        Message(id: "\(id)-edited-assistant", conversation_id: id, role: "assistant", content: answer, parts: nil, created_at: 0),
      ]
      self.manager.currentConversationId = id
      self.manager.currentConversation = self.conversation(id)
      self.manager.onProviderSession?(self.conversation(id))
      self.manager.onChunk?(answer)
      self.manager.isStreaming = false
      self.manager.onComplete?(id, "\(id)-edited-assistant", "\(id)-edited-user", 0, 0)
      self.manager.conversationBranchState = self.state(id)
      self.capture()
    }
  }

  private func runDraftChecks() {
    let directory = output.appendingPathComponent("draft-check")
    let url = output.appendingPathComponent("draft-file.txt")
    try! "Sample".write(to: url, atomically: true, encoding: .utf8)
    let file = AttachmentHelper.createAttachment(from: url)!
    let text = "Unfinished \(ComposerInlineToken.file(file).marker)"
    let draft = ComposerDraft(text: text, attachments: [file], mcpAttachments: [.browser])
    ComposerBranchDraftStore.save(draft, conversationID: "one", selectedMessage: 2, directory: directory)
    ComposerBranchDraftStore.save(ComposerDraft(text: "Other branch"), conversationID: "two", selectedMessage: nil, directory: directory)
    let restored = ComposerBranchDraftStore.load("one", directory: directory)!
    precondition(restored.draft.text == text && restored.draft.attachments[0].id == file.id)
    precondition(restored.draft.mcpAttachments == [.browser] && restored.selectedMessage == 2)
    precondition(ComposerBranchDraftStore.load("two", directory: directory)!.draft.text == "Other branch")
    precondition(!restored.draft.resolvedText.contains("[[file:"))
    try! "Passed: per-branch drafts, selected response, resource selections, and stable inline attachment identities."
      .write(to: output.appendingPathComponent("checks.txt"), atomically: true, encoding: .utf8)
  }

  private func makeImage() -> ChatAttachment {
    let image = NSImage(size: NSSize(width: 240, height: 160))
    image.lockFocus(); NSColor(white: 0.22, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 240, height: 160).fill()
    ("Reference" as NSString).draw(at: NSPoint(x: 30, y: 70), withAttributes: [
      .font: NSFont.systemFont(ofSize: 25), .foregroundColor: NSColor.white])
    image.unlockFocus()
    let url = output.appendingPathComponent("Reference.png")
    try! NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: url)
    return AttachmentHelper.createAttachment(from: url)!
  }

  private func installMenu() {
    let bar = NSMenu(), menu = NSMenu(), item = NSMenuItem()
    for (title, action, key) in [("Capture", #selector(capture), "s"),
      ("Fail next branch", #selector(failBranch), "f"), ("Light appearance", #selector(light), "l"),
      ("Dark appearance", #selector(dark), "d")] {
      let entry = NSMenuItem(title: title, action: action, keyEquivalent: key); entry.target = self; menu.addItem(entry)
    }
    menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    item.submenu = menu; bar.addItem(item); NSApp.mainMenu = bar
  }
  @objc private func failBranch() { failNextBranch = true }
  @objc private func light() { ThemeManager.shared.preset = .lazzywhite }
  @objc private func dark() { ThemeManager.shared.preset = .lazzydark }
  @objc private func capture() {
    guard let host = controller?.chatWindow?.contentView, let panel = controller.chatWindow else { return }
    host.layoutSubtreeIfNeeded()
    let usable = panel.screen!.visibleFrame
    precondition(panel.frame.minY >= usable.minY - 1 && panel.frame.maxY <= usable.maxY + 1)
    if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try? bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("composer.png"))
    }
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct BranchComposerRegression {
  @MainActor static func main() {
    let app = NSApplication.shared
    let delegate = BranchPreviewDelegate(); app.delegate = delegate
    app.setActivationPolicy(.regular); app.finishLaunching(); app.run()
    withExtendedLifetime(delegate) {}
  }
}
