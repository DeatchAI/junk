import AppKit
import SwiftUI
@testable import Detach

/// Exercises the rebuilt production view without a runtime, account, or provider process.
@MainActor final class AttachmentComposerDelegate: NSObject, NSApplicationDelegate {
  private var controller: FloatingWindowController!
  private var manager: WebSocketManager!
  private let output = URL(fileURLWithPath: "/tmp/detach-attachment-composer-check")
  private var checks = 0
  private var didStart = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard !didStart else { return }
    didStart = true
    try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    UserDefaults.standard.setVolatileDomain([
      "appearance_preset": "Lazzy Dark", "appearance_mode": "Solid",
      "appearance_bg_color": "#151515", "appearance_fg_color": "#FFFFFF",
      "appearance_accent_color": "#FFFFFF", "ai_zero_data_retention": false,
      "composer.working-directory.path.v1": output.path,
    ], forName: UserDefaults.argumentDomain)
    ThemeManager.shared.refreshFromSettings()
    installMenu()

    let reference = makeImage(name: "Layout reference.png", label: "Detach", light: false)
    let draftImage = makeImage(name: "Draft sketch.png", label: "Draft", light: true)
    let codeURL = output.appendingPathComponent("Composer.swift")
    try! "struct Composer { /* synthetic fixture */ }".write(to: codeURL, atomically: true, encoding: .utf8)
    let code = AttachmentHelper.createAttachment(from: codeURL)!
    let invalidURL = output.appendingPathComponent("Unavailable preview.png")
    try! Data("invalid image".utf8).write(to: invalidURL)
    let invalid = AttachmentHelper.createAttachment(from: invalidURL)!
    runStateChecks(image: reference, code: code, invalid: invalid)
    if CommandLine.arguments.contains("--checks-only") {
      print("Passed \(checks) attachment, draft restoration, and persistence checks.")
      return
    }

