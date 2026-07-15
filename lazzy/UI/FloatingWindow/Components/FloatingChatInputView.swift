import AppKit
import SwiftUI

struct FloatingChatInputView: View {
  @Binding var inputText: String
  var isInputFocused: FocusState<Bool>.Binding
  var onClose: () -> Void
  let fileAttachments: [ChatAttachment]
  let selectedSkills: [SkillAttachment]
  let selectedMCPAttachments: [ComposerMCPAttachment]
  let selectedCommands: [SlashCommandAlias]
  let availableMCPAttachments: [ComposerMCPAttachment]
  let availableSkills: [SkillAttachment]
  let workflows: [QuickAction]
  let quickActions: [QuickAction]
  @Binding var isAttachmentMenuRequested: Bool
  @Binding var isAttachmentMenuActive: Bool
  @Binding var isCommandMenuActive: Bool
  var onAttachFile: (URL) -> Void
  var onAttachSkill: (SkillAttachment) -> Void
  var onAttachMCP: (ComposerMCPAttachment) -> Void
  var onAttachCommand: (SlashCommandAlias) -> Void
  var onCreateCommand: (String, String) -> Void
  var onRunCommandAction: (QuickAction) -> Void
  var onOpenCommandDestination: (ComposerCommandDestination) -> Void
  var onRemoveFile: (ChatAttachment) -> Void
  var onRemoveSkill: (SkillAttachment) -> Void
  var onRemoveMCP: (ComposerMCPAttachment) -> Void
  var onRemoveCommand: (SlashCommandAlias) -> Void
  var selectedAction: String = "Anything .."

  @ObservedObject private var theme = ThemeManager.shared
  @State private var isAttachmentMenuPresented = false
  @State private var isSlashCommandMenuPresented = false
  @State private var attachmentMenuPage: ComposerAttachmentMenuPage = .root
  @State private var mentionTriggerOffset: Int?
  @State private var slashTriggerOffset: Int?

  var body: some View {
    VStack(spacing: 8) {
        HStack(alignment: .top, spacing: 8) {
          ZStack(alignment: .topLeading) {
            if inputText.isEmpty {
              Text(selectedAction)
                .foregroundColor(theme.secondaryTextColor)
                .padding(.horizontal, 5)
            }

            InlineComposerTextEditor(
              text: $inputText,
              isFocused: isInputFocused,
              textColor: NSColor(theme.textColor),
              tokenColor: NSColor(theme.accentColor),
              font: AppFont.nsFont(size: 14),
              onBackspaceWhenEmpty: removeLastInlineToken
            )
              .frame(minHeight: 24, maxHeight: 80)
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          Button(action: onClose) {
            Image(systemName: "xmark")
              .font(.appFont(size: 14, weight: .bold))
              .foregroundColor(theme.textColor.opacity(0.5))
          }
          .buttonStyle(.plain)
          .padding(.top, 4)
        }
    }
    .background {
      ComposerAttachmentPanelAnchor(
        isPresented: $isAttachmentMenuPresented,
        preferredWidth: attachmentMenuPage == .files ? 320 : 280,
        menu: ComposerAttachmentMenu(
          page: $attachmentMenuPage,
          availableMCPAttachments: availableMCPAttachments,
          availableSkills: availableSkills,
          selectedMCPIds: Set(selectedMCPAttachments.map(\.id)),
          selectedSkillIds: Set(selectedSkills.map(\.id)),
          fileSearchQuery: mentionSearchQuery,
          onAttachFile: completeFileAttachment,
          onUpdateFileQuery: replaceMentionQuery,
          onAttachSkill: completeSkillAttachment,
          onAttachMCP: completeMCPAttachment,
          onDismiss: dismissAttachmentMenu
        )
      )
    }
    .background {
      ComposerAttachmentPanelAnchor(
        isPresented: $isSlashCommandMenuPresented,
        preferredWidth: 320,
        menu: ComposerSlashCommandMenu(
          query: slashCommandQuery,
          workflows: workflows,
          quickActions: quickActions,
          onSelectAlias: completeSlashAlias,
          onSelectAction: completeSlashAction,
          onCreateCommand: completeCreateCommand,
          onOpenDestination: completeSlashDestination,
          onDismiss: dismissSlashCommandMenu
        )
      )
    }
    .padding(.horizontal, 14)
    .padding(.top, 14)
    .padding(.bottom, 8)
    .onChange(of: inputText) { _, newValue in
      updateAttachmentMenuTrigger(for: newValue)
      updateSlashCommandTrigger(for: newValue)
      removeDetachedSelectionsMissingFromText(newValue)
    }
    .onChange(of: isAttachmentMenuRequested) { _, isRequested in
      guard isRequested else { return }
      mentionTriggerOffset = nil
      attachmentMenuPage = .root
      isAttachmentMenuPresented = true
      dismissSlashCommandMenu()
      isAttachmentMenuRequested = false
    }
    .onChange(of: isAttachmentMenuPresented) { _, isPresented in
      isAttachmentMenuActive = isPresented
    }
    .onChange(of: isSlashCommandMenuPresented) { _, isPresented in
      isCommandMenuActive = isPresented
    }
    .onDisappear {
      isAttachmentMenuActive = false
      isCommandMenuActive = false
    }
  }

  private var hasAttachments: Bool {
    !fileAttachments.isEmpty || !selectedSkills.isEmpty || !selectedMCPAttachments.isEmpty
      || !selectedCommands.isEmpty
  }

  private var mentionSearchQuery: String {
    guard let mentionTriggerOffset, mentionTriggerOffset < inputText.count else { return "" }
    let triggerIndex = inputText.index(inputText.startIndex, offsetBy: mentionTriggerOffset)
    let afterTrigger = inputText.index(after: triggerIndex)
    return String(inputText[afterTrigger...].prefix { !$0.isWhitespace && !$0.isNewline })
  }

  private var slashCommandQuery: String {
    guard let slashTriggerOffset, slashTriggerOffset < inputText.count else { return "" }
    let triggerIndex = inputText.index(inputText.startIndex, offsetBy: slashTriggerOffset)
    let afterTrigger = inputText.index(after: triggerIndex)
    return String(inputText[afterTrigger...].prefix { !$0.isWhitespace && !$0.isNewline })
  }

  private func updateAttachmentMenuTrigger(for value: String) {
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
    } else if !mentionSearchQuery.isEmpty {
      attachmentMenuPage = .files
    }
  }

