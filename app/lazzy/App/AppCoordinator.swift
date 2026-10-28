import AppKit
import Combine
import Foundation
import SwiftUI

private enum OnboardingState {
  // Increment only when a new first-run flow must be shown to existing installs.
  static let currentVersion = 3
  static let completionVersionKey = "onboarding_completion_version"
}

/// Main coordinator that ties together all components
@MainActor
class AppCoordinator: ObservableObject {

  // MARK: - Components

  let serverLauncher = ServerLauncher()
  let floatingWorkspace = FloatingWindowWorkspaceController()
  let historyWindow = HistoryWindowController()
  let detachedRunStore = DetachedRunStore()
  let detachedRunControls = DetachedRunControls()
  lazy var activityIsland = ActivityIslandWindowController(runStore: detachedRunStore, controls: detachedRunControls)
  lazy var keepAwake = KeepAwakeController(runStore: detachedRunStore)
  let wsManager = WebSocketManager()
  let permissionsManager = PermissionsManager()
  let hotkeyManager = HotkeyManager.shared
  let voiceDictation = VoiceDictationController()
  let screenshotCapture = ScreenshotCaptureController()
  let onboardingWindow = OnboardingWindowController()

  // MARK: - State

  @Published private(set) var hasCompletedOnboarding: Bool

  var cancellables = Set<AnyCancellable>()
  var approvalManagers: [String: WebSocketManager] = [:]
  private var hasStartedCoreServices = false
  private var isObservingShortcutChanges = false
  weak var voiceTargetController: FloatingWindowController?

  static var shared: AppCoordinator?

  init() {
    hasCompletedOnboarding = UserDefaults.standard.integer(forKey: OnboardingState.completionVersionKey) >= OnboardingState.currentVersion
    Self.shared = self
    setupBindings()
    historyWindow.wsManager = wsManager
    configureFloatingWorkspace()
    setupVoiceDictation()
    setupActivityIslandCallbacks()
    AgentQuestionCenter.shared.configure(runStore: detachedRunStore, island: activityIsland)
    _ = keepAwake

    setupHistoryCallbacks()
    setupOnboardingCallbacks()
    setupPermissionCallbacks()
  }

  // MARK: - Setup

  // MARK: - Shortcut Management

  private func registerAllShortcuts() {
    hotkeyManager.updateShortcut(for: .floatingChat, shortcut: ShortcutSettings.floatingChat)
    hotkeyManager.updateShortcut(for: .closeComposer, shortcut: ShortcutSettings.closeComposer)
    hotkeyManager.updateShortcut(for: .resumeLastChat, shortcut: ShortcutSettings.resumeLastChat)
    hotkeyManager.updateShortcut(for: .history, shortcut: ShortcutSettings.historyPanel)
  }

  private func observeShortcutChanges() {
    guard !isObservingShortcutChanges else { return }
    isObservingShortcutChanges = true

    // Observe UserDefaults for shortcut changes
    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
      .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
      .sink { [weak self] _ in
        guard self?.hasCompletedOnboarding == true else { return }
        print("🔄 Shortcut settings changed - updating hotkeys")
        self?.registerAllShortcuts()
      }
      .store(in: &cancellables)
  }

