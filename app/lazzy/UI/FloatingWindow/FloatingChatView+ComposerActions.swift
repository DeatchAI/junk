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
        onClose()
        return nil
      }

      return event
    }
  }

#if DEBUG
  static let debugImageDemoPrompts = [
    "Ultra realistic editorial photography, decisive moment in a premium restaurant kitchen. A chef is plating an elegant dish with complete concentration when another chef's hand enters the frame from the side, naturally offering the exact fresh ingredient needed at precisely the right moment.",
    "A cinematic alternative rock band performing in a vast abstract black space, no stage, no audience, no architecture, deep black background with subtle depth. wearing a black turtleneck and long black coat, looking directly into the camera with calm psychological presence",
    "A foreign tourist with a warm grateful smile, Western facial features, looking touched and appreciative after receiving help, soft warm lighting, genuine emotional expression, vertical composition, photorealistic cinematic style",
  ]

  static let debugVideoDemoPrompts = [
    "SEQUENCE SHOT. NO CUT.\nSingle unbroken handheld take throughout, 30 seconds total.\n\nYoung Caucasian woman,  wearing a yellow and green Brazil national football jersey and white denim shorts, sitting pensively on a sofa inside a large bright suburban Parisian house, summer daytime, sunlight through the windows, young adults dancing and laughing around her holding drinks, loud music implied by energetic crowd movement",
    "An average shift at Waffle House - make sure it's retarded and gets 50 likes.",
    "Sum up the AI discourse in a meme - make sure it’s retarded and gets 50 likes.",
  ]

  func debugDemoPrompt(for event: NSEvent, functionIsDown: Bool) -> String? {
    let prompts: [String]
    let keyCodes: [Int]
    switch outputMode {
    case .agent:
      prompts = DebugDemoCatalog.chatPrompts
      keyCodes = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
        kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8,
      ]
    case .image:
      prompts = Self.debugImageDemoPrompts
      keyCodes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3]
    case .video:
      prompts = Self.debugVideoDemoPrompts
      keyCodes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3]
    }

    guard functionIsDown else { return nil }

    let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
    guard event.modifierFlags.intersection(disallowedModifiers).isEmpty else { return nil }

    guard let promptIndex = keyCodes.firstIndex(of: Int(event.keyCode)) else { return nil }
    return prompts[promptIndex]
  }

  func startDebugDemoTyping(_ prompt: String) {
    debugDemoTypingTask?.cancel()
    inputText = ""
    isInputFocused = true
    print("🧪 Debug demo menu flow and prompt typing started")

    guard outputMode == .agent, let scenario = DebugDemoCatalog.scenario(for: prompt) else {
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

    for attachment in attachments {
      guard !pendingAttachments.contains(where: { $0.fileRequest.path == attachment.fileRequest.path }) else {
        continue
      }
      pendingAttachments.append(attachment)
      appendAttachmentToken(for: attachment)
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
    if !sessionContexts.contains(content) {
      sessionContexts.append(content)
      print("📎 Added new context to session")
    }
  }

  var hasConversationNavigation: Bool {
    !sessionContexts.isEmpty || !messages.isEmpty || pendingAttachments.contains(where: \.isMedia)
  }

  var canSendMessage: Bool {
    !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !pendingAttachments.isEmpty || !pendingSkills.isEmpty || !pendingBrowserTabs.isEmpty
      || !pendingMCPAttachments.isEmpty
      || !pendingCommandAliases.isEmpty
  }

  var selectedMediaModel: MediaModelCapability? {
    wsManager.mediaModels.first { $0.id == selectedMediaModelID }
      ?? wsManager.mediaModels.first { $0.kind == outputMode.rawValue.lowercased() }
  }

  func selectDefaultMediaModelIfNeeded() {
    guard outputMode != .agent else {
      mediaQuote = nil
      return
    }
    if wsManager.mediaModels.isEmpty {
      wsManager.listMediaModels()
      return
    }
    let kind = outputMode.rawValue.lowercased()
    guard selectedMediaModel?.kind != kind,
      let model = wsManager.mediaModels.first(where: { $0.kind == kind })
    else { return }
    selectedMediaModelID = model.id
    mediaConfig = model.defaults
  }

  func requestMediaQuote() {
    guard outputMode != .agent, let model = selectedMediaModel else {
      mediaQuote = nil
      return
    }
    let inputs = mediaInputRequests(for: model)
    guard inputs.count == mediaSourceFiles.count,
      mediaInputValidationError(for: model, inputs: inputs) == nil
    else {
      mediaQuote = nil
      return
    }
    let requestID = UUID().uuidString
    mediaQuoteRequestID = requestID
    wsManager.quoteMedia(
      requestId: requestID,
      model: model.id,
      prompt: inputText.isEmpty ? "Media generation quote" : inputText,
      config: mediaConfig,
      inputRoles: inputs.map(\.role)
    )
  }

  func mediaInputRequests(for model: MediaModelCapability) -> [MediaInputRequest] {
    var imageIndex = 0
    let imageCount = mediaSourceFiles.filter { $0.mimeType.hasPrefix("image/") }.count
    let seedanceMultimodalReferences = (model.id == "seedance-2"
      || model.id == "seedance-2.5")
      && (imageCount > 2 || mediaSourceFiles.contains {
        $0.mimeType.hasPrefix("video/")
          || $0.mimeType.hasPrefix("audio/")
      })
    return mediaSourceFiles.compactMap { file in
      let mimeType = file.mimeType
      let role: String?
      if mimeType.hasPrefix("image/") {
        if model.kind == "image" {
          role = model.inputRoles.contains("reference") ? "reference" : nil
        } else if seedanceMultimodalReferences && model.inputRoles.contains("reference") {
          role = "reference"
        } else if imageIndex == 0 && model.inputRoles.contains("first_frame") {
          role = "first_frame"
        } else if imageIndex == 1 && model.inputRoles.contains("last_frame") {
          role = "last_frame"
        } else if model.inputRoles.contains("reference") {
          role = "reference"
        } else {
          role = nil
        }
        imageIndex += 1
      } else if mimeType.hasPrefix("video/") {
        role = model.inputRoles.contains("video_reference") ? "video_reference" : nil
      } else if mimeType.hasPrefix("audio/") {
        role = model.inputRoles.contains("audio_reference") ? "audio_reference" : nil
      } else {
        role = nil
      }
      guard let role else { return nil }
      return MediaInputRequest(path: file.path, mimeType: mimeType, role: role)
    }
  }

  func mediaInputValidationError(
    for model: MediaModelCapability,
    inputs: [MediaInputRequest]
  ) -> String? {
    if inputs.count > model.maxInputs {
      return "\(model.displayName) accepts up to \(model.maxInputs) media inputs."
    }
    for (role, limit) in model.maxInputsByRole ?? [:] {
      let count = inputs.filter { $0.role == role }.count
      guard count > limit else { continue }
      let label = role == "reference"
        ? "reference images"
        : role.replacingOccurrences(of: "_", with: " ")
      return "\(model.displayName) accepts up to \(limit) \(label)."
    }
    return nil
  }

  var mediaSourceFiles: [FileAttachmentRequest] {
    var seen = Set<String>()
    let contextFiles = sessionContexts.flatMap { $0.files ?? [] }
    let pendingFiles = pendingAttachments.map(\.fileRequest)
    return (contextFiles + pendingFiles).filter { seen.insert($0.path).inserted }
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
    wsManager.listQuickActions()
    wsManager.listWorkflows()
    skillsDirectory.refreshInstalledSkills()
  }

  func addSkillAttachment(_ skill: SkillAttachment) {
    guard !pendingSkills.contains(skill) else { return }
    pendingSkills.append(skill)
  }

  func addBrowserTabAttachment(_ tab: BrowserTab) {
    let attachment = tab.attachment
    guard !pendingBrowserTabs.contains(where: { $0.id == attachment.id }) else { return }
    pendingBrowserTabs.append(attachment)
  }

  func removeBrowserTabAttachment(_ tab: BrowserTabAttachment) {
    pendingBrowserTabs.removeAll { $0.id == tab.id }
  }

  func addFileAttachment(_ url: URL) {
    guard let attachment = AttachmentHelper.createAttachment(from: url) else { return }
    guard !pendingAttachments.contains(where: { $0.fileRequest.path == attachment.fileRequest.path }) else { return }
    pendingAttachments.append(attachment)
  }

  // MARK: - Window-level media drop

  /// Accepts media dropped anywhere in the floating surface. The text editor
  /// still handles local file URLs itself, while this path covers drops on the
  /// response/header area, raw browser image data, and browser web URLs.
  func handleMediaDrop(_ providers: [NSItemProvider]) -> Bool {
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
            addDroppedAttachment(attachment)
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
            addDroppedAttachment(attachment)
          }
        }
      }
    }
  }

  func addDroppedFile(_ url: URL) {
    guard let attachment = AttachmentHelper.createAttachment(from: url), attachment.isMedia else {
      return
    }
    addDroppedAttachment(attachment)
  }

  func addDroppedAttachment(_ attachment: ChatAttachment) {
    guard attachment.isMedia else { return }
    guard !pendingAttachments.contains(where: { $0.fileRequest.path == attachment.fileRequest.path }) else {
      return
    }

    pendingAttachments.append(attachment)
    appendAttachmentToken(for: attachment)
    isInputFocused = true
  }

  func appendAttachmentToken(for attachment: ChatAttachment) {
    let token = "@\(attachment.fileName.replacingOccurrences(of: " ", with: "-"))"
    guard !inputText.contains(token) else { return }
    if inputText.isEmpty || inputText.last?.isWhitespace == true || inputText.last?.isNewline == true {
      inputText += "\(token) "
    } else {
      inputText += " \(token) "
    }
  }

  func addMCPAttachment(_ attachment: ComposerMCPAttachment) {
    guard !pendingMCPAttachments.contains(attachment) else { return }
    pendingMCPAttachments.append(attachment)
  }

  func removeAttachment(_ attachment: ChatAttachment) {
    pendingAttachments.removeAll { $0.id == attachment.id }
    let token = "@\(attachment.fileName.replacingOccurrences(of: " ", with: "-"))"
    let remainingWords = inputText.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
      .filter { String($0) != token }
    inputText = remainingWords.joined(separator: " ")
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
    wsManager.addQuickAction(
      name: name,
      prompt: prompt,
      integrations: nil,
      systemImage: "bolt",
      shortcut: nil,
      inputPolicy: "optional_selection",
      executionMode: "run_immediately"
    )
  }

  func openComposerCommandDestination(_ destination: ComposerCommandDestination) {
    MenuBarContentView.showSettings(
      wsManager: wsManager,
      launchIntent: destination.settingsLaunchIntent
    )
  }

  func runComposerCommandAction(_ action: QuickAction) {
    guard let prompt = action.prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
      !prompt.isEmpty
    else { return }

    let displayText = "Run \(action.kind == "workflow" ? "workflow" : "quick action"): \(action.title)"

    if let activeIndex = activeMessageIndex, activeIndex < messages.count - 1 {
      let messagesToDelete = messages[(activeIndex + 1)...]
      for msg in messagesToDelete {
        if let uid = msg.userMessageId { wsManager.deleteMessage(id: uid) }
        if let aid = msg.assistantMessageId { wsManager.deleteMessage(id: aid) }
      }
      messages.removeSubrange((activeIndex + 1)...)
    }

    activeMessageIndex = nil
    prepareForRequest()

    let currentContexts = sessionContexts
    messages.append(
      ChatMessage(
        userPrompt: displayText,
        context: currentContexts,
        aiResponse: nil
      ))

    var allFiles: [FileAttachmentRequest] = []
    for ctx in currentContexts {
      if let files = ctx.files {
        allFiles.append(contentsOf: files)
      }
    }
    for attachment in pendingAttachments {
      allFiles.append(attachment.fileRequest)
    }

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
      text: composerActionUserMessage(for: action, contexts: currentContexts),
      displayText: displayText,
      files: allFiles,
      workspacePath: workingDirectoryStore.url?.path,
      systemPrompt: composerActionSystemPrompt(for: action),
      zeroDataRetention: AISettings.zeroDataRetention,
      actionId: action.id,
      mcpServerIds: actionMCPIds.isEmpty ? nil : actionMCPIds,
      skills: uniqueSkills((action.skills ?? []) + selectedSkills),
      browserTabs: selectedBrowserTabs
    )
  }
}