  private func updateSlashCommandTrigger(for value: String) {
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

  private func completeFileAttachment(_ url: URL) {
    replaceMentionToken(with: inlineFileToken(for: url))
    onAttachFile(url)
  }

  private func replaceMentionQuery(with query: String) {
    guard let mentionTriggerOffset, mentionTriggerOffset < inputText.count else { return }
    let start = inputText.index(inputText.startIndex, offsetBy: mentionTriggerOffset)
    guard inputText[start] == "@" else { return }

    var end = inputText.index(after: start)
    while end < inputText.endIndex, !inputText[end].isWhitespace, !inputText[end].isNewline {
      inputText.formIndex(after: &end)
    }

    inputText.replaceSubrange(inputText.index(after: start)..<end, with: query)
  }

  private func completeSkillAttachment(_ skill: SkillAttachment) {
    replaceMentionToken(with: inlineSkillToken(for: skill))
    onAttachSkill(skill)
  }

  private func completeMCPAttachment(_ attachment: ComposerMCPAttachment) {
    replaceMentionToken(with: inlineMCPToken(for: attachment))
    onAttachMCP(attachment)
  }

  private func completeSlashAlias(_ alias: SlashCommandAlias) {
    replaceSlashCommandToken(with: inlineCommandToken(for: alias) + " ")
    onAttachCommand(alias)
    dismissSlashCommandMenu()
    isInputFocused.wrappedValue = true
  }

  private func completeSlashAction(_ action: QuickAction) {
    consumeSlashCommandToken()
    onRunCommandAction(action)
  }

  private func completeCreateCommand(name: String, prompt: String) {
    consumeSlashCommandToken()
    onCreateCommand(name, prompt)
  }

  private func completeSlashDestination(_ destination: ComposerCommandDestination) {
    consumeSlashCommandToken()
    onOpenCommandDestination(destination)
  }

  private func consumeMentionTrigger() {
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

  private func replaceMentionToken(with token: String) {
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

  private func replaceSlashCommandToken(with replacement: String) {
    guard let slashTriggerOffset, slashTriggerOffset < inputText.count else { return }
    let start = inputText.index(inputText.startIndex, offsetBy: slashTriggerOffset)
    guard inputText[start] == "/" else { return }

    var end = inputText.index(after: start)
    while end < inputText.endIndex, !inputText[end].isWhitespace, !inputText[end].isNewline {
      inputText.formIndex(after: &end)
    }

    inputText.replaceSubrange(start..<end, with: replacement)
  }

  private func consumeSlashCommandToken() {
    replaceSlashCommandToken(with: "")
    dismissSlashCommandMenu()
    isInputFocused.wrappedValue = true
  }

  private func dismissAttachmentMenu() {
    isAttachmentMenuPresented = false
    attachmentMenuPage = .root
    mentionTriggerOffset = nil
  }

  private func dismissSlashCommandMenu() {
    isSlashCommandMenuPresented = false
    slashTriggerOffset = nil
  }

  private func appendInlineToken(_ token: String) {
    if inputText.isEmpty || inputText.last?.isWhitespace == true || inputText.last?.isNewline == true {
      inputText += "\(token) "
    } else {
      inputText += " \(token) "
    }
  }

  private func inlineCommandToken(for alias: SlashCommandAlias) -> String {
    "/\(alias.command)"
  }

  private func inlineMCPToken(for attachment: ComposerMCPAttachment) -> String {
    "@\(attachment.name.replacingOccurrences(of: " ", with: "-"))"
  }

  private func inlineSkillToken(for skill: SkillAttachment) -> String {
    "@\(skill.name.replacingOccurrences(of: " ", with: "-"))"
  }

  private func inlineFileToken(for url: URL) -> String {
    "@\(url.lastPathComponent.replacingOccurrences(of: " ", with: "-"))"
  }

  private func removeLastInlineToken() {
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

  private func removeDetachedSelectionsMissingFromText(_ text: String) {
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
  }

  private func removeSelections(matchingInlineToken token: String) {
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
  }

  private func containsInlineToken(_ token: String, in text: String) -> Bool {
    text.range(
      of: #"(^|\s)\#(NSRegularExpression.escapedPattern(for: token))(?=\s|$)"#,
      options: .regularExpression
    ) != nil
  }
}

struct ComposerMCPAttachment: Identifiable, Hashable {
  let id: String
  let serverId: String
  let name: String
  let systemImage: String
  let detail: String

  init(id: String, serverId: String? = nil, name: String, systemImage: String, detail: String) {
    self.id = id
    self.serverId = serverId ?? id
    self.name = name
    self.systemImage = systemImage
    self.detail = detail
  }

  static let browser = ComposerMCPAttachment(
    id: "detach-browser-tools",
    name: "Browser",
    systemImage: "globe",
    detail: "Use your connected Chrome profile"
  )

  static let macOS = ComposerMCPAttachment(
    id: "detach-macos-tools",
    name: "macOS",
    systemImage: "macwindow",
    detail: "Control native macOS apps"
  )

  static let secrets = ComposerMCPAttachment(
    id: "detach-secrets-tools",
    name: "Secrets",
    systemImage: "lock.fill",
    detail: "Use saved credentials with Touch ID"
  )
}

private struct InlineComposerTextEditor: NSViewRepresentable {
  @Binding var text: String
  var isFocused: FocusState<Bool>.Binding
  let textColor: NSColor
  let tokenColor: NSColor
  let font: NSFont
  let onBackspaceWhenEmpty: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, isFocused: isFocused, onBackspaceWhenEmpty: onBackspaceWhenEmpty)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.borderType = .noBorder

    let textView = ComposerNSTextView()
    textView.delegate = context.coordinator
    textView.onBackspaceWhenEmpty = {
      context.coordinator.onBackspaceWhenEmpty()
    }
    textView.isRichText = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.drawsBackground = false
    textView.backgroundColor = .clear
    textView.textContainerInset = NSSize(width: 0, height: 0)
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.minSize = NSSize(width: 0, height: 24)
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 80)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.font = font
    textView.textColor = textColor
    textView.insertionPointColor = textColor
    textView.tokenColor = tokenColor
    textView.baseTextColor = textColor
    textView.baseFont = font

    scrollView.documentView = textView
    context.coordinator.textView = textView
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = context.coordinator.textView else { return }
    context.coordinator.text = $text
    context.coordinator.isFocused = isFocused
    context.coordinator.onBackspaceWhenEmpty = onBackspaceWhenEmpty

    if textView.string != text {
      textView.string = text
    }
    textView.font = font
    textView.textColor = textColor
    textView.insertionPointColor = textColor
    textView.tokenColor = tokenColor
    textView.baseTextColor = textColor
    textView.baseFont = font
    textView.applyInlineTokenStyles()

    if isFocused.wrappedValue, textView.window?.firstResponder !== textView {
      DispatchQueue.main.async {
        textView.window?.makeFirstResponder(textView)
      }
    }
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var text: Binding<String>
    var isFocused: FocusState<Bool>.Binding
    var onBackspaceWhenEmpty: () -> Void
    weak var textView: ComposerNSTextView?

    init(
      text: Binding<String>,
      isFocused: FocusState<Bool>.Binding,
      onBackspaceWhenEmpty: @escaping () -> Void
    ) {
      self.text = text
      self.isFocused = isFocused
      self.onBackspaceWhenEmpty = onBackspaceWhenEmpty
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? ComposerNSTextView else { return }
      text.wrappedValue = textView.string
      textView.applyInlineTokenStyles()
    }

    func textDidBeginEditing(_ notification: Notification) {
      isFocused.wrappedValue = true
    }
  }
}

private final class ComposerNSTextView: NSTextView {
  var onBackspaceWhenEmpty: (() -> Void)?
  var tokenColor: NSColor = .systemBlue
  var baseTextColor: NSColor = .labelColor
  var baseFont: NSFont = NSFont.systemFont(ofSize: 14)

