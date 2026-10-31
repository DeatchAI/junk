import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

extension FloatingChatView {
  // MARK: - Shortcut Monitor

  func setupShortcutMonitor() {
    guard shortcutMonitor == nil else { return }
    shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      guard controller.isVisible else { return event }

      guard controller.isFrontmost else { return event }
      guard isInputFocused else { return event }
      guard !isInlineAttachmentMenuActive else { return event }
      guard !isInlineCommandMenuActive else { return event }
      if let textView = event.window?.firstResponder as? NSTextView,
        textView.hasMarkedText()
      {
        return event
      }

      let modifiers = event.modifierFlags
      var carbonModifiers: Int = 0
      if modifiers.contains(.shift) { carbonModifiers |= shiftKey }
      if modifiers.contains(.control) { carbonModifiers |= controlKey }
      if modifiers.contains(.option) { carbonModifiers |= optionKey }
      if modifiers.contains(.command) { carbonModifiers |= cmdKey }

      let keyCode = Int(event.keyCode)

      // Check for Submit shortcut
      let submit = ShortcutSettings.chatSubmit
      if keyCode == submit.keyCode && carbonModifiers == submit.modifiers {
        sendMessage()
        return nil  // Consume event
      }

      // Check for New Chat shortcut
      let newChat = ShortcutSettings.chatNewChat
      if keyCode == newChat.keyCode && carbonModifiers == newChat.modifiers {
        startNewChat()
        return nil  // Consume event
      }

      // Escape follows normal floating-panel behavior: dismiss this focused
      // composer after any detached menu has had a chance to consume Escape.
      // The agent itself keeps running and remains available from the notch.
      if keyCode == kVK_Escape && carbonModifiers == 0 {
        if revisionSession.messageNumber != nil { cancelMessageRevision() }
        else { onClose() }
        return nil
      }

      return event
    }
  }

#if DEBUG
  func debugDemoPrompt(for event: NSEvent, functionIsDown: Bool) -> String? {
    guard functionIsDown else { return nil }

    let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
    guard event.modifierFlags.intersection(disallowedModifiers).isEmpty else { return nil }

    let prompts = DebugDemoCatalog.chatPrompts
    let keyCodes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
                    kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8,
                    kVK_ANSI_9, kVK_ANSI_0]
    guard let promptIndex = keyCodes.firstIndex(of: Int(event.keyCode)),
      prompts.indices.contains(promptIndex) else { return nil }
    return prompts[promptIndex]
  }

  func startDebugDemoTyping(_ prompt: String) {
    debugDemoTypingTask?.cancel()
    inputText = ""
    isInputFocused = true
    print("🧪 Debug demo menu flow and prompt typing started")

    guard let scenario = DebugDemoCatalog.scenario(for: prompt) else {
      typeDebugDemoPrompt(prompt)
      return
    }

    debugDemoTypingTask = DebugDemoTyping.start(
      scenario: scenario,
      setMenuStep: { debugMenuStep = $0 },
      appendCharacter: { inputText.append($0) }
    )
  }

  func typeDebugDemoPrompt(_ prompt: String) {
    debugDemoTypingTask = Task { @MainActor in
      for character in prompt {
        guard !Task.isCancelled else { return }
        inputText.append(character)
        try? await Task.sleep(for: .milliseconds(18))
      }
    }
  }

