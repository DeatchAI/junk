import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

struct FloatingChatInputView: View {
  @Binding var inputText: String
  @Binding var debugMenuStep: DebugComposerMenuStep?
  var isInputFocused: FocusState<Bool>.Binding
  @ObservedObject var controller: FloatingWindowController
  var onClose: () -> Void
  var onSubmit: () -> Void
  var onPasteAttachment: () -> Bool
  let fileAttachments: [ChatAttachment]
  var textContexts: [DetectedContent] = []
  var onRemoveTextContext: (DetectedContent) -> Void = { _ in }
  var onAttachTextContext: (DetectedContent) -> Void = { _ in }
  var editorDocumentID: UUID? = nil
  let selectedSkills: [SkillAttachment]
  let selectedBrowserTabs: [BrowserTabAttachment]
  let selectedMCPAttachments: [ComposerMCPAttachment]
  let selectedCommands: [SlashCommandAlias]
  let availableMCPAttachments: [ComposerMCPAttachment]
  let isLoadingMCPAttachments: Bool
  let availableSkills: [SkillAttachment]
  let workflows: [SavedWorkflow]
  let commands: [CustomSlashCommand]
  @Binding var isAttachmentMenuRequested: Bool
  @Binding var isAttachmentMenuActive: Bool
  @Binding var isCommandMenuActive: Bool
  @ObservedObject var skillsDirectory: SkillsDirectoryService
  @ObservedObject var workingDirectoryStore: WorkingDirectoryStore
  @ObservedObject var browserTabStore: BrowserTabStore
  @ObservedObject var conversationStore: ComposerConversationStore
  let currentConversationID: String?
  var onAttachFile: (URL) -> Void
  var onAttachAttachment: (ChatAttachment) -> Void
  var onRemoveFileAttachment: (ChatAttachment) -> Void
  var onAttachSkill: (SkillAttachment) -> Void
  var onAttachBrowserTab: (BrowserTab) -> Void
  var onRefreshBrowserTabs: () -> Void
  var onAttachMCP: (ComposerMCPAttachment) -> Void
  var onOpenMCPServers: () -> Void
  var onAttachCommand: (SlashCommandAlias) -> Void
  var onCreateCommand: (String, String) -> Void
  var onRunCommandAction: (SavedWorkflow) -> Void
  var onOpenCommandDestination: (ComposerCommandDestination) -> Void
  var onRemoveSkill: (SkillAttachment) -> Void
  var onRemoveBrowserTab: (BrowserTabAttachment) -> Void
  var onRemoveMCP: (ComposerMCPAttachment) -> Void
  var onRemoveCommand: (SlashCommandAlias) -> Void
  var selectedAction: String = "Ask your agent… @ context · / commands"
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
  @State var knownInlineSelections: [String: ComposerInlineSelection] = [:]
  @State var menuCaretRect: NSRect?

  var body: some View {
    VStack(spacing: 8) {
        if FeatureFlags.voiceModeEnabled && voiceDictationState != .idle {
          voiceStatus
        }

        HStack(alignment: .top, spacing: 8) {
          VStack(alignment: .leading, spacing: 10) {
            if fileAttachments.contains(where: \.canPreviewMedia) {
              ComposerAttachmentList(attachments: fileAttachments.filter(\.canPreviewMedia), onRemove: onRemoveFileAttachment)
            }
            editor
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          ComposerWindowControls(controller: controller, onClose: onClose)
        }
    }
    .background {
      attachmentPanel
    }
    .background {
      commandPanel
    }
    .padding(.horizontal, 18)
    .padding(.top, 18)
    .padding(.bottom, 10)
    .onChange(of: inputText) { oldValue, newValue in
      updateAttachmentMenuTrigger(for: newValue, previousValue: oldValue)
      updateSlashCommandTrigger(for: newValue, previousValue: oldValue)
      reconcileInlineSelections(in: newValue)
    }
    .onChange(of: inlineTokens) { _, _ in prepareInlineSelections() }
    .onChange(of: editorDocumentID) { _, _ in
      knownInlineSelections = [:]
      prepareInlineSelections()
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
      if !isPresented {
        conversationStore.cancelSearch()
        conversationStore.cancelAttachment()
      }
    }
    .onChange(of: currentConversationID) { _, _ in dismissAttachmentMenu() }
    .onChange(of: controller.isVisible) { _, visible in
      if !visible { dismissAttachmentMenu() }
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
      conversationStore.cancelSearch()
      conversationStore.cancelAttachment()
    }
    .onAppear {
      prepareInlineSelections()
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
    .onChange(of: workingDirectoryStore.remoteWorkspace) { _, target in
      fileCatalog.setWorkingDirectory(target == nil ? workingDirectoryStore.url : nil)
      if target != nil && attachmentMenuPage == .files { attachmentMenuPage = .root }
    }
  }

  private var editor: some View {
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
              tokens: inlineTokens,
              documentID: editorDocumentID,
              menuAnchorOffset: menuAnchorOffset,
              onCaretRectChange: { menuCaretRect = $0 },
              onSubmit: onSubmit,
              onPasteAttachment: onPasteAttachment,
              onBackspaceWhenEmpty: removeLastInlineToken,
              onFileDrop: attachDroppedFiles,
              onImageDrop: attachDroppedImage,
              onRemoteURLDrop: attachDroppedRemoteURL
            )
              .frame(height: max(editorHeight, 40))
          }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var attachmentPanel: some View {
      ComposerAttachmentPanelAnchor(
        isPresented: $isAttachmentMenuPresented,
        preferredWidth: attachmentMenuPage == .files
          || attachmentMenuPage == .browserTabs
          || attachmentMenuPage == .conversations
          || attachmentMenuPage == .discoverSkills
          || attachmentMenuPage == .remoteSkillDetail ? ComposerMenuStyle.detailWidth : ComposerMenuStyle.rootWidth,
        caretRect: menuCaretRect,
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
          conversationStore: conversationStore,
          selectedConversationIDs: Set(fileAttachments.compactMap(\.conversationID)),
          currentConversationID: currentConversationID,
          selectedMCPIds: Set(selectedMCPAttachments.map(\.id)),
          selectedSkillIds: Set(selectedSkills.map(\.id)),
          selectedBrowserTabIds: Set(selectedBrowserTabs.map(\.id)),
          skillsSearchQuery: skillsSearchQuery,
          onAttachBrowserTab: completeBrowserTabAttachment,
          onAttachConversation: completeConversationAttachment,
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

  private var commandPanel: some View {
      ComposerAttachmentPanelAnchor(
        isPresented: $isSlashCommandMenuPresented,
        preferredWidth: ComposerMenuStyle.commandWidth,
        caretRect: menuCaretRect,
        contentRefreshID: AnyHashable(slashCommandQuery),
        menu: ComposerSlashCommandMenu(
          query: slashCommandQuery,
          workflows: workflows,
          commands: commands,
          onSelectAlias: completeSlashAlias,
          onSelectAction: completeSlashAction,
          onCreateCommand: completeCreateCommand,
          onOpenDestination: completeSlashDestination,
          onDismiss: dismissSlashCommandMenu
        )
      )
  }
}