  override func keyDown(with event: NSEvent) {
    if Int(event.keyCode) == 51 {
      if deleteInlineTokenBeforeCursor() {
        return
      }
      if string.isEmpty {
        onBackspaceWhenEmpty?()
        return
      }
    }
    super.keyDown(with: event)
  }

  func applyInlineTokenStyles() {
    guard let storage = textStorage else { return }
    let selectedRanges = self.selectedRanges
    let fullRange = NSRange(location: 0, length: storage.length)
    storage.beginEditing()
    storage.setAttributes([
      .foregroundColor: baseTextColor,
      .font: baseFont,
    ], range: fullRange)

    let pattern = #"(^|\s)([@/][^\s]+)"#
    if let regex = try? NSRegularExpression(pattern: pattern) {
      let text = storage.string as NSString
      regex.enumerateMatches(in: storage.string, range: fullRange) { match, _, _ in
        guard let tokenRange = match?.range(at: 2), tokenRange.location != NSNotFound else { return }
        storage.addAttributes([
          .foregroundColor: tokenColor,
          .font: baseFont,
        ], range: tokenRange)
      }
    }

    storage.endEditing()
    self.selectedRanges = selectedRanges
  }

  private func deleteInlineTokenBeforeCursor() -> Bool {
    let range = selectedRange()
    guard range.length == 0, range.location > 0 else { return false }

    let prefix = (string as NSString).substring(to: range.location)
    guard let regex = try? NSRegularExpression(pattern: #"(^|\s)([@/][^\s]+)\s*$"#) else {
      return false
    }
    let fullRange = NSRange(location: 0, length: (prefix as NSString).length)
    guard let match = regex.firstMatch(in: prefix, range: fullRange) else { return false }
    let tokenRange = match.range(at: 2)
    guard tokenRange.location != NSNotFound else { return false }

    var deleteRange = tokenRange
    if tokenRange.location > 0 {
      let previousLocation = tokenRange.location - 1
      let previous = (prefix as NSString).substring(with: NSRange(location: previousLocation, length: 1))
      if previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        deleteRange = NSRange(location: previousLocation, length: tokenRange.length + 1)
      }
    }

    textStorage?.deleteCharacters(in: deleteRange)
    setSelectedRange(NSRange(location: deleteRange.location, length: 0))
    didChangeText()
    applyInlineTokenStyles()
    return true
  }
}

private enum ComposerAttachmentMenuPage {
  case root
  case files
  case skills
  case mcpServers
}