#endif

  func removeShortcutMonitor() {
    if let shortcutMonitor {
      NSEvent.removeMonitor(shortcutMonitor)
      self.shortcutMonitor = nil
    }
  }

  /// Attach image or file representations from the clipboard. Returning false
  /// lets NSTextView continue with its normal text paste behavior.
  func handlePaste() -> Bool {
    let attachments = AttachmentHelper.getAttachmentsFromClipboard()
    guard !attachments.isEmpty else { return false }
    guard !workingDirectoryStore.isRemote else {
      errorMessage = "Local file attachments are not available for remote runs."
      return true
    }

    for attachment in attachments {
      addPendingAttachment(attachment)
    }
    print("📎 \(attachments.count) attachment(s) pasted from clipboard")
    return true
  }

  func appendVoiceTranscription(_ transcript: String) {
    let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return }

    if inputText.isEmpty {
      inputText = cleaned
    } else if inputText.last?.isWhitespace == true {
      inputText += cleaned
    } else {
      inputText += " \(cleaned)"
    }
    isInputFocused = true
  }

  func addContextIfNeeded(_ content: DetectedContent) {
    for file in content.files ?? [] {
      if let attachment = AttachmentHelper.createAttachment(from: URL(fileURLWithPath: file.path)) {
        addPendingAttachment(attachment)
      }
    }
    if let text = content.text, !text.isEmpty {
      let context = DetectedContent(type: .text, text: text, files: nil)
      if !sessionContexts.contains(context) {
        sessionContexts.append(context)
        inputText = ComposerInlineToken.addingMissingFiles(to: inputText, attachments: pendingAttachments, contexts: sessionContexts)
      }
    }
  }

  var hasConversationNavigation: Bool {
    !messages.isEmpty
  }

  var canSendMessage: Bool {
    guard wsManager.isConnected, !wsManager.isStreaming, !wsManager.isStoppingRun else { return false }
    guard !conversationStore.isAttaching else { return false }
    guard wsManager.currentConversation?.isProviderHistory != true || wsManager.currentConversation?.canResume != false else { return false }
    return !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !pendingAttachments.isEmpty || !pendingSkills.isEmpty || !pendingBrowserTabs.isEmpty
      || !pendingMCPAttachments.isEmpty
      || !pendingCommandAliases.isEmpty
  }

  var availableComposerMCPAttachments: [ComposerMCPAttachment] {
    let connectedServers = wsManager.mcpServers.filter { $0.enabled && ($0.status?.connected ?? true) }
    let composioServer = connectedServers.first { $0.name.localizedCaseInsensitiveContains("Composio") }
    let connectedComposioIntegrations = wsManager.composioIntegrations
      .filter { $0.connected && !$0.name.localizedCaseInsensitiveContains("Composio") }

    var attachments = connectedServers
      .filter { server in server.id != composioServer?.id }
      .map(serverAttachment)

    if let composioServer {
      if connectedComposioIntegrations.isEmpty {
        attachments.append(serverAttachment(composioServer))
      } else {
        attachments.append(
          contentsOf: connectedComposioIntegrations.map { integration in
            ComposerMCPAttachment(
              id: "composio:\(integration.id)",
              serverId: composioServer.id,
              name: integration.name,
              systemImage: composioSystemImage(for: integration),
              detail: "Use \(integration.name) through Composio"
            )
          }
        )
      }
    }

    return attachments
  }

  func serverAttachment(_ server: MCPServer) -> ComposerMCPAttachment {
    ComposerMCPAttachment(
      id: server.id,
      name: server.name,
      systemImage: "server.rack",
      detail: server.status?.tools?.isEmpty == false
        ? "\(server.status?.tools?.count ?? 0) tools"
        : "\(server.transport.uppercased()) MCP server"
    )
  }

  func composioSystemImage(for integration: ComposioIntegration) -> String {
    switch integration.id.lowercased() {
    case "gmail":
      return "envelope"
    case "github":
      return "chevron.left.forwardslash.chevron.right"
    case "slack":
      return "number"
    case "notion":
      return "doc.text"
    case "googlecalendar", "google-calendar", "calendar":
      return "calendar"
    default:
      return "puzzlepiece.extension"
    }
  }

  func refreshComposerResources() {
    wsManager.listMCPServers()
    wsManager.listComposioIntegrations(limit: 100)
    wsManager.listWorkflows()
    skillsDirectory.refreshInstalledSkills()
  }

  func addSkillAttachment(_ skill: SkillAttachment) {
    guard !pendingSkills.contains(skill) else { return }
    pendingSkills.append(skill)
  }

  func addBrowserTabAttachment(_ tab: BrowserTab) {
    guard !workingDirectoryStore.isRemote else { return }
    let attachment = tab.attachment
    guard !pendingBrowserTabs.contains(where: { $0.id == attachment.id }) else { return }
    pendingBrowserTabs.append(attachment)
  }

  func removeBrowserTabAttachment(_ tab: BrowserTabAttachment) {
    pendingBrowserTabs.removeAll { $0.id == tab.id }
  }

  func addFileAttachment(_ url: URL) {
    guard !workingDirectoryStore.isRemote else {
      errorMessage = "Local file attachments are not available for remote runs."
      return
    }
    guard let attachment = AttachmentHelper.createAttachment(from: url) else { return }
    addPendingAttachment(attachment)
  }

  // MARK: - Window-level media drop

  /// Accepts media dropped anywhere in the floating surface. The text editor
  /// still handles local file URLs itself, while this path covers drops on the
  /// response/header area, raw browser image data, and browser web URLs.
  func handleMediaDrop(_ providers: [NSItemProvider]) -> Bool {
    guard !workingDirectoryStore.isRemote else {
      errorMessage = "Local file attachments are not available for remote runs."
      return false
    }
    guard !providers.isEmpty else { return false }
    for provider in providers {
      loadMediaDrop(provider)
    }
    return true
  }

  func loadMediaDrop(_ provider: NSItemProvider) {
    let imageType = provider.registeredTypeIdentifiers.first {
      UTType($0)?.conforms(to: .image) == true
    }

    if let imageType {
      provider.loadDataRepresentation(forTypeIdentifier: imageType) { data, _ in
        if let data, let image = NSImage(data: data),
          let attachment = AttachmentHelper.createAttachment(from: image)
        {
          Task { @MainActor in
            addPendingAttachment(attachment)
          }
          return
        }
        loadDroppedURL(provider)
      }
      return
    }

    loadDroppedURL(provider)
  }

  func loadDroppedURL(_ provider: NSItemProvider) {
    guard let urlType = provider.registeredTypeIdentifiers.first(where: {
      guard let type = UTType($0) else { return false }
      return type.conforms(to: .fileURL) || type.conforms(to: .url)
    }) else { return }

    provider.loadItem(forTypeIdentifier: urlType, options: nil) { item, _ in
      let url: URL?
      if let data = item as? Data {
        url = URL(dataRepresentation: data, relativeTo: nil)
      } else if let nsURL = item as? NSURL {
        url = nsURL as URL
      } else if let string = item as? String {
        url = URL(string: string)
      } else {
        url = nil
      }

      guard let url else { return }
      if url.isFileURL {
        Task { @MainActor in
          addDroppedFile(url)
        }
      } else {
        Task {
          let attachment = await AttachmentHelper.createAttachment(fromRemoteURL: url)
          guard let attachment else { return }
          await MainActor.run {
            addPendingAttachment(attachment)
          }
        }
      }
    }
  }

  func addDroppedFile(_ url: URL) {
    guard let attachment = AttachmentHelper.createAttachment(from: url), attachment.isMedia else {
      return
    }
    addPendingAttachment(attachment)
  }

  func addPendingAttachment(_ attachment: ChatAttachment) {
    guard !workingDirectoryStore.isRemote else {
      errorMessage = "Local file attachments are not available for remote runs."
      return
    }
    if let id = attachment.conversationID, pendingAttachments.contains(where: { $0.conversationID == id }) { return }
    guard !pendingAttachments.contains(where: { $0.fileRequest.path == attachment.fileRequest.path }) else {
      return
    }

    pendingAttachments.append(attachment)
    inputText = ComposerInlineToken.addingMissingFiles(to: inputText, attachments: pendingAttachments, contexts: sessionContexts)
    isInputFocused = true
  }

  func addMCPAttachment(_ attachment: ComposerMCPAttachment) {
    guard !pendingMCPAttachments.contains(attachment) else { return }
    pendingMCPAttachments.append(attachment)
  }

  func removeAttachment(_ attachment: ChatAttachment) {
    pendingAttachments.removeAll { $0.id == attachment.id }
    inputText = inputText.replacingOccurrences(of: ComposerInlineToken.file(attachment).marker, with: "")
  }

  func removeSkillAttachment(_ skill: SkillAttachment) {
    pendingSkills.removeAll { $0.id == skill.id }
  }

  func removeMCPAttachment(_ attachment: ComposerMCPAttachment) {
    pendingMCPAttachments.removeAll { $0.id == attachment.id }
  }

  func addCommandAlias(_ alias: SlashCommandAlias) {
    guard !pendingCommandAliases.contains(alias) else { return }
    pendingCommandAliases.append(alias)
  }

  func removeCommandAlias(_ alias: SlashCommandAlias) {
    pendingCommandAliases.removeAll { $0.id == alias.id }
  }

  func createInlineCommand(name: String, prompt: String) {
    wsManager.addSlashCommand(command: name, title: name, replacementText: prompt)
  }

  func openComposerCommandDestination(_ destination: ComposerCommandDestination) {
    MenuBarContentView.showSettings(
      wsManager: wsManager,
      launchIntent: destination.settingsLaunchIntent
    )
  }

  func runComposerCommandAction(_ action: SavedWorkflow) {
    guard remoteSendIsReady() else { return }
    guard wsManager.isConnected, !wsManager.isStreaming, !wsManager.isStoppingRun,
      validateDraftAttachments() else { return }
    guard wsManager.currentConversation?.isProviderHistory != true || wsManager.currentConversation?.canResume != false else { return }
    guard let prompt = action.prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
      !prompt.isEmpty
    else { return }

    let displayText = "Run workflow: \(action.title)"
    var draft = composerDraft
    draft.text = prompt
    draft.skills = uniqueSkills((action.skills ?? []) + draft.skills)

    activeMessageIndex = nil
    prepareForRequest()

    let currentContexts = sessionContexts
    messages.append(
      ChatMessage(
        userPrompt: displayText,
        context: currentContexts,
        aiResponse: nil,
        attachments: draft.attachments,
        draft: draft
      ))

    pendingAttachments.removeAll()
    let selectedBrowserTabs = pendingBrowserTabs.isEmpty ? nil : pendingBrowserTabs
    pendingBrowserTabs.removeAll()
    let selectedMCPIds = uniqueServerIds(from: pendingMCPAttachments)
    let actionMCPIds = uniqueStrings((action.mcpServerIds ?? []) + selectedMCPIds)
    let selectedSkills = pendingSkills
    pendingMCPAttachments.removeAll()
    pendingSkills.removeAll()
    pendingCommandAliases.removeAll()

    wsManager.sendChat(
      text: prompt,
      displayText: displayText,
      files: draft.files,
      workspacePath: workingDirectoryStore.path,
      attachmentContext: currentContexts.compactMap(\.text).joined(separator: "\n\n"),
      zeroDataRetention: AISettings.zeroDataRetention,
      actionId: action.id,
      mcpServerIds: actionMCPIds.isEmpty ? nil : actionMCPIds,
      skills: uniqueSkills((action.skills ?? []) + selectedSkills),
      browserTabs: selectedBrowserTabs
    )
    if let saved = revisionSession.finish() { applyDraft(saved) }
    retainSentAttachments()
  }
}
