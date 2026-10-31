import AppKit
import SwiftUI

struct ComposerAttachmentMenu: View {
  @Binding var page: ComposerAttachmentMenuPage
  let availableMCPAttachments: [ComposerMCPAttachment]
  let isLoadingMCPAttachments: Bool
  let availableSkills: [SkillAttachment]
  @ObservedObject var skillsDirectory: SkillsDirectoryService
  @ObservedObject var fileCatalog: InlineWorkspaceCatalog
  @ObservedObject var workingDirectoryStore: WorkingDirectoryStore
  @ObservedObject var browserTabStore: BrowserTabStore
  @ObservedObject var conversationStore: ComposerConversationStore
  let selectedConversationIDs: Set<String>
  let currentConversationID: String?
  let selectedMCPIds: Set<String>
  let selectedSkillIds: Set<String>
  let selectedBrowserTabIds: Set<Int>
  let skillsSearchQuery: String
  let onAttachBrowserTab: (BrowserTab) -> Void
  let onAttachConversation: (Conversation) -> Void
  let onRefreshBrowserTabs: () -> Void
  let onAttachFile: (URL) -> Void
  let onUpdateFileQuery: (String) -> Void
  let onChooseWorkingDirectory: () -> Void
  let onChooseFromMac: () -> Void
  let onAttachSkill: (SkillAttachment) -> Void
  let onAttachMCP: (ComposerMCPAttachment) -> Void
  let onOpenMCPServers: () -> Void
  let onDismiss: () -> Void