/// Hosts the attachment picker in its own borderless panel. A separate panel is
/// required because content drawn inside the chat window cannot extend beyond
/// that window without covering the composer or response area.
private struct ComposerAttachmentPanelAnchor<MenuContent: View>: NSViewRepresentable {
  @Binding var isPresented: Bool
  let preferredWidth: CGFloat
  let menu: MenuContent

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    view.postsFrameChangedNotifications = true
    return view
  }

  func updateNSView(_ anchorView: NSView, context: Context) {
    if isPresented {
      context.coordinator.present(menu: menu, preferredWidth: preferredWidth, from: anchorView)
    } else {
      context.coordinator.dismiss()
    }
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.dismiss()
  }

  @MainActor
  final class Coordinator {
    private var panel: NSPanel?
    private weak var parentWindow: NSWindow?

    func present(menu: MenuContent, preferredWidth: CGFloat, from anchorView: NSView) {
      guard let window = anchorView.window else { return }

      let hostingView = NSHostingView(rootView: menu.padding(22))
      hostingView.layer?.backgroundColor = NSColor.clear.cgColor

      let menuPanel: NSPanel
      if let panel {
        menuPanel = panel
        menuPanel.contentView = hostingView
      } else {
        menuPanel = KeyablePanel(
          contentRect: .zero,
          styleMask: [.borderless],
          backing: .buffered,
          defer: false
        )
        menuPanel.isOpaque = false
        menuPanel.backgroundColor = .clear
        menuPanel.hasShadow = false
        menuPanel.hidesOnDeactivate = false
        menuPanel.isFloatingPanel = true
        menuPanel.becomesKeyOnlyIfNeeded = false
        menuPanel.level = window.level
        menuPanel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        menuPanel.contentView = hostingView
        panel = menuPanel
      }

      if parentWindow !== window {
        parentWindow?.removeChildWindow(menuPanel)
        window.addChildWindow(menuPanel, ordered: .above)
        parentWindow = window
      }

      hostingView.frame.size.width = preferredWidth + 44
      hostingView.layoutSubtreeIfNeeded()
      let fittingHeight = min(max(hostingView.fittingSize.height, 80), 390)
      menuPanel.setContentSize(NSSize(width: preferredWidth + 44, height: fittingHeight))
      position(menuPanel, relativeTo: anchorView)
      menuPanel.orderFront(nil)
    }

    func dismiss() {
      guard let panel else { return }
      parentWindow?.removeChildWindow(panel)
      panel.orderOut(nil)
      self.panel = nil
      parentWindow = nil
    }

    private func position(_ panel: NSPanel, relativeTo anchorView: NSView) {
      guard let window = anchorView.window else { return }
      let boundsInWindow = anchorView.convert(anchorView.bounds, to: nil)
      let boundsInScreen = window.convertToScreen(boundsInWindow)
      let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
      let panelSize = panel.frame.size

      // Align visual menu left (with 22pt transparent padding) to anchorView left with a 12pt visual inset:
      // origin.x + 22 = boundsInScreen.minX + 12 => origin.x = boundsInScreen.minX - 10
      var originX = boundsInScreen.minX - 10

      // Position the visual top of the menu to overlap just below the top of the input view (14pt overlay):
      // origin.y + panelSize.height - 22 = boundsInScreen.maxY - 14 => origin.y = boundsInScreen.maxY - panelSize.height + 8
      var originY = boundsInScreen.maxY - panelSize.height + 8

      originX = min(max(originX, visibleFrame.minX), visibleFrame.maxX - panelSize.width)
      originY = min(max(originY, visibleFrame.minY), visibleFrame.maxY - panelSize.height)
      panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
  }
}

/// Compact custom menu content rendered inside the detached attachment panel.
private struct ComposerAttachmentMenu: View {
  @Binding var page: ComposerAttachmentMenuPage
  let availableMCPAttachments: [ComposerMCPAttachment]
  let availableSkills: [SkillAttachment]
  let selectedMCPIds: Set<String>
  let selectedSkillIds: Set<String>
  let fileSearchQuery: String
  let onAttachFile: (URL) -> Void
  let onUpdateFileQuery: (String) -> Void
  let onAttachSkill: (SkillAttachment) -> Void
  let onAttachMCP: (ComposerMCPAttachment) -> Void
  let onDismiss: () -> Void