    manager = WebSocketManager()
    manager.isConnecting = true
    manager.session?.invalidateAndCancel()
    manager.session = nil
    manager.isConnected = true
    manager.workflows = [SavedWorkflow(id: "review", title: "Review changes", prompt: "Review this diff.", kind: "workflow")]
    manager.addChatSentListener { [weak self] request in
      guard let self else { return }
      let data = try! JSONEncoder().encode(request)
      try! data.write(to: self.output.appendingPathComponent("submitted-request.json"))
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        self.manager.isStreaming = false
        self.manager.onChunk?("The revised message and its attachments were received by the isolated UI fixture.")
        self.manager.onComplete?("attachment-fixture", "a-fixture", "u-fixture", 0, 0)
        self.capture()
      }
    }
    controller = FloatingWindowController(wsManager: manager, selectedAgent: "codex", selectedModel: nil)
    controller.show(at: NSPoint(x: 520, y: 500), with: nil)
    let messages = [
      ChatMessage(userPrompt: "Polish the spacing using this reference and the composer file.", context: [],
        aiResponse: "The composer now keeps media and files together inside the input surface.",
        attachments: [reference, code]),
      ChatMessage(userPrompt: "Keep follow-ups compact and easy to revisit.", context: [],
        aiResponse: "Use the numbered strip to revisit a response. Open a message to inspect its files or revise it.")
    ]
    let notesURL = output.appendingPathComponent("notes.md")
    try! "# Sample layout notes".write(to: notesURL, atomically: true, encoding: .utf8)
    let notes = AttachmentHelper.createAttachment(from: notesURL)!
    let logo = makeImage(name: "Logo.png", label: "D", light: false)
    let text = "\(ComposerInlineToken.file(code).marker) Use this file to polish the layout. \(ComposerInlineToken.file(notes).marker)\nKeep it compact with @Browser."
    let view = FloatingChatView(controller: controller, wsManager: manager,
      onClose: { [weak self] in self?.controller.hide() },
      pendingAttachments: [draftImage, reference, logo, code, notes], pendingMCPAttachments: [.browser], inputText: text,
      messages: messages, lastCompletedResponse: messages[1].aiResponse!)
    controller.chatWindow?.contentView = FirstClickHostingView(rootView: view)
    manager.currentConversationId = "attachment-fixture"
    controller.chatWindow?.title = "Detach inline composer · isolated preview"
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      self.capture()
      try! "Passed \(self.checks) attachment, draft restoration, and persistence checks."
        .write(to: self.output.appendingPathComponent("checks.txt"), atomically: true, encoding: .utf8)
    }
  }

  private func runStateChecks(image: ChatAttachment, code: ChatAttachment, invalid: ChatAttachment) {
    expect(image.canPreviewMedia && !code.canPreviewMedia && !invalid.canPreviewMedia,
      "Only decodable media gets a thumbnail")
    let skill = SkillAttachment(id: "skill", name: "Review", path: "/tmp/SKILL.md", summary: nil)
    let draft = ComposerDraft(text: "Unfinished @Review", attachments: [code],
      contexts: [DetectedContent(type: .text, text: "Selected text", files: nil)], skills: [skill],
      browserTabs: [BrowserTabAttachment(id: 1, title: "Reference", url: "https://example.com")],
      mcpAttachments: [.browser], commands: [.defaults[0]])
    let first = ComposerDraft(text: "Earlier message", attachments: [image])
    var revision = ComposerRevisionSession()
    let loaded = revision.begin(messageNumber: 1, currentDraft: draft, original: first)
    expect(loaded.text == first.text && loaded.attachments == [image], "Load original text and files")
    _ = revision.begin(messageNumber: 2, currentDraft: loaded, original: ComposerDraft(text: "Another message"))
    let restored = revision.finish()!
    expect(restored.text == draft.text && restored.attachments == [code], "Switching revisions preserves the initial draft")
    expect(restored.contexts == draft.contexts && restored.skills == [skill]
      && restored.browserTabs == draft.browserTabs && restored.mcpAttachments == [.browser]
      && restored.commands == [.defaults[0]], "Restore all selected resources")
    expect(revision.messageNumber == nil && revision.finish() == nil, "Finish clears revision state")
    _ = revision.begin(messageNumber: 1, currentDraft: draft, original: first)
    expect(revision.finish()?.text == draft.text, "Submission restores the previous draft too")
    let duplicateDraft = ComposerDraft(attachments: [code],
      contexts: [DetectedContent(type: .files, text: nil, files: [code.fileRequest])])
    expect(duplicateDraft.files == [code.fileRequest], "Send each selected file once")
    let pasteA = AttachmentHelper.createAttachment(from: image.thumbnail)!
    let pasteB = AttachmentHelper.createAttachment(from: image.thumbnail)!
    expect(pasteA.fileRequest.path != pasteB.fileRequest.path, "Rapid pastes cannot overwrite earlier message files")

    let folder = output.appendingPathComponent("metadata")
    try? FileManager.default.removeItem(at: folder)
    let messages = [
      ChatMessage(userMessageId: "u1", userPrompt: "Repeated prompt", context: nil,
        aiResponse: "one", attachments: [image]),
      ChatMessage(userMessageId: "u2", userPrompt: "Repeated prompt", context: nil,
        aiResponse: "two", attachments: [code])]
    SentMessageAttachmentStore.save(messages, conversationID: "local-check", directory: folder)
    let history = messages.map { ChatMessage(userMessageId: $0.userMessageId,
      userPrompt: $0.userPrompt, context: nil, aiResponse: $0.aiResponse) }
    let reloaded = SentMessageAttachmentStore.restore(history, conversationID: "local-check", directory: folder)
    expect(reloaded[0].attachments.first?.fileRequest == image.fileRequest
      && reloaded[1].attachments.first?.fileRequest == code.fileRequest, "Files stay with their own message after reload")
    let page = SentMessageAttachmentStore.restore([history[1]], conversationID: "local-check", directory: folder)
    expect(page.first?.attachments.first?.fileRequest == code.fileRequest, "Message IDs survive paginated history")
    let url = try! FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)[0]
    let metadata = try! String(contentsOf: url, encoding: .utf8)
    expect(!metadata.contains("Repeated prompt") && !metadata.contains("synthetic fixture"),
      "Attachment index excludes prompts and file contents")
    let permissions = try! FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber
    expect(permissions.intValue == 0o600, "Attachment index is private to this user")
    let deletedURL = output.appendingPathComponent("Missing.swift")
    let missing = ChatAttachment(thumbnail: NSImage(), fileRequest: FileAttachmentRequest(path: deletedURL.path,
      mimeType: "text/plain"), fileName: "Missing.swift")
    SentMessageAttachmentStore.save([ChatMessage(userPrompt: "Missing", context: nil, aiResponse: "",
      attachments: [missing])], conversationID: "missing", directory: folder)
    let missingReload = SentMessageAttachmentStore.restore([ChatMessage(userPrompt: "Missing", context: nil,
      aiResponse: "")], conversationID: "missing", directory: folder)
    expect(missingReload[0].attachments.isEmpty, "Missing files do not leave attachment pills")
    let repeated = [
      ChatMessage(userPrompt: "Same words", context: nil, aiResponse: "", attachments: [image]),
      ChatMessage(userPrompt: "Same words", context: nil, aiResponse: "")]
    SentMessageAttachmentStore.save(repeated, conversationID: "ambiguous", directory: folder)
    let repeatedHistory = repeated.map { ChatMessage(userPrompt: $0.userPrompt, context: nil, aiResponse: "") }
    let full = SentMessageAttachmentStore.restore(repeatedHistory, conversationID: "ambiguous", directory: folder)
    expect(full[0].attachments.count == 1 && full[1].attachments.isEmpty,
      "Repeated prompts without files stay empty")
    let partial = SentMessageAttachmentStore.restore([repeatedHistory[1]], conversationID: "ambiguous", directory: folder)
    expect(partial[0].attachments.isEmpty, "Never guess which repeated prompt belongs to a partial page")
    let otherChat = SentMessageAttachmentStore.restore(history, conversationID: "other", directory: folder)
    expect(otherChat.allSatisfy { $0.attachments.isEmpty }, "Attachment metadata stays in its own conversation")
    SentMessageAttachmentStore.save([ChatMessage(userPrompt: "Native image prompt", context: nil,
      aiResponse: "", attachments: [image])], conversationID: "native-image", directory: folder)
    let nativeImage = SentMessageAttachmentStore.restore([ChatMessage(
      userPrompt: "Native image prompt\n[Attachment in original session; file not copied]", context: nil,
      aiResponse: "")], conversationID: "native-image", directory: folder)
    expect(nativeImage[0].attachments.count == 1, "Native image markers do not lose sent attachment references")
  }

  private func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
    checks += 1
  }

  private func makeImage(name: String, label: String, light: Bool) -> ChatAttachment {
    let image = NSImage(size: NSSize(width: 240, height: 160))
    image.lockFocus()
    (light ? NSColor(white: 0.86, alpha: 1) : NSColor(white: 0.12, alpha: 1)).setFill()
    NSRect(x: 0, y: 0, width: 240, height: 160).fill()
    (light ? NSColor.white : NSColor(white: 0.3, alpha: 1)).setFill()
    NSBezierPath(roundedRect: NSRect(x: 18, y: 20, width: 204, height: 120), xRadius: 12, yRadius: 12).fill()
    (label as NSString).draw(at: NSPoint(x: 36, y: 84), withAttributes: [
      .font: NSFont.systemFont(ofSize: 24), .foregroundColor: light ? NSColor.black : NSColor.white])
    image.unlockFocus()
    let url = output.appendingPathComponent(name)
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
    return AttachmentHelper.createAttachment(from: url)!
  }

  private func installMenu() {
    let menu = NSMenu(), submenu = NSMenu(), item = NSMenuItem()
    for (title, action, key) in [("Capture", #selector(capture), "s"),
      ("Light appearance", #selector(lightAppearance), "l"),
      ("Dark appearance", #selector(darkAppearance), "d"),
      ("Many attachments", #selector(manyAttachments), "m")] {
      let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
      entry.target = self; submenu.addItem(entry)
    }
    submenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    item.submenu = submenu; menu.addItem(item); NSApp.mainMenu = menu
  }

  @objc private func capture() {
    guard let host = controller?.chatWindow?.contentView else { return }
    host.layoutSubtreeIfNeeded()
    if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try? bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("composer.png"))
    }
  }

  @objc private func lightAppearance() { setAppearance(light: true) }
  @objc private func darkAppearance() { setAppearance(light: false) }
  private func setAppearance(light: Bool) {
    ThemeManager.shared.preset = light ? .lazzywhite : .lazzydark
    ThemeManager.shared.backgroundColorHex = light ? "#FFFFFF" : "#151515"
    ThemeManager.shared.foregroundColorHex = light ? "#151515" : "#FFFFFF"
  }

  @objc private func manyAttachments() {
    let files = (0..<30).map { index -> FileAttachmentRequest in
      let url = output.appendingPathComponent("Component-\(index).swift")
      try! "// Synthetic file".write(to: url, atomically: true, encoding: .utf8)
      return FileAttachmentRequest(path: url.path, mimeType: "text/plain")
    }
    controller.detectedContent = DetectedContent(type: .files, text: nil, files: files)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct AttachmentComposerRegression {
  @MainActor static func main() {
    let app = NSApplication.shared
    let delegate = AttachmentComposerDelegate()
    app.delegate = delegate
    if CommandLine.arguments.contains("--checks-only") {
      delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
      return
    }
    app.setActivationPolicy(.regular)
    delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    app.finishLaunching()
    app.run()
    withExtendedLifetime(delegate) {}
  }
}
