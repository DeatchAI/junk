import Foundation

extension FloatingChatInputView {
  var inlineSelections: [ComposerInlineSelection] {
    ComposerDraft(attachments: fileAttachments, contexts: textContexts, skills: selectedSkills,
      browserTabs: selectedBrowserTabs, mcpAttachments: selectedMCPAttachments, commands: selectedCommands).inlineSelections
  }

  var inlineTokens: [ComposerInlineToken] { inlineSelections.map(\.token) }

  var menuAnchorOffset: Int? {
    let offset = isSlashCommandMenuPresented ? slashTriggerOffset : mentionTriggerOffset
    guard let offset, offset <= inputText.count else { return nil }
    return inputText.prefix(offset).utf16.count
  }

  func prepareInlineSelections() {
    inlineSelections.forEach { knownInlineSelections[$0.token.id] = $0 }
    let updated = ComposerInlineToken.addingMissingFiles(to: inputText,
      attachments: fileAttachments, contexts: textContexts)
    if inputText != updated { inputText = updated }
  }

  func reconcileInlineSelections(in text: String) {
    let selections = inlineSelections
    selections.forEach { knownInlineSelections[$0.token.id] = $0 }
    for selection in selections where !ComposerInlineToken.contains(selection.token, in: text) {
      switch selection {
      case .file(let file): onRemoveFileAttachment(file)
      case .context(let context): onRemoveTextContext(context)
      case .skill(let skill): onRemoveSkill(skill)
      case .tab(let tab): onRemoveBrowserTab(tab)
      case .mcp(let mcp): onRemoveMCP(mcp)
      case .command(let command): onRemoveCommand(command)
      }
    }
    // Undo may restore a deleted pill. Restore its payload with the visible token.
    let selectedIDs = Set(selections.map { $0.token.id })
    for (id, selection) in knownInlineSelections where !selectedIDs.contains(id)
      && ComposerInlineToken.contains(selection.token, in: text) {
      switch selection {
      case .file(let file): onAttachAttachment(file)
      case .context(let context): onAttachTextContext(context)
      case .skill(let skill): onAttachSkill(skill)
      case .tab(let tab): onAttachBrowserTab(BrowserTab(id: tab.id, windowId: tab.windowId,
        active: tab.active, title: tab.title, url: tab.url))
      case .mcp(let mcp): onAttachMCP(mcp)
      case .command(let command): onAttachCommand(command)
      }
    }
  }
}