  @ObservedObject private var theme = ThemeManager.shared
  @State private var selectedRootIndex = 0
  @State private var selectedSkillIndex = 0
  @State private var selectedMCPIndex = 0
  @State private var keyMonitor: Any?

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      switch page {
      case .root:
        rootMenu
      case .files:
        fileMenu
      case .skills:
        skillMenu
      case .mcpServers:
        mcpMenu
      }
    }
    .padding(6)
    .frame(width: page == .files ? 320 : 280, alignment: .leading)
    .background(menuBackground)
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(theme.textColor.opacity(0.1), lineWidth: 0.5)
    }
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
    .onAppear(perform: setupKeyMonitor)
    .onDisappear(perform: removeKeyMonitor)
    .onChange(of: page) { _, _ in clampSelectionForCurrentPage() }
    .onChange(of: availableSkills.count) { _, _ in clampSelectionForCurrentPage() }
    .onChange(of: availableMCPAttachments.count) { _, _ in clampSelectionForCurrentPage() }
  }

  private var rootMenu: some View {
    Group {
      ComposerAttachmentMenuRow(
        title: "Files & Folders",
        subtitle: "Search and attach workspace files",
        systemImage: "doc.on.doc",
        isHighlighted: selectedRootIndex == 0,
        onHover: { selectedRootIndex = 0 }
      ) {
        page = .files
      }
      ComposerAttachmentMenuRow(
        title: "Installed Skills",
        subtitle: "Run custom AI workflows and skills",
        systemImage: "wand.and.stars",
        isHighlighted: selectedRootIndex == 1,
        onHover: { selectedRootIndex = 1 }
      ) {
        page = .skills
      }
      ComposerAttachmentMenuRow(
        title: "Connected MCP Servers",
        subtitle: "Interact with model context servers",
        systemImage: "server.rack",
        isHighlighted: selectedRootIndex == 2,
        onHover: { selectedRootIndex = 2 }
      ) {
        page = .mcpServers
      }
      ComposerAttachmentMenuRow(
        title: "Browser",
        subtitle: "Enable browser tools",
        systemImage: "globe",
        isSelected: selectedMCPIds.contains(ComposerMCPAttachment.browser.id),
        isHighlighted: selectedRootIndex == 3,
        onHover: { selectedRootIndex = 3 }
      ) {
        onAttachMCP(.browser)
      }
      ComposerAttachmentMenuRow(
        title: "macOS",
        subtitle: "Control native macOS apps",
        systemImage: "macwindow",
        isSelected: selectedMCPIds.contains(ComposerMCPAttachment.macOS.id),
        isHighlighted: selectedRootIndex == 4,
        onHover: { selectedRootIndex = 4 }
      ) {
        onAttachMCP(.macOS)
      }
      ComposerAttachmentMenuRow(
        title: "Secrets",
        subtitle: "Use saved credentials with Touch ID",
        systemImage: "lock.fill",
        isSelected: selectedMCPIds.contains(ComposerMCPAttachment.secrets.id),
        isHighlighted: selectedRootIndex == 5,
        onHover: { selectedRootIndex = 5 }
      ) {
        onAttachMCP(.secrets)
      }
    }
  }

  private var fileMenu: some View {
    InlineFileBrowser(
      query: fileSearchQuery,
      onBack: { page = .root },
      onUpdateQuery: onUpdateFileQuery,
      onSelect: onAttachFile
    )
  }

  private var skillMenu: some View {
    Group {
      ComposerAttachmentMenuHeader(title: "Installed Skills") { page = .root }
      if availableSkills.isEmpty {
        ComposerAttachmentMenuEmptyState(text: "No installed skills found")
      } else {
        ScrollView {
          VStack(spacing: 2) {
            ForEach(availableSkills) { skill in
              let index = availableSkills.firstIndex(where: { $0.id == skill.id }) ?? 0
              ComposerAttachmentMenuRow(
                title: skill.name,
                subtitle: skill.summary ?? skill.path,
                systemImage: "wand.and.stars",
                isSelected: selectedSkillIds.contains(skill.id),
                isHighlighted: selectedSkillIndex == index,
                onHover: { selectedSkillIndex = index }
              ) {
                onAttachSkill(skill)
              }
              .help(skill.summary ?? skill.path)
            }
          }
        }
        .frame(maxHeight: 232)
      }
    }
  }

  private var mcpMenu: some View {
    Group {
      ComposerAttachmentMenuHeader(title: "Connected MCP Servers") { page = .root }
      if availableMCPAttachments.isEmpty {
        ComposerAttachmentMenuEmptyState(text: "No connected MCP servers")
      } else {
        ScrollView {
          VStack(spacing: 2) {
            ForEach(availableMCPAttachments) { attachment in
              let index = availableMCPAttachments.firstIndex(where: { $0.id == attachment.id }) ?? 0
              ComposerAttachmentMenuRow(
                title: attachment.name,
                subtitle: attachment.detail,
                systemImage: attachment.systemImage,
                isSelected: selectedMCPIds.contains(attachment.id),
                isHighlighted: selectedMCPIndex == index,
                onHover: { selectedMCPIndex = index }
              ) {
                onAttachMCP(attachment)
              }
              .help(attachment.detail)
            }
          }
        }
        .frame(maxHeight: 232)
      }
    }
  }

  @ViewBuilder
  private var menuBackground: some View {
    if theme.usesGlassEffect {
      ZStack {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(.ultraThinMaterial)
        if let overlay = theme.glassOverlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(overlay)
        }
      }
    } else {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(theme.solidBackground)
    }
  }

  private func setupKeyMonitor() {
    guard keyMonitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      guard page != .files else { return event }
      let modifiers = event.modifierFlags.intersection([.command, .option, .control])
      guard modifiers.isEmpty else { return event }

      switch Int(event.keyCode) {
      case 125:
        moveSelection(by: 1)
        return nil
      case 126:
        moveSelection(by: -1)
        return nil
      case 36, 49, 76, 124:
        activateSelection()
        return nil
      case 53, 123:
        if page == .root {
          onDismiss()
          return nil
        }
        page = .root
        return nil
      default:
        return event
      }
    }
  }

  private func removeKeyMonitor() {
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
  }

  private func moveSelection(by delta: Int) {
    switch page {
    case .root:
      selectedRootIndex = clamped(selectedRootIndex + delta, count: 6)
    case .skills:
      selectedSkillIndex = clamped(selectedSkillIndex + delta, count: availableSkills.count)
    case .mcpServers:
      selectedMCPIndex = clamped(selectedMCPIndex + delta, count: availableMCPAttachments.count)
    case .files:
      break
    }
  }

  private func activateSelection() {
    switch page {
    case .root:
      switch selectedRootIndex {
      case 0: page = .files
      case 1: page = .skills
      case 2: page = .mcpServers
      case 3: onAttachMCP(.browser)
      case 4: onAttachMCP(.macOS)
      case 5: onAttachMCP(.secrets)
      default: break
      }
    case .skills:
      guard availableSkills.indices.contains(selectedSkillIndex) else { return }
      onAttachSkill(availableSkills[selectedSkillIndex])
    case .mcpServers:
      guard availableMCPAttachments.indices.contains(selectedMCPIndex) else { return }
      onAttachMCP(availableMCPAttachments[selectedMCPIndex])
    case .files:
      break
    }
  }

  private func clampSelectionForCurrentPage() {
    selectedRootIndex = clamped(selectedRootIndex, count: 6)
    selectedSkillIndex = clamped(selectedSkillIndex, count: availableSkills.count)
    selectedMCPIndex = clamped(selectedMCPIndex, count: availableMCPAttachments.count)
  }

  private func clamped(_ value: Int, count: Int) -> Int {
    guard count > 0 else { return 0 }
    return min(max(value, 0), count - 1)
  }
}

private struct ComposerSlashCommandMenu: View {
  let query: String
  let workflows: [QuickAction]
  let quickActions: [QuickAction]
  let onSelectAlias: (SlashCommandAlias) -> Void
  let onSelectAction: (QuickAction) -> Void
  let onCreateCommand: (String, String) -> Void
  let onOpenDestination: (ComposerCommandDestination) -> Void
  let onDismiss: () -> Void

  @ObservedObject private var theme = ThemeManager.shared
  @State private var selectedIndex = 0
  @State private var keyMonitor: Any?
  @State private var isCreatingCommand = false
  @State private var newCommandName = ""
  @State private var newCommandPrompt = ""
  @FocusState private var focusedCreateField: CreateCommandField?

  private enum CreateCommandField {
    case name
    case prompt
  }

  private var normalizedQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private var visibleItems: [SlashCommandMenuItem] {
    var items: [SlashCommandMenuItem] = []
    items.append(contentsOf: visibleWorkflows.map(SlashCommandMenuItem.workflow))
    items.append(contentsOf: visibleQuickActions.map(SlashCommandMenuItem.quickAction))
    items.append(contentsOf: visibleAliases.map(SlashCommandMenuItem.alias))
    items.append(contentsOf: visibleCreateItems)
    return items
  }

