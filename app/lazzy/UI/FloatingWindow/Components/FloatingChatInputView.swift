import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

struct FloatingChatInputView: View {
  @Binding var inputText: String
  @Binding var debugMenuStep: DebugComposerMenuStep?
  var isInputFocused: FocusState<Bool>.Binding
  var onClose: () -> Void
  var onSubmit: () -> Void
  var onPasteAttachment: () -> Bool
  let fileAttachments: [ChatAttachment]
  let selectedSkills: [SkillAttachment]
  let selectedBrowserTabs: [BrowserTabAttachment]
  let selectedMCPAttachments: [ComposerMCPAttachment]
  let selectedCommands: [SlashCommandAlias]
  let availableMCPAttachments: [ComposerMCPAttachment]
  let isLoadingMCPAttachments: Bool
  let availableSkills: [SkillAttachment]
  let workflows: [QuickAction]
  let quickActions: [QuickAction]
  @Binding var isAttachmentMenuRequested: Bool
  @Binding var isAttachmentMenuActive: Bool
  @Binding var isCommandMenuActive: Bool
  @ObservedObject var skillsDirectory: SkillsDirectoryService
  @ObservedObject var workingDirectoryStore: WorkingDirectoryStore
  @ObservedObject var browserTabStore: BrowserTabStore
  var onAttachFile: (URL) -> Void
  var onAttachSkill: (SkillAttachment) -> Void
  var onAttachBrowserTab: (BrowserTab) -> Void
  var onRefreshBrowserTabs: () -> Void
  var onAttachMCP: (ComposerMCPAttachment) -> Void
  var onOpenMCPServers: () -> Void
  var onAttachCommand: (SlashCommandAlias) -> Void
  var onCreateCommand: (String, String) -> Void
  var onRunCommandAction: (QuickAction) -> Void
  var onOpenCommandDestination: (ComposerCommandDestination) -> Void
  var onRemoveFile: (ChatAttachment) -> Void
  var onRemoveSkill: (SkillAttachment) -> Void
  var onRemoveBrowserTab: (BrowserTabAttachment) -> Void
  var onRemoveMCP: (ComposerMCPAttachment) -> Void
  var onRemoveCommand: (SlashCommandAlias) -> Void
  var selectedAction: String = "Anything .."
  let voiceDictationState: VoiceDictationState
  let voicePartialTranscript: String

  @ObservedObject var theme = ThemeManager.shared
  @State var isAttachmentMenuPresented = false
  @State var isSlashCommandMenuPresented = false
  @State var attachmentMenuPage: ComposerAttachmentMenuPage = .root
  @State var mentionTriggerOffset: Int?
  @State var slashTriggerOffset: Int?
  @State var editorHeight: CGFloat = 24
  @StateObject var fileCatalog = InlineWorkspaceCatalog()

  var body: some View {
    VStack(spacing: 8) {
        if FeatureFlags.voiceModeEnabled && voiceDictationState != .idle {
          voiceStatus
        }

        HStack(alignment: .top, spacing: 8) {
          ZStack(alignment: .topLeading) {
            if inputText.isEmpty {
              Text(selectedAction)
                .foregroundColor(theme.secondaryTextColor)
                .padding(.horizontal, 5)
            }

            InlineComposerTextEditor(
              text: $inputText,
              measuredHeight: $editorHeight,
              isFocused: isInputFocused,
              textColor: NSColor(theme.textColor),
              tokenColor: NSColor(theme.accentColor),
              font: AppFont.nsFont(size: 14),
              onSubmit: onSubmit,
              onPasteAttachment: onPasteAttachment,
              onBackspaceWhenEmpty: removeLastInlineToken,
              onFileDrop: attachDroppedFiles,
              onImageDrop: attachDroppedImage,
              onRemoteURLDrop: attachDroppedRemoteURL
            )
              .frame(height: editorHeight)
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
        preferredWidth: attachmentMenuPage == .files
          || attachmentMenuPage == .browserTabs
          || attachmentMenuPage == .discoverSkills
          || attachmentMenuPage == .remoteSkillDetail ? 320 : 280,
        contentRefreshID: attachmentMenuContentRefreshID,
        menu: ComposerAttachmentMenu(
          page: $attachmentMenuPage,
          availableMCPAttachments: availableMCPAttachments,
          isLoadingMCPAttachments: isLoadingMCPAttachments,
          availableSkills: availableSkills,
          skillsDirectory: skillsDirectory,
          fileCatalog: fileCatalog,
          workingDirectoryStore: workingDirectoryStore,
          browserTabStore: browserTabStore,
          selectedMCPIds: Set(selectedMCPAttachments.map(\.id)),
          selectedSkillIds: Set(selectedSkills.map(\.id)),
          selectedBrowserTabIds: Set(selectedBrowserTabs.map(\.id)),
          skillsSearchQuery: skillsSearchQuery,
          onAttachBrowserTab: completeBrowserTabAttachment,
          onRefreshBrowserTabs: onRefreshBrowserTabs,
          onAttachFile: completeFileAttachment,
          onUpdateFileQuery: replaceMentionQuery,
          onChooseWorkingDirectory: chooseWorkingDirectory,
          onChooseFromMac: chooseFilesFromMac,
          onAttachSkill: completeSkillAttachment,
          onAttachMCP: completeMCPAttachment,
          onOpenMCPServers: onOpenMCPServers,
          onDismiss: dismissAttachmentMenu
        )
      )
    }
    .background {
      ComposerAttachmentPanelAnchor(
        isPresented: $isSlashCommandMenuPresented,
        preferredWidth: 320,
        contentRefreshID: AnyHashable(slashCommandQuery),
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
    .onChange(of: debugMenuStep) { _, step in
      performDebugMenuStep(step)
    }
    .onDisappear {
      isAttachmentMenuActive = false
      isCommandMenuActive = false
    }
    .onAppear {
      fileCatalog.setWorkingDirectory(workingDirectoryStore.url)
    }
    .onChange(of: workingDirectoryStore.url) { _, directory in
      fileCatalog.setWorkingDirectory(directory)
      if directory == nil && attachmentMenuPage == .files {
        attachmentMenuPage = .root
      } else if attachmentMenuPage == .files {
        fileCatalog.search(query: mentionSearchQuery)
      }
    }
  }

}