  @ObservedObject private var theme = ThemeManager.shared
  @State var selectedRootIndex = 0
  @State var selectedBrowserTabIndex = 0
  @State var selectedConversationIndex = 0
  @State var selectedSkillIndex = 0
  @State var selectedMCPIndex = 0
  @State var selectedRemoteSkillIndex = 0
  @State var selectedRemoteSkill: RemoteSkill?
  @State var keyMonitor: Any?

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      switch page {
      case .root:
        ScrollViewReader { proxy in
          ScrollView {
            VStack(spacing: 1) { rootMenu }
          }.frame(height: 9 * ComposerMenuStyle.rowHeight + 8)
            .onChange(of: selectedRootIndex) { _, index in proxy.scrollTo(index) }
        }
      case .files:
        fileMenu
      case .browserTabs:
        browserTabsMenu
      case .conversations:
        ComposerConversationsMenu(page: $page, store: conversationStore,
          conversations: visibleConversations, selectedIDs: selectedConversationIDs,
          selectedIndex: $selectedConversationIndex, onAttach: onAttachConversation)
      case .skills:
        skillMenu
      case .discoverSkills:
        discoverSkillsMenu
      case .remoteSkillDetail:
        remoteSkillDetail
      case .mcpServers:
        mcpMenu
      }
    }
    .composerMenuSurface(width: page == .files || page == .browserTabs || page == .conversations
      || page == .discoverSkills || page == .remoteSkillDetail ? ComposerMenuStyle.detailWidth : ComposerMenuStyle.rootWidth)
    .onAppear(perform: setupKeyMonitor)
    .onDisappear(perform: removeKeyMonitor)
    .onChange(of: page) { _, newPage in
      if newPage == .mcpServers {
        onOpenMCPServers()
      }
      if newPage == .browserTabs {
        onRefreshBrowserTabs()
      }
      if newPage == .conversations {
        conversationStore.search(skillsSearchQuery, immediately: true)
      } else {
        conversationStore.cancelSearch()
        conversationStore.cancelAttachment()
      }
      clampSelectionForCurrentPage()
    }
    .onChange(of: availableSkills.count) { _, _ in clampSelectionForCurrentPage() }
    .onChange(of: availableMCPAttachments.count) { _, _ in clampSelectionForCurrentPage() }
    .onChange(of: browserTabStore.tabs) { _, _ in clampSelectionForCurrentPage() }
    .onChange(of: conversationStore.contentRevision) { _, _ in clampSelectionForCurrentPage() }
    .onChange(of: skillsDirectory.searchResults) { _, _ in clampSelectionForCurrentPage() }
    .onChange(of: skillsSearchQuery) { _, _ in
      selectedRemoteSkillIndex = 0
      selectedConversationIndex = 0
      clampSelectionForCurrentPage()
    }
  }

  private var rootMenu: some View {
    Group {
      ComposerAttachmentMenuRow(
        title: "Files & Folders",
        subtitle: workingDirectoryStore.isRemote
          ? "The remote agent can read files in its project"
          : workingDirectoryStore.url == nil
          ? "Choose a file or folder from Finder"
          : "Search files in \(workingDirectoryStore.displayName)",
        systemImage: "doc.on.doc",
        showsSubmenu: !workingDirectoryStore.isRemote && workingDirectoryStore.url != nil,
        isHighlighted: selectedRootIndex == 0,
        isEnabled: !workingDirectoryStore.isRemote,
        onHover: { selectedRootIndex = 0 }
      ) {
        if workingDirectoryStore.url == nil {
          onChooseFromMac()
        } else {
          page = .files
        }
      }
      .id(0)
      ComposerAttachmentMenuRow(
        title: "Tabs",
        subtitle: workingDirectoryStore.isRemote
          ? "Browser tabs are available for local runs"
          : "Attach open tabs from Chrome",
        systemImage: "rectangle.on.rectangle",
        showsSubmenu: !workingDirectoryStore.isRemote,
        isHighlighted: selectedRootIndex == 1,
        isEnabled: !workingDirectoryStore.isRemote,
        onHover: { selectedRootIndex = 1 }
      ) {
        page = .browserTabs
      }
      .id(1)
      ComposerAttachmentMenuRow(
        title: "Past conversations",
        subtitle: "Attach context from a previous chat",
        systemImage: "bubble.left.and.bubble.right",
        showsSubmenu: true,
        isHighlighted: selectedRootIndex == 2,
        onHover: { selectedRootIndex = 2 }
      ) {
        page = .conversations
      }
      .id(2)
      ComposerAttachmentMenuRow(
        title: "Installed Skills",
        subtitle: "Run custom AI workflows and skills",
        systemImage: "wand.and.stars",
        showsSubmenu: true,
        isHighlighted: selectedRootIndex == 3,
        onHover: { selectedRootIndex = 3 }
      ) {
        page = .skills
      }
      .id(3)
      ComposerAttachmentMenuRow(
        title: "Discover Skills",
        subtitle: "Browse popular skills or search with @",
        systemImage: "magnifyingglass",
        showsSubmenu: true,
        isHighlighted: selectedRootIndex == 4,
        onHover: { selectedRootIndex = 4 }
      ) {
        openSkillsDirectory()
      }
      .id(4)
      ComposerAttachmentMenuRow(
        title: "Connected MCP Servers",
        subtitle: "Interact with model context servers",
        systemImage: "server.rack",
        showsSubmenu: true,
        isHighlighted: selectedRootIndex == 5,
        onHover: { selectedRootIndex = 5 }
      ) {
        page = .mcpServers
      }
      .id(5)
      ComposerAttachmentMenuRow(
        title: "Browser",
        subtitle: "Enable browser tools",
        systemImage: "globe",
        isSelected: selectedMCPIds.contains(ComposerMCPAttachment.browser.id),
        isHighlighted: selectedRootIndex == 6,
        onHover: { selectedRootIndex = 6 }
      ) {
        onAttachMCP(.browser)
      }
      .id(6)
      ComposerAttachmentMenuRow(
        title: "macOS",
        subtitle: "Control native macOS apps",
        systemImage: "macwindow",
        isSelected: selectedMCPIds.contains(ComposerMCPAttachment.macOS.id),
        isHighlighted: selectedRootIndex == 7,
        onHover: { selectedRootIndex = 7 }
      ) {
        onAttachMCP(.macOS)
      }
      .id(7)
      ComposerAttachmentMenuRow(
        title: "Secrets",
        subtitle: "Use saved credentials with Touch ID",
        systemImage: "lock.fill",
        isSelected: selectedMCPIds.contains(ComposerMCPAttachment.secrets.id),
        isHighlighted: selectedRootIndex == 8,
        onHover: { selectedRootIndex = 8 }
      ) {
        onAttachMCP(.secrets)
      }
      .id(8)
    }
  }

  var visibleConversations: [Conversation] {
    conversationStore.conversations.filter { $0.id != currentConversationID }
  }

  private var fileMenu: some View {
    InlineFileBrowser(
      catalog: fileCatalog,
      onBack: { page = .root },
      onUpdateQuery: onUpdateFileQuery,
      onChooseWorkingDirectory: onChooseWorkingDirectory,
      onChooseFromMac: onChooseFromMac,
      onSelect: onAttachFile
    )
  }

  private var browserTabsMenu: some View {
    ComposerBrowserTabsMenu(
      page: $page,
      store: browserTabStore,
      selectedTabIds: selectedBrowserTabIds,
      selectedIndex: $selectedBrowserTabIndex,
      onAttach: onAttachBrowserTab,
      onRefresh: onRefreshBrowserTabs
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
      if isLoadingMCPAttachments {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Loading MCP servers…")
            .font(.appFont(size: 12))
            .foregroundColor(theme.secondaryTextColor)
        }
        .frame(maxWidth: .infinity, minHeight: availableMCPAttachments.isEmpty ? 72 : 0)
      }

      if availableMCPAttachments.isEmpty && !isLoadingMCPAttachments {
        ComposerAttachmentMenuEmptyState(text: "No connected MCP servers")
      } else if !availableMCPAttachments.isEmpty {
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

  private var discoverSkillsMenu: some View {
    Group {
      ComposerAttachmentMenuHeader(title: "Discover Skills") {
        skillsDirectory.search(query: "")
        page = .root
      }

      let normalizedQuery = skillsSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
      if normalizedQuery.count < 2 {
        Text("Trending skills")
          .font(.appFont(size: 11, weight: .semibold))
          .foregroundColor(theme.secondaryTextColor)
          .padding(.horizontal, 4)
          .padding(.top, 3)

        ScrollView {
          VStack(spacing: 2) {
            ForEach(Array(visibleRemoteSkills.enumerated()), id: \.element.id) { index, skill in
              remoteSkillRow(skill, index: index)
            }
          }
        }
        .frame(maxHeight: 236)
      } else if !skillsDirectory.searchResults.isEmpty {
        if skillsDirectory.isSearching {
          HStack(spacing: 6) {
            ProgressView()
              .controlSize(.mini)
            Text("Refreshing…")
              .font(.appFont(size: 10))
              .foregroundColor(theme.secondaryTextColor)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 4)
          .padding(.top, 3)
        }

        ScrollView {
          VStack(spacing: 2) {
            ForEach(Array(visibleRemoteSkills.enumerated()), id: \.element.id) { index, skill in
              remoteSkillRow(skill, index: index)
            }
          }
        }
        .frame(maxHeight: 236)
      } else if skillsDirectory.isSearching {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Searching skills.sh…")
            .font(.appFont(size: 12))
            .foregroundColor(theme.secondaryTextColor)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
      } else if skillsDirectory.searchResults.isEmpty {
        ComposerAttachmentMenuEmptyState(text: "No skills found")
      } else {
        ScrollView {
          VStack(spacing: 2) {
            ForEach(Array(visibleRemoteSkills.enumerated()), id: \.element.id) { index, skill in
              remoteSkillRow(skill, index: index)
            }
          }
        }
        .frame(maxHeight: 236)
      }

      if let errorMessage = skillsDirectory.errorMessage {
        Text(errorMessage)
          .font(.appFont(size: 10))
          .foregroundColor(.red.opacity(0.85))
          .lineLimit(4)
          .padding(.horizontal, 4)
          .padding(.top, 3)
      }
    }
  }

  var visibleRemoteSkills: [RemoteSkill] {
    let normalizedQuery = skillsSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalizedQuery.count < 2
      ? SkillsDirectoryService.featuredSkills
      : skillsDirectory.searchResults
  }

  private func remoteSkillRow(_ skill: RemoteSkill, index: Int) -> some View {
    ComposerAttachmentMenuRow(
      title: skill.name,
      subtitle: [skill.source, skill.formattedInstalls]
        .filter { !$0.isEmpty }
        .joined(separator: " · "),
      systemImage: "wand.and.stars",
      isHighlighted: selectedRemoteSkillIndex == index,
      onHover: { selectedRemoteSkillIndex = index }
    ) {
      openRemoteSkill(skill)
    }
    .help("Open " + skill.name)
  }

  private var remoteSkillDetail: some View {
    Group {
      ComposerAttachmentMenuHeader(title: selectedRemoteSkill?.name ?? "Skill") {
        page = .discoverSkills
      }

      if let skill = selectedRemoteSkill {
        VStack(alignment: .leading, spacing: 10) {
          Text(skill.source)
            .font(.appFont(size: 12, weight: .medium))
            .foregroundColor(theme.textColor)

          if !skill.formattedInstalls.isEmpty {
            Label(skill.formattedInstalls, systemImage: "arrow.down.circle")
              .font(.appFont(size: 11))
              .foregroundColor(theme.secondaryTextColor)
          }

          HStack(spacing: 8) {
            let isInstalling = skillsDirectory.installingSkillID == skill.id
            let installedAttachment = skillsDirectory.installedSkill(for: skill)
            let isInstalled = installedAttachment != nil

            if let detailURL = skill.detailURL {
              Button("View on skills.sh") {
                NSWorkspace.shared.open(detailURL)
              }
              .buttonStyle(.plain)
              .font(.appFont(size: 11, weight: .medium))
              .foregroundColor(theme.accentColor)
            }

            Spacer()

            Button(action: { installRemoteSkill(skill) }) {
              HStack(spacing: 5) {
                if isInstalling {
                  ProgressView()
                    .controlSize(.small)
                } else if isInstalled {
                  Image(systemName: "checkmark.circle.fill")
                } else {
                  Image(systemName: "arrow.down.circle")
                }
                Text(
                  isInstalling
                    ? "Installing…"
                    : isInstalled ? "Attach" : "Install & Attach"
                )
              }
              .font(.appFont(size: 12, weight: .semibold))
              .foregroundColor(theme.backgroundColor)
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(
                isInstalling
                  ? theme.accentColor.opacity(0.62)
                  : theme.accentColor
              )
              .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(skillsDirectory.installingSkillID != nil)
          }

          if let errorMessage = skillsDirectory.errorMessage {
            Text(errorMessage)
              .font(.appFont(size: 10))
              .foregroundColor(.red.opacity(0.85))
              .lineLimit(6)
          }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
      } else {
        ComposerAttachmentMenuEmptyState(text: "Select a skill to continue")
      }
    }
  }

  private func installRemoteSkill(_ skill: RemoteSkill) {
    if let installedAttachment = skillsDirectory.installedSkill(for: skill) {
      onAttachSkill(installedAttachment)
      self.selectedRemoteSkill = nil
      page = .skills
      return
    }

    Task { @MainActor in
      let result = await skillsDirectory.install(skill)
      guard case .success(let attachment) = result else { return }
      onAttachSkill(attachment)
      self.selectedRemoteSkill = nil
      page = .skills
    }
  }


}