  private var visibleWorkflows: [QuickAction] {
    filtered(workflows.filter(\.enabled))
  }

  private var visibleQuickActions: [QuickAction] {
    filtered(quickActions.filter(\.enabled))
  }

  private var visibleAliases: [SlashCommandAlias] {
    SlashCommandAlias.defaults.filter { matches($0.command) || matches($0.title) || matches($0.subtitle) }
  }

  private var visibleDestinations: [SlashCommandDestinationItem] {
    SlashCommandDestinationItem.defaults.filter { matches($0.command) || matches($0.title) || matches($0.subtitle) }
  }

  private var visibleCreateItems: [SlashCommandMenuItem] {
    var items: [SlashCommandMenuItem] = []
    if matches("new command") || matches("create command") {
      items.append(.inlineCreateCommand)
    }
    items.append(contentsOf: visibleDestinations.map(SlashCommandMenuItem.destination))
    return items
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      if isCreatingCommand {
        createCommandForm
      } else if visibleItems.isEmpty {
        ComposerAttachmentMenuEmptyState(text: "No matching commands")
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            commandSection(
              title: "Workflows",
              items: visibleWorkflows.map(SlashCommandMenuItem.workflow)
            )
            commandSection(
              title: "Quick Actions",
              items: visibleQuickActions.map(SlashCommandMenuItem.quickAction)
            )
            commandSection(
              title: "Commands",
              items: visibleAliases.map(SlashCommandMenuItem.alias)
            )
            commandSection(
              title: "Create",
              items: visibleCreateItems
            )
          }
        }
        .frame(maxHeight: 338)
      }
    }
    .padding(6)
    .frame(width: 320, alignment: .leading)
    .background(menuBackground)
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(theme.textColor.opacity(0.1), lineWidth: 0.5)
    }
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
    .onAppear(perform: setupKeyMonitor)
    .onDisappear(perform: removeKeyMonitor)
    .onChange(of: query) { _, _ in clampSelection() }
    .onChange(of: workflows.count) { _, _ in clampSelection() }
    .onChange(of: quickActions.count) { _, _ in clampSelection() }
    .onChange(of: isCreatingCommand) { _, isCreating in
      clampSelection()
      if isCreating {
        DispatchQueue.main.async {
          focusedCreateField = .name
        }
      }
    }
  }

  private var createCommandForm: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Button(action: closeCreateCommandForm) {
          Image(systemName: "chevron.left")
            .font(.appFont(size: 11, weight: .semibold))
            .frame(width: 24, height: 28)
        }
        .buttonStyle(.plain)
        .help("Back")

        Text("New Command")
          .font(.appFont(size: 13, weight: .semibold))
        Spacer()
      }
      .foregroundColor(theme.textColor)
      .padding(.horizontal, 4)

      VStack(alignment: .leading, spacing: 8) {
        slashCommandTextField(
          title: "Name",
          text: $newCommandName,
          placeholder: "summarize",
          field: .name
        )
        slashCommandTextField(
          title: "Prompt",
          text: $newCommandPrompt,
          placeholder: "Summarize this clearly",
          field: .prompt
        )
      }

      HStack(spacing: 8) {
        Button("Cancel", action: closeCreateCommandForm)
          .buttonStyle(.plain)
          .font(.appFont(size: 12, weight: .medium))
          .foregroundColor(theme.secondaryTextColor)

        Spacer()

        Button(action: saveCommand) {
          HStack(spacing: 5) {
            Image(systemName: "plus")
            Text("Create")
          }
          .font(.appFont(size: 12, weight: .semibold))
          .foregroundColor(theme.backgroundColor)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(canSaveCommand ? theme.accentColor : theme.textColor.opacity(0.16))
          .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSaveCommand)
      }
      .padding(.horizontal, 4)
    }
    .padding(5)
  }

  private func slashCommandTextField(
    title: String,
    text: Binding<String>,
    placeholder: String,
    field: CreateCommandField
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.appFont(size: 11, weight: .medium))
        .foregroundColor(theme.secondaryTextColor)
      TextField(placeholder, text: text)
        .textFieldStyle(.plain)
        .font(.appFont(size: 13))
        .foregroundColor(theme.textColor)
        .focused($focusedCreateField, equals: field)
        .onSubmit {
          if field == .name {
            focusedCreateField = .prompt
          } else {
            saveCommand()
          }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(theme.textColor.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    .padding(.horizontal, 4)
  }

  @ViewBuilder
  private func commandSection(
    title: String,
    items: [SlashCommandMenuItem]
  ) -> some View {
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.appFont(size: 12, weight: .medium))
          .foregroundColor(theme.secondaryTextColor)
          .padding(.horizontal, 10)
          .padding(.top, 2)

        ForEach(items) { item in
          ComposerAttachmentMenuRow(
            title: item.title,
            subtitle: item.subtitle,
            systemImage: item.systemImage,
            isHighlighted: selectedIndex == globalIndex(for: item),
            onHover: {
              selectedIndex = globalIndex(for: item)
            }
          ) {
            activate(item)
          }
        }

      }
    }
  }

  @ViewBuilder
  private var menuBackground: some View {
    if theme.usesGlassEffect {
      ZStack {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(.ultraThinMaterial)
        if let overlay = theme.glassOverlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(overlay)
        }
      }
    } else {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(theme.solidBackground)
    }
  }

  private func filtered(_ actions: [QuickAction]) -> [QuickAction] {
    actions.filter { action in
      matches(action.title) || matches(action.prompt ?? "") || matches(action.shortcut ?? "")
    }
  }

  private func matches(_ text: String) -> Bool {
    normalizedQuery.isEmpty || text.lowercased().contains(normalizedQuery)
  }

  private func globalIndex(for item: SlashCommandMenuItem) -> Int {
    visibleItems.firstIndex(where: { $0.id == item.id }) ?? 0
  }

  private func setupKeyMonitor() {
    guard keyMonitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      guard !isCreatingCommand else { return event }
      let modifiers = event.modifierFlags.intersection([.command, .option, .control])
      guard modifiers.isEmpty else { return event }

      switch Int(event.keyCode) {
      case 125:
        moveSelection(by: 1)
        return nil
      case 126:
        moveSelection(by: -1)
        return nil
      case 36, 76:
        activateSelected()
        return nil
      case 53:
        onDismiss()
        return nil
      default:
        return event
      }
    }
  }

  private func removeKeyMonitor() {
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
  }

  private func moveSelection(by delta: Int) {
    guard !visibleItems.isEmpty else { return }
    selectedIndex = min(max(selectedIndex + delta, 0), visibleItems.count - 1)
  }

  private func clampSelection() {
    guard !visibleItems.isEmpty else {
      selectedIndex = 0
      return
    }
    selectedIndex = min(max(selectedIndex, 0), visibleItems.count - 1)
  }

  private func activateSelected() {
    guard visibleItems.indices.contains(selectedIndex) else { return }
    activate(visibleItems[selectedIndex])
  }

  private func activate(_ item: SlashCommandMenuItem) {
    switch item {
    case .inlineCreateCommand:
      isCreatingCommand = true
    case .workflow(let action), .quickAction(let action):
      onSelectAction(action)
    case .alias(let alias):
      onSelectAlias(alias)
    case .destination(let destination):
      onOpenDestination(destination.destination)
    }
  }

  private var canSaveCommand: Bool {
    !newCommandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !newCommandPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func saveCommand() {
    let name = newCommandName.trimmingCharacters(in: .whitespacesAndNewlines)
    let prompt = newCommandPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !prompt.isEmpty else { return }
    onCreateCommand(name, prompt)
  }

  private func closeCreateCommandForm() {
    isCreatingCommand = false
    newCommandName = ""
    newCommandPrompt = ""
  }
}