  private func setupPermissionCallbacks() {
    NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.permissionsManager.checkPermissions()
      }
      .store(in: &cancellables)
  }

  func handleFinderFiles(_ urls: [URL]) {
    var seen = Set<String>()
    let attachments = urls.map(\.standardizedFileURL)
      .filter { seen.insert($0.path).inserted }
      .compactMap { AttachmentHelper.createAttachment(from: $0) }
    guard !attachments.isEmpty else { return }
    let content = DetectedContent(type: .files, text: nil, files: attachments.map(\.fileRequest))
    floatingWorkspace.openNewTask(at: NSEvent.mouseLocation, with: content)
  }

  func runWorkflow(_ workflow: SavedWorkflow) {
    guard let prompt = workflow.prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }

    let location = NSEvent.mouseLocation
    let task = floatingWorkspace.openNewTask(at: location)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      task.wsManager.sendChat(
        text: prompt,
        displayText: prompt,
        files: [],
        conversationId: task.wsManager.currentConversationId,
        zeroDataRetention: AISettings.zeroDataRetention,
        actionId: workflow.id,
        mcpServerIds: workflow.mcpServerIds ?? [],
        skills: workflow.skills,
        agent: task.controller.selectedAgent,
        model: task.controller.selectedModel,
        modelSettings: task.controller.selectedModelSettings
      )
    }
  }

  // MARK: - Control

  /// Drives local notch previews without starting an agent or spending tokens.
  func showNotchDebugScenario(_ scenario: NotchDebugScenario) {
    #if DEBUG
    AgentQuestionCenter.shared.clearDebugPreview()
    #endif
    detachedRunStore.showDebugScenario(scenario)
    #if DEBUG
    if scenario == .question { AgentQuestionCenter.shared.showDebugPreview(); return }
    #endif
    if scenario == .clear {
      activityIsland.hide()
    } else if detachedRunStore.hasPendingApproval {
      activityIsland.showApproval()
    } else {
      // Debug samples intentionally bypass the normal composer visibility
      // rule so every Notch Debug menu item is immediately testable.
      activityIsland.showDebugPreview()
    }
  }

  /// Start coordinating (call on app launch)
  func start() {
    if !hasCompletedOnboarding {
      onboardingWindow.show()
    } else {
      performCoreStart()
    }
  }

  func resetOnboarding() {
    UserDefaults.standard.removeObject(forKey: OnboardingState.completionVersionKey)
    hasCompletedOnboarding = false
    hotkeyManager.deactivateAllShortcuts()
    stop()
    hasStartedCoreServices = false
    DispatchQueue.main.async {
      MenuBarContentView.settingsWindowController?.window?.close()
      MenuBarContentView.settingsWindowController = nil
      self.onboardingWindow.show()
    }
  }

  /// The original core start logic (permissions, monitoring, server connection)
  private func performCoreStart() {
    guard hasCompletedOnboarding else { return }
    guard !hasStartedCoreServices else { return }
    hasStartedCoreServices = true
    keepAwake.resume()
    registerAllShortcuts()
    observeShortcutChanges()
    permissionsManager.checkPermissions()

    serverLauncher.onServerReady = { [weak self] in
      self?.wsManager.connect()
    }
    serverLauncher.start()

    print("🚀 Detach coordinator started")
  }

  // MARK: - Onboarding Setup

  private func setupOnboardingCallbacks() {
    onboardingWindow.onComplete = { [weak self] in
      self?.completeOnboarding()
    }
  }

  private func completeOnboarding() {
    UserDefaults.standard.set(OnboardingState.currentVersion, forKey: OnboardingState.completionVersionKey)
    hasCompletedOnboarding = true
    onboardingWindow.close()

    // Start the app normally
    performCoreStart()
  }

  /// Stop monitoring
  func stop() {
    keepAwake.suspend()
    wsManager.disconnect()
    serverLauncher.stop()
    voiceDictation.stop()
    print("🛑 App coordinator stopped")
  }

  /// Opens a new task for the user's configured New Floating Chat shortcut.
  func openNewFloatingTask() {
    let location = NSEvent.mouseLocation
    _ = floatingWorkspace.openNewTask(at: location)
  }

  /// Restores the last focused task without replacing its conversation or
  /// current stream. Starting from a clean workspace creates the first task.
  func resumeLastFloatingTask() {
    let location = NSEvent.mouseLocation
    if !floatingWorkspace.showLastActiveTask(at: location) {
      _ = floatingWorkspace.openNewTask(at: location)
    }
  }

  func openFirstAgentTask(agent: String) {
    let task = floatingWorkspace.openNewTask(at: NSEvent.mouseLocation)
    task.controller.selectedAgent = agent
    task.controller.selectedModel = DetachSettings.selectedModel(for: agent)
    task.controller.selectedModelSettings = DetachSettings.modelSettings(
      for: agent,
      model: task.controller.selectedModel
    )
    task.controller.initialDraftText = "Reply with one short sentence confirming you can respond. Do not read or change files or use tools."
  }

  /// Toggle the history panel
  func toggleHistoryPanel() {
    historyWindow.toggle()
  }

  // MARK: - History Panel Setup

  private func setupHistoryCallbacks() {
    // When user selects a conversation from history
    historyWindow.onSelectConversation = { [weak self] conversation in
      guard let self = self else { return }

      // Reopen history in a new task so it cannot replace an active composer.
      let location = NSEvent.mouseLocation
      self.floatingWorkspace.openConversation(conversation.id, at: location)
    }

    // When user wants to start a new conversation
    historyWindow.onNewConversation = { [weak self] in
      guard let self = self else { return }

      // History's new-chat action also creates an independent floating task.
      let location = NSEvent.mouseLocation
      self.floatingWorkspace.openNewTask(at: location)
    }
  }

  // MARK: - System Automation Setup

  /// Store reference to command approval window
  static var commandApprovalWindowController: NSWindowController?

  private func setupSystemAutomationCallbacks() {
    // When server sends a command approval request
    wsManager.onCommandApprovalRequest = { [weak self] id, runId, conversationId, command, description, riskLevel in
      guard let self = self else { return }

      DispatchQueue.main.async {
        self.detachedRunStore.requestApproval(
          id: id,
          runId: runId,
          conversationId: conversationId,
          command: command,
          description: description,
          riskLevel: riskLevel
        )
        self.activityIsland.showApproval()
      }
    }
  }

  private func showCommandApprovalWindow(
    requestId: String,
    command: String,
    description: String,
    riskLevel: String
  ) {
    NSApp.activate(ignoringOtherApps: true)

    // Close any existing approval window
    if let existing = Self.commandApprovalWindowController {
      existing.window?.close()
      Self.commandApprovalWindowController = nil
    }

    // Create the approval view
    let approvalView = CommandApprovalView(
      requestId: requestId,
      command: command,
      description: description,
      riskLevel: riskLevel,
      onApprove: { [weak self] in
        self?.wsManager.sendCommandApprovalResponse(requestId: requestId, approved: true)
        Self.commandApprovalWindowController?.window?.close()
        Self.commandApprovalWindowController = nil
      },
      onDeny: { [weak self] in
        self?.wsManager.sendCommandApprovalResponse(requestId: requestId, approved: false)
        Self.commandApprovalWindowController?.window?.close()
        Self.commandApprovalWindowController = nil
      }
    )

    // Create window
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 450, height: 350),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Command Approval"
    window.backgroundColor = .clear
    window.isOpaque = false
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.contentView = NSHostingView(rootView: approvalView)

    // Center and show
    let controller = NSWindowController(window: window)
    Self.commandApprovalWindowController = controller

    window.center()
    controller.showWindow(nil)
  }
}
