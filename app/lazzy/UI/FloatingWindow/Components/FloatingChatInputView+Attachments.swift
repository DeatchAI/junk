import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension FloatingChatInputView {
  var voiceStatus: some View {
    HStack(spacing: 8) {
      Image(systemName: voiceStatusIcon)
        .font(.appFont(size: 12, weight: .semibold))
        .foregroundColor(voiceStatusColor)

      Text(voiceStatusText)
        .font(.appFont(size: 12, weight: .medium))
        .foregroundColor(theme.textColor.opacity(0.72))
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)

      if voiceDictationState == .listening {
        Text("Release Fn to attach")
          .font(.appFont(size: 10, weight: .medium))
          .foregroundColor(theme.secondaryTextColor)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 7)
    .background(theme.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
  }

  var voiceStatusText: String {
    switch voiceDictationState {
    case .idle:
      return ""
    case .requestingPermission:
      return "Preparing voice input…"
    case .listening:
      let partial = voicePartialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
      return partial.isEmpty ? "Listening…" : partial
    case .processing:
      return "Finishing transcription…"
    case .failed(let message):
      return message
    }
  }

  var voiceStatusIcon: String {
    switch voiceDictationState {
    case .idle, .requestingPermission:
      return "mic"
    case .listening:
      return "waveform"
    case .processing:
      return "ellipsis"
    case .failed:
      return "exclamationmark.triangle"
    }
  }

  var voiceStatusColor: Color {
    if case .failed = voiceDictationState {
      return .red
    }
    return theme.accentColor
  }

  var hasAttachments: Bool {
    !fileAttachments.isEmpty || !selectedSkills.isEmpty || !selectedBrowserTabs.isEmpty
      || !selectedMCPAttachments.isEmpty
      || !selectedCommands.isEmpty
  }

  var mentionSearchQuery: String {
    guard let mentionTriggerOffset, mentionTriggerOffset < inputText.count else { return "" }
    let triggerIndex = inputText.index(inputText.startIndex, offsetBy: mentionTriggerOffset)
    let afterTrigger = inputText.index(after: triggerIndex)
    return String(inputText[afterTrigger...].prefix { !$0.isWhitespace && !$0.isNewline })
  }

  /// Skills are searched from the whole trailing composer phrase so queries
  /// such as `@web design` are useful, rather than being cut off at a space.
  var skillsSearchQuery: String {
    guard let mentionTriggerOffset, mentionTriggerOffset < inputText.count else { return "" }
    let triggerIndex = inputText.index(inputText.startIndex, offsetBy: mentionTriggerOffset)
    let afterTrigger = inputText.index(after: triggerIndex)
    return String(inputText[afterTrigger...].prefix { !$0.isNewline })
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var attachmentMenuContentRefreshID: AnyHashable? {
    switch attachmentMenuPage {
    case .files:
      // The file browser observes fileCatalog directly. Keep the detached
      // hosting view alive while results change so AppKit does not rebuild and
      // reposition the panel for every typed character.
      return AnyHashable("files")
    case .browserTabs:
      let tabs = browserTabStore.tabs
        .map { "\($0.id):\($0.title):\($0.url)" }
        .joined(separator: "\u{1F}")
      let selection = selectedBrowserTabs.map(\.id).sorted().map(String.init).joined(separator: "\u{1F}")
      return AnyHashable("\(browserTabStore.isLoading)|\(browserTabStore.errorMessage ?? "")|\(tabs)|\(selection)")
    case .skills:
      return AnyHashable(availableSkills.map(\.id).joined(separator: "\u{1F}"))
    case .discoverSkills, .remoteSkillDetail:
      return AnyHashable(skillsSearchQuery)
    case .root, .mcpServers:
      // The picker lives in a detached AppKit host. Include the live MCP
      // snapshot so a newly connected server replaces the host's captured
      // menu instead of waiting for the panel to be reopened.
      let mcpState = availableMCPAttachments
        .map { "\($0.id):\($0.name):\($0.detail)" }
        .joined(separator: "\u{1F}")
      let selection = selectedMCPAttachments.map(\.id).sorted().joined(separator: "\u{1F}")
      return AnyHashable("\(isLoadingMCPAttachments)|\(mcpState)|\(selection)")
    }
  }

  var slashCommandQuery: String {
    guard let slashTriggerOffset, slashTriggerOffset < inputText.count else { return "" }
    let triggerIndex = inputText.index(inputText.startIndex, offsetBy: slashTriggerOffset)
    let afterTrigger = inputText.index(after: triggerIndex)
    return String(inputText[afterTrigger...].prefix { !$0.isWhitespace && !$0.isNewline })
  }

  func updateAttachmentMenuTrigger(for value: String) {
    if value.last == "@" {
      let beforeMention = value.dropLast().last
      guard beforeMention == nil || beforeMention?.isWhitespace == true else { return }

      mentionTriggerOffset = value.count - 1
      attachmentMenuPage = .root
      isAttachmentMenuPresented = true
      dismissSlashCommandMenu()
      return
    }

    guard isAttachmentMenuPresented, let mentionTriggerOffset else { return }
    let mentionStillExists = mentionTriggerOffset < value.count
      && value[value.index(value.startIndex, offsetBy: mentionTriggerOffset)] == "@"

    if !mentionStillExists {
      dismissAttachmentMenu()
    } else if attachmentMenuPage == .discoverSkills {
      skillsDirectory.search(query: skillsSearchQuery)
    } else if attachmentMenuPage == .files {
      if workingDirectoryStore.url == nil {
        chooseFilesFromMac()
      } else {
        fileCatalog.search(query: mentionSearchQuery)
      }
    } else if !mentionSearchQuery.isEmpty {
      if workingDirectoryStore.url == nil {
        chooseFilesFromMac()
      } else {
        attachmentMenuPage = .files
        fileCatalog.search(query: mentionSearchQuery)
      }
    }
  }

  func updateSlashCommandTrigger(for value: String) {
    if value.last == "/" {
      let beforeSlash = value.dropLast().last
      guard beforeSlash == nil || beforeSlash?.isWhitespace == true else { return }

      slashTriggerOffset = value.count - 1
      isSlashCommandMenuPresented = true
      dismissAttachmentMenu()
      return
    }

    guard isSlashCommandMenuPresented, let slashTriggerOffset else { return }
    let slashStillExists = slashTriggerOffset < value.count
      && value[value.index(value.startIndex, offsetBy: slashTriggerOffset)] == "/"
    let slashTokenIsActive = slashStillExists
      && !String(value[value.index(after: value.index(value.startIndex, offsetBy: slashTriggerOffset))...])
        .contains(where: { $0.isWhitespace || $0.isNewline })

    if !slashStillExists || !slashTokenIsActive {
      dismissSlashCommandMenu()
    }
  }

  func completeFileAttachment(_ url: URL) {
    replaceMentionToken(with: inlineFileToken(for: url))
    onAttachFile(url)
  }

  func completeBrowserTabAttachment(_ tab: BrowserTab) {
    replaceMentionToken(with: inlineBrowserTabToken(for: tab))
    onAttachBrowserTab(tab)
  }

  func chooseWorkingDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Use Folder"
    panel.message = "Choose the folder you are working in. File search will stay inside it."
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      workingDirectoryStore.setDirectory(url)
    }
  }

  func chooseFilesFromMac() {
    // The Finder panel is a separate window. Hide the inline attachment
    // surface first, but keep mentionTriggerOffset until a selection can
    // replace the typed @ token.
    isAttachmentMenuPresented = false
    attachmentMenuPage = .root
    fileCatalog.cancel()

    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    panel.prompt = "Attach"
    panel.begin { response in
      guard response == .OK else {
        mentionTriggerOffset = nil
        return
      }
      for url in panel.urls {
        completeFileAttachment(url)
      }
    }
  }

  func attachDroppedFiles(_ urls: [URL]) {
    var attachedPaths = Set(fileAttachments.map(\.fileRequest.path))
    for url in urls where url.isFileURL && attachedPaths.insert(url.path).inserted {
      appendInlineToken(inlineFileToken(for: url))
      onAttachFile(url)
    }
    isInputFocused.wrappedValue = true
  }

  func attachDroppedImage(_ image: NSImage) {
    guard let attachment = AttachmentHelper.createAttachment(from: image) else { return }
    onAttachFile(URL(fileURLWithPath: attachment.fileRequest.path))
    appendInlineToken(inlineFileToken(for: URL(fileURLWithPath: attachment.fileRequest.path)))
    isInputFocused.wrappedValue = true
  }

  func attachDroppedRemoteURL(_ url: URL) {
    Task {
      guard let attachment = await AttachmentHelper.createAttachment(fromRemoteURL: url) else { return }
      await MainActor.run {
        let fileURL = URL(fileURLWithPath: attachment.fileRequest.path)
        onAttachFile(fileURL)
        appendInlineToken(inlineFileToken(for: fileURL))
        isInputFocused.wrappedValue = true
      }
    }
  }

  func replaceMentionQuery(with query: String) {
    guard let mentionTriggerOffset, mentionTriggerOffset < inputText.count else { return }
    let start = inputText.index(inputText.startIndex, offsetBy: mentionTriggerOffset)
    guard inputText[start] == "@" else { return }

    var end = inputText.index(after: start)
    while end < inputText.endIndex, !inputText[end].isWhitespace, !inputText[end].isNewline {
      inputText.formIndex(after: &end)
    }

    inputText.replaceSubrange(inputText.index(after: start)..<end, with: query)
  }

  func completeSkillAttachment(_ skill: SkillAttachment) {
    replaceMentionToken(with: inlineSkillToken(for: skill))
    onAttachSkill(skill)
  }

  func completeMCPAttachment(_ attachment: ComposerMCPAttachment) {
    replaceMentionToken(with: inlineMCPToken(for: attachment))
    onAttachMCP(attachment)
  }

  func completeSlashAlias(_ alias: SlashCommandAlias) {
    replaceSlashCommandToken(with: inlineCommandToken(for: alias) + " ")
    onAttachCommand(alias)
    dismissSlashCommandMenu()
    isInputFocused.wrappedValue = true
  }

  func completeSlashAction(_ action: QuickAction) {
    consumeSlashCommandToken()
    onRunCommandAction(action)
  }

  func completeCreateCommand(name: String, prompt: String) {
    consumeSlashCommandToken()
    onCreateCommand(name, prompt)
  }

  func completeSlashDestination(_ destination: ComposerCommandDestination) {
    consumeSlashCommandToken()
    onOpenCommandDestination(destination)
  }

  func consumeMentionTrigger() {
    if let mentionTriggerOffset, mentionTriggerOffset < inputText.count {
      let start = inputText.index(inputText.startIndex, offsetBy: mentionTriggerOffset)
      if inputText[start] == "@" {
        var end = inputText.index(after: start)
        while end < inputText.endIndex, !inputText[end].isWhitespace, !inputText[end].isNewline {
          inputText.formIndex(after: &end)
        }
        inputText.removeSubrange(start..<end)
      }
    }
    dismissAttachmentMenu()
    isInputFocused.wrappedValue = true
  }

  func replaceMentionToken(with token: String) {
    guard let mentionTriggerOffset, mentionTriggerOffset < inputText.count else {
      appendInlineToken(token)
      dismissAttachmentMenu()
      isInputFocused.wrappedValue = true
      return
    }
    let start = inputText.index(inputText.startIndex, offsetBy: mentionTriggerOffset)
    guard inputText[start] == "@" else {
      appendInlineToken(token)
      dismissAttachmentMenu()
      isInputFocused.wrappedValue = true
      return
    }

    var end = inputText.index(after: start)
    while end < inputText.endIndex, !inputText[end].isWhitespace, !inputText[end].isNewline {
      inputText.formIndex(after: &end)
    }

    inputText.replaceSubrange(start..<end, with: token + " ")
    dismissAttachmentMenu()
    isInputFocused.wrappedValue = true
  }

  func replaceSlashCommandToken(with replacement: String) {
    guard let slashTriggerOffset, slashTriggerOffset < inputText.count else { return }
    let start = inputText.index(inputText.startIndex, offsetBy: slashTriggerOffset)
    guard inputText[start] == "/" else { return }

    var end = inputText.index(after: start)
    while end < inputText.endIndex, !inputText[end].isWhitespace, !inputText[end].isNewline {
      inputText.formIndex(after: &end)
    }

    inputText.replaceSubrange(start..<end, with: replacement)
  }

  func consumeSlashCommandToken() {
    replaceSlashCommandToken(with: "")
    dismissSlashCommandMenu()
    isInputFocused.wrappedValue = true
  }

  func dismissAttachmentMenu() {
    isAttachmentMenuPresented = false
    attachmentMenuPage = .root
    mentionTriggerOffset = nil
    fileCatalog.cancel()
  }

  func dismissSlashCommandMenu() {
    isSlashCommandMenuPresented = false
    slashTriggerOffset = nil
  }

  func performDebugMenuStep(_ step: DebugComposerMenuStep?) {
    guard let step else { return }

    switch step {
    case .showAttachmentMenu:
      mentionTriggerOffset = nil
      attachmentMenuPage = .root
      isAttachmentMenuPresented = true
      dismissSlashCommandMenu()
    case .selectMCP(let id):
      guard isAttachmentMenuPresented, let attachment = debugMCPAttachment(for: id) else { break }
      // Use the same callback the visible MCP rows use, then keep the picker
      // open so the recording shows multiple capability selections in context.
      onAttachMCP(attachment)
      appendInlineToken(inlineMCPToken(for: attachment))
      isInputFocused.wrappedValue = true
    case .selectFile(let url):
      guard isAttachmentMenuPresented else { break }
      // Use the same attachment callback as the visible file picker. The
      // scripted URL is a real file or folder, so it travels with the request.
      onAttachFile(url)
      appendInlineToken(inlineFileToken(for: url))
      isInputFocused.wrappedValue = true
    case .dismissAttachmentMenu:
      dismissAttachmentMenu()
    case .showCommandMenu:
      dismissAttachmentMenu()
      if let last = inputText.last, !last.isWhitespace && !last.isNewline {
        inputText.append(" ")
      }
      inputText.append("/")
      slashTriggerOffset = inputText.count - 1
      isSlashCommandMenuPresented = true
      isInputFocused.wrappedValue = true
    case .selectCommand(let id):
      guard isSlashCommandMenuPresented,
        let alias = SlashCommandAlias.defaults.first(where: { $0.id == id })
      else { break }
      // This is the same completion path as clicking a command row.
      completeSlashAlias(alias)
    case .dismissCommandMenu:
      dismissSlashCommandMenu()
    }

    // Each scripted step is an edge-triggered request. Clearing it lets a
    // later recording start from the same menu state without stale actions.
    debugMenuStep = nil
  }

  func debugMCPAttachment(for id: String) -> ComposerMCPAttachment? {
    switch id {
    case ComposerMCPAttachment.browser.id:
      return .browser
    case ComposerMCPAttachment.macOS.id:
      return .macOS
    case ComposerMCPAttachment.secrets.id:
      return .secrets
    default:
      return nil
    }
  }

  func appendInlineToken(_ token: String) {
    if inputText.isEmpty || inputText.last?.isWhitespace == true || inputText.last?.isNewline == true {
      inputText += "\(token) "
    } else {
      inputText += " \(token) "
    }
  }

  func inlineCommandToken(for alias: SlashCommandAlias) -> String {
    "/\(alias.command)"
  }

  func inlineMCPToken(for attachment: ComposerMCPAttachment) -> String {
    "@\(attachment.name.replacingOccurrences(of: " ", with: "-"))"
  }

  func inlineSkillToken(for skill: SkillAttachment) -> String {
    "@\(skill.name.replacingOccurrences(of: " ", with: "-"))"
  }

  func inlineFileToken(for url: URL) -> String {
    "@\(url.lastPathComponent.replacingOccurrences(of: " ", with: "-"))"
  }

  func inlineBrowserTabToken(for tab: BrowserTab) -> String {
    inlineBrowserTabToken(title: tab.title, id: tab.id)
  }

  func inlineBrowserTabToken(for tab: BrowserTabAttachment) -> String {
    inlineBrowserTabToken(title: tab.title, id: tab.id)
  }

  private func inlineBrowserTabToken(title: String, id: Int) -> String {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let label = title.isEmpty ? "chrome-tab-\(id)" : title
    return "@\(label.replacingOccurrences(of: " ", with: "-"))"
  }

  func removeLastInlineToken() {
    let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let lastTokenRange = trimmed.range(
      of: #"(^|\s)([@/][^\s]+)$"#,
      options: .regularExpression
    ) else { return }

    let token = String(trimmed[lastTokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    inputText = String(trimmed[..<lastTokenRange.lowerBound]).trimmingCharacters(in: .whitespaces)
    if !inputText.isEmpty { inputText += " " }
    removeSelections(matchingInlineToken: token)
  }

  func removeDetachedSelectionsMissingFromText(_ text: String) {
    for command in selectedCommands where !containsInlineToken(inlineCommandToken(for: command), in: text) {
      onRemoveCommand(command)
    }
    for attachment in selectedMCPAttachments where !containsInlineToken(inlineMCPToken(for: attachment), in: text) {
      onRemoveMCP(attachment)
    }
    for skill in selectedSkills where !containsInlineToken(inlineSkillToken(for: skill), in: text) {
      onRemoveSkill(skill)
    }
    for file in fileAttachments {
      let token = "@\(file.fileName.replacingOccurrences(of: " ", with: "-"))"
      if !containsInlineToken(token, in: text) {
        onRemoveFile(file)
      }
    }
    for tab in selectedBrowserTabs where !containsInlineToken(inlineBrowserTabToken(for: tab), in: text) {
      onRemoveBrowserTab(tab)
    }
  }

  func removeSelections(matchingInlineToken token: String) {
    for command in selectedCommands where inlineCommandToken(for: command) == token {
      onRemoveCommand(command)
      return
    }
    for attachment in selectedMCPAttachments where inlineMCPToken(for: attachment) == token {
      onRemoveMCP(attachment)
      return
    }
    for skill in selectedSkills where inlineSkillToken(for: skill) == token {
      onRemoveSkill(skill)
      return
    }
    for file in fileAttachments where "@\(file.fileName.replacingOccurrences(of: " ", with: "-"))" == token {
      onRemoveFile(file)
      return
    }
    for tab in selectedBrowserTabs where inlineBrowserTabToken(for: tab) == token {
      onRemoveBrowserTab(tab)
      return
    }
  }

  func containsInlineToken(_ token: String, in text: String) -> Bool {
    text.range(
      of: #"(^|\s)\#(NSRegularExpression.escapedPattern(for: token))(?=\s|$)"#,
      options: .regularExpression
    ) != nil
  }
}