private enum SlashCommandMenuItem: Identifiable {
  case inlineCreateCommand
  case workflow(QuickAction)
  case quickAction(QuickAction)
  case alias(SlashCommandAlias)
  case destination(SlashCommandDestinationItem)

  var id: String {
    switch self {
    case .inlineCreateCommand:
      return "inline-create-command"
    case .workflow(let action):
      return "workflow:\(action.id)"
    case .quickAction(let action):
      return "quick-action:\(action.id)"
    case .alias(let alias):
      return "alias:\(alias.id)"
    case .destination(let destination):
      return "destination:\(destination.id)"
    }
  }

  var title: String {
    switch self {
    case .inlineCreateCommand:
      return "New Command"
    case .workflow(let action), .quickAction(let action):
      return action.title
    case .alias(let alias):
      return alias.title
    case .destination(let destination):
      return destination.title
    }
  }

  var subtitle: String? {
    switch self {
    case .inlineCreateCommand:
      return "Create a reusable command here"
    case .workflow(let action), .quickAction(let action):
      return action.prompt
    case .alias(let alias):
      return "/\(alias.command) - \(alias.subtitle)"
    case .destination(let destination):
      return destination.subtitle
    }
  }

  var systemImage: String {
    switch self {
    case .inlineCreateCommand:
      return "plus.circle"
    case .workflow(let action), .quickAction(let action):
      return action.systemImage ?? (action.kind == "workflow" ? "play.square.stack" : "bolt")
    case .alias(let alias):
      return alias.systemImage
    case .destination(let destination):
      return destination.systemImage
    }
  }
}

private struct SlashCommandDestinationItem: Identifiable {
  let id: String
  let command: String
  let title: String
  let subtitle: String
  let systemImage: String
  let destination: ComposerCommandDestination

  static let defaults: [SlashCommandDestinationItem] = [
    SlashCommandDestinationItem(
      id: "create-workflow",
      command: "create-workflow",
      title: "Create Workflow",
      subtitle: "Open the workflow builder",
      systemImage: "plus.square.on.square",
      destination: .createWorkflow
    ),
    SlashCommandDestinationItem(
      id: "create-quick-action",
      command: "create-quick-action",
      title: "Create Quick Action",
      subtitle: "Open the quick action builder",
      systemImage: "bolt.badge.plus",
      destination: .createQuickAction
    ),
    SlashCommandDestinationItem(
      id: "connect-mcp",
      command: "connect-mcp",
      title: "Connect MCP",
      subtitle: "Add a custom server or integration",
      systemImage: "server.rack",
      destination: .connectMCP
    ),
  ]
}

private struct ComposerAttachmentMenuRow: View {
  let title: String
  var subtitle: String? = nil
  let systemImage: String
  var isSelected = false
  var isHighlighted = false
  var onHover: (() -> Void)?
  let action: () -> Void

  @ObservedObject private var theme = ThemeManager.shared
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: systemImage)
          .font(.appFont(size: 14, weight: .medium))
          .foregroundColor(theme.textColor.opacity(0.7))
          .frame(width: 20)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.appFont(size: 13, weight: .semibold))
            .foregroundColor(theme.textColor)
            .lineLimit(1)

          if let subtitle = subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(.appFont(size: 11, weight: .regular))
              .foregroundColor(theme.secondaryTextColor)
              .lineLimit(1)
          }
        }

        Spacer(minLength: 8)

        if isSelected {
          Image(systemName: "checkmark")
            .font(.appFont(size: 11, weight: .semibold))
            .foregroundColor(theme.accentColor)
        }
      }
      .foregroundColor(theme.textColor)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(isHighlighted || isHovered ? theme.textColor.opacity(0.06) : .clear)
      }
    }
    .buttonStyle(.plain)
    .onHover {
      isHovered = $0
      if $0 { onHover?() }
    }
  }
}

