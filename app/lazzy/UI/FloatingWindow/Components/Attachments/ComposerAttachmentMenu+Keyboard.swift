import AppKit
import SwiftUI

extension ComposerAttachmentMenu {
  func setupKeyMonitor() {
    guard keyMonitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      // Keep ordinary typing in the composer, including spaces in chat searches.
      guard page != .files else { return event }
      let modifiers = event.modifierFlags.intersection([.command, .option, .control])
      guard modifiers.isEmpty else { return event }
      if page == .conversations && [49, 124].contains(Int(event.keyCode)) { return event }

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

  func removeKeyMonitor() {
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
  }

  func moveSelection(by delta: Int) {
    switch page {
    case .root:
      selectedRootIndex = clamped(selectedRootIndex + delta, count: 9)
    case .browserTabs:
      selectedBrowserTabIndex = clamped(selectedBrowserTabIndex + delta, count: browserTabStore.tabs.count)
    case .conversations:
      selectedConversationIndex = clamped(selectedConversationIndex + delta, count: visibleConversations.count)
    case .skills:
      selectedSkillIndex = clamped(selectedSkillIndex + delta, count: availableSkills.count)
    case .mcpServers:
      selectedMCPIndex = clamped(selectedMCPIndex + delta, count: availableMCPAttachments.count)
    case .discoverSkills:
      selectedRemoteSkillIndex = clamped(selectedRemoteSkillIndex + delta, count: visibleRemoteSkills.count)
    case .files, .remoteSkillDetail:
      break
    }
  }

  func activateSelection() {
    switch page {
    case .root:
      switch selectedRootIndex {
      case 0: page = .files
      case 1: page = .browserTabs
      case 2: page = .conversations
      case 3: page = .skills
      case 4:
        openSkillsDirectory()
      case 5: page = .mcpServers
      case 6: onAttachMCP(.browser)
      case 7: onAttachMCP(.macOS)
      case 8: onAttachMCP(.secrets)
      default: break
      }
    case .browserTabs:
      guard browserTabStore.tabs.indices.contains(selectedBrowserTabIndex) else { return }
      onAttachBrowserTab(browserTabStore.tabs[selectedBrowserTabIndex])
    case .conversations:
      guard visibleConversations.indices.contains(selectedConversationIndex), !conversationStore.isAttaching else { return }
      let conversation = visibleConversations[selectedConversationIndex]
      guard !selectedConversationIDs.contains(conversation.id) else { return }
      onAttachConversation(conversation)
    case .skills:
      guard availableSkills.indices.contains(selectedSkillIndex) else { return }
      onAttachSkill(availableSkills[selectedSkillIndex])
    case .mcpServers:
      guard availableMCPAttachments.indices.contains(selectedMCPIndex) else { return }
      onAttachMCP(availableMCPAttachments[selectedMCPIndex])
    case .discoverSkills:
      guard visibleRemoteSkills.indices.contains(selectedRemoteSkillIndex) else { return }
      openRemoteSkill(visibleRemoteSkills[selectedRemoteSkillIndex])
    case .files, .remoteSkillDetail:
      break
    }
  }

  func clampSelectionForCurrentPage() {
    selectedRootIndex = clamped(selectedRootIndex, count: 9)
    selectedBrowserTabIndex = clamped(selectedBrowserTabIndex, count: browserTabStore.tabs.count)
    selectedConversationIndex = clamped(selectedConversationIndex, count: visibleConversations.count)
    selectedSkillIndex = clamped(selectedSkillIndex, count: availableSkills.count)
    selectedMCPIndex = clamped(selectedMCPIndex, count: availableMCPAttachments.count)
    selectedRemoteSkillIndex = clamped(selectedRemoteSkillIndex, count: visibleRemoteSkills.count)
  }

  func openSkillsDirectory() {
    skillsDirectory.clearError()
    skillsDirectory.search(query: skillsSearchQuery)
    page = .discoverSkills
  }

  func openRemoteSkill(_ skill: RemoteSkill) {
    selectedRemoteSkill = skill
    skillsDirectory.clearError()
    page = .remoteSkillDetail
  }

  func clamped(_ value: Int, count: Int) -> Int {
    guard count > 0 else { return 0 }
    return min(max(value, 0), count - 1)
  }
}