private struct ComposerAttachmentMenuHeader: View {
  let title: String
  let onBack: () -> Void

  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(spacing: 8) {
      Button(action: onBack) {
        Image(systemName: "chevron.left")
          .font(.appFont(size: 11, weight: .semibold))
          .frame(width: 24, height: 28)
      }
      .buttonStyle(.plain)
      .help("Back")

      Text(title)
        .font(.appFont(size: 13, weight: .semibold))
      Spacer()
    }
    .foregroundColor(theme.textColor)
    .padding(.horizontal, 4)
    .padding(.bottom, 3)
  }
}

private struct ComposerAttachmentMenuEmptyState: View {
  let text: String

  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Text(text)
      .font(.appFont(size: 12))
      .foregroundColor(theme.secondaryTextColor)
      .frame(maxWidth: .infinity, minHeight: 72)
  }
}

private struct InlineFileBrowser: View {
  let query: String
  let onBack: () -> Void
  let onUpdateQuery: (String) -> Void
  let onSelect: (URL) -> Void

  @ObservedObject private var theme = ThemeManager.shared
  @State private var results: [InlineWorkspaceItem] = []
  @State private var selectedIndex = 0
  @State private var isSearching = false
  @State private var keyMonitor: Any?
  @State private var catalog = InlineWorkspaceCatalog.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 8) {
        Button(action: navigateBack) {
          Image(systemName: "chevron.left")
            .font(.appFont(size: 11, weight: .semibold))
            .frame(width: 24, height: 28)
        }
        .buttonStyle(.plain)
        .help("Back")

        Text("Files & Folders")
          .font(.appFont(size: 13, weight: .semibold))

        Spacer()

        if !query.isEmpty {
          Text("@\(query)")
            .font(.appFont(size: 11, weight: .medium))
            .foregroundColor(theme.secondaryTextColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.textColor.opacity(0.07))
            .clipShape(Capsule())
        }

        if isSearching {
          ProgressView()
            .controlSize(.mini)
            .help("Indexing your home directory")
        }
      }
      .foregroundColor(theme.textColor)
      .padding(.horizontal, 4)

      resultList
    }
    .padding(5)
    .onAppear {
      reload()
      setupKeyMonitor()
    }
    .onChange(of: query) { _, _ in reload() }
    .onDisappear {
      catalog.cancel()
      removeKeyMonitor()
    }
  }

  @ViewBuilder
  private var resultList: some View {
    if results.isEmpty && !isSearching {
      ContentUnavailableView(
        "No matching files",
        systemImage: "doc.text.magnifyingglass",
        description: Text(query.isEmpty ? "Browse folders in your home directory." : "The home directory is still being indexed, or try a shorter name.")
      )
      .frame(height: 294)
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 2) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
              InlineFileResultRow(item: item, isSelected: selectedIndex == index) {
                onSelect(item.url)
              }
              .id(item.id)
              .onHover { isHovering in
                if isHovering { selectedIndex = index }
              }
            }
          }
        }
        .onChange(of: selectedIndex) { _, newValue in
          guard results.indices.contains(newValue) else { return }
          withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(results[newValue].id, anchor: .center)
          }
        }
      }
      .frame(height: 294)
      .overlay {
        if isSearching && results.isEmpty {
          ProgressView().controlSize(.small)
        }
      }
    }
  }

  private func reload() {
    isSearching = true
    catalog.search(query: query) { found, isIndexing in
      results = found
      if found.isEmpty {
        selectedIndex = 0
      } else if !found.indices.contains(selectedIndex) {
        selectedIndex = 0
      } else {
        selectedIndex = min(selectedIndex, found.count - 1)
      }
      isSearching = isIndexing
    }
  }

  private func setupKeyMonitor() {
    guard keyMonitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let modifiers = event.modifierFlags.intersection([.command, .option, .control])
      guard modifiers.isEmpty else { return event }

      switch Int(event.keyCode) {
      case 125:
        moveSelection(by: 1)
        return nil
      case 126:
        moveSelection(by: -1)
        return nil
      case 36, 76:
        selectCurrent()
        return nil
      case 49:
        openCurrentDirectory()
        return nil
      case 53, 123:
        navigateBack()
        return nil
      default:
        return event
      }
    }
  }

  private func removeKeyMonitor() {
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
  }

  private func moveSelection(by delta: Int) {
    guard !results.isEmpty else { return }
    selectedIndex = min(max(selectedIndex + delta, 0), results.count - 1)
  }

  private func selectCurrent() {
    guard results.indices.contains(selectedIndex) else { return }
    onSelect(results[selectedIndex].url)
  }

  private func openCurrentDirectory() {
    guard results.indices.contains(selectedIndex) else { return }
    let item = results[selectedIndex]
    guard item.isDirectory else { return }
    onUpdateQuery(item.homeRelativeQueryPath + "/")
  }

  private func navigateBack() {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      onBack()
      return
    }

    let path = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let components = path.split(separator: "/", omittingEmptySubsequences: true)
    guard components.count > 1 else {
      onUpdateQuery("")
      return
    }

    onUpdateQuery(components.dropLast().joined(separator: "/") + "/")
  }
}

private struct InlineFileResultRow: View {
  let item: InlineWorkspaceItem
  let isSelected: Bool
  let onSelect: () -> Void

  @ObservedObject private var theme = ThemeManager.shared
  @State private var isHovered = false

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: 12) {
        Image(systemName: item.systemImage)
          .font(.appFont(size: 14, weight: .medium))
          .foregroundColor(item.isDirectory ? theme.accentColor : theme.textColor.opacity(0.7))
          .frame(width: 20)

        VStack(alignment: .leading, spacing: 2) {
          Text(item.name)
            .font(.appFont(size: 13, weight: .semibold))
            .foregroundColor(theme.textColor)
            .lineLimit(1)

          Text(item.relativePath)
            .font(.appFont(size: 11, weight: .regular))
            .foregroundColor(theme.secondaryTextColor)
            .lineLimit(1)
            .truncationMode(.middle)
        }

        Spacer(minLength: 8)
      }
      .foregroundColor(theme.textColor)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(isSelected || isHovered ? theme.textColor.opacity(0.06) : .clear)
      }
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }
}
