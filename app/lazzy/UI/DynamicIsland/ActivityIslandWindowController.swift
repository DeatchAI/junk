import AppKit
import Combine
import SwiftUI

/// An always-on-top control surface for work that continues after the composer closes.
/// Frame changes follow task count and explicit inline selection, never streamed text.
@MainActor
final class ActivityIslandWindowController: NSObject, ObservableObject {
  static let activityRevealDuration: TimeInterval = 4
  private struct PendingFrameRequest {
    let expanded: Bool
    let animated: Bool
  }

  private struct PresentationPreferences: Equatable {
    let enabled = AppSettings.notchLiveActivitiesEnabled
    let placement = AppSettings.activityIslandPlacement
  }

  private var islandWindow: AgentQuestionPanel?
  private let runStore: DetachedRunStore
  private let controls: DetachedRunControls
  let interaction = ActivityIslandTaskState()
  private var completionDismissWorkItem: DispatchWorkItem?
  private var hoverCollapseWorkItem: DispatchWorkItem?
  private var pendingFrameRequest: PendingFrameRequest?
  private var cancellables = Set<AnyCancellable>()
  private var isPointerHovering = false
  private var isAnimatingFrame = false
  private var hasKeyboardInteraction = false
  private var activityVisibleUntil = Date.distantPast
  private var outsideClickMonitor: Any?
  private var localClickMonitor: Any?
  private var frameAnimationGeneration = 0

  @Published private(set) var isVisible = false
  @Published private(set) var isExpanded = false
  @Published private(set) var placement = AppSettings.activityIslandPlacement
  @Published private(set) var physicalNotchHeight: CGFloat = 40

  var onOpenConversation: ((String) -> Void)?
  var onApprovalResponse: ((String, Bool) -> Void)?

  init(runStore: DetachedRunStore, controls: DetachedRunControls) {
    self.runStore = runStore
    self.controls = controls
    super.init()
    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
      .map { _ in PresentationPreferences() }
      .prepend(PresentationPreferences())
      .removeDuplicates()
      .dropFirst()
      .receive(on: RunLoop.main)
      .sink { [weak self] preferences in
        self?.updatePreferences(enabled: preferences.enabled, placement: preferences.placement)
      }
      .store(in: &cancellables)
    NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.refreshVisibleFrame() }
      .store(in: &cancellables)
    runStore.$runs
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.refreshTasks()
      }
      .store(in: &cancellables)
    interaction.$expandedRunID.dropFirst()
      .receive(on: RunLoop.main)
      .sink { [weak self] id in
        guard let self else { return }
        if id == nil { self.hasKeyboardInteraction = false }
        if self.isVisible, self.isExpanded, let window = self.islandWindow {
          self.applyFrame(to: window, expanded: true, animated: true)
        }
        if id == nil && !self.isPointerHovering { self.setHovering(false) }
      }.store(in: &cancellables)
    interaction.$expandedInteractionHeight.removeDuplicates().dropFirst()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        guard let self, self.isVisible, self.isExpanded, let window = self.islandWindow else { return }
        self.applyFrame(to: window, expanded: true, animated: true)
      }.store(in: &cancellables)
  }

  deinit {
    if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
  }

  private func refreshTasks() {
    interaction.reconcile(runStore.presentationRuns)
    guard isVisible else { return }
    if hasPendingInterrupt {
      revealPendingInteraction()
      setExpanded(true, animated: true)
    }
    if runStore.presentationRuns.isEmpty && AgentQuestionCenter.shared.current == nil
      && !isPointerHovering && !hasKeyboardInteraction {
      hide()
      return
    }
    if isExpanded, let window = islandWindow { applyFrame(to: window, expanded: true, animated: true) }
    scheduleCompletionExpiry()
  }

  private func scheduleCompletionExpiry() {
    completionDismissWorkItem?.cancel()
    completionDismissWorkItem = nil
    guard let expiry = runStore.nextCompletionExpiry else { return }
    let refresh = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.runStore.objectWillChange.send()
      self.refreshTasks()
    }
    completionDismissWorkItem = refresh
    DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, expiry.timeIntervalSinceNow), execute: refresh)
  }

  private func updatePreferences(enabled: Bool, placement: ActivityIslandPlacement) {
    if self.placement != placement {
      resetPendingFrameWork()
      hoverCollapseWorkItem?.cancel()
      hoverCollapseWorkItem = nil
      isPointerHovering = false
      hasKeyboardInteraction = false
      interaction.collapse()
      self.placement = placement
    }
    guard enabled else {
      hide()
      return
    }
    if isVisible {
      refreshVisibleFrame()
      if interaction.expandedRunID == nil { setHovering(false) }
    } else if !runStore.presentationRuns.isEmpty || hasPendingInterrupt {
      present()
    }
  }

  private func refreshVisibleFrame() {
    guard isVisible, let window = islandWindow else { return }
    applyFrame(to: window, expanded: isExpanded)
  }

  func show() {
    activityVisibleUntil = Date.now.addingTimeInterval(Self.activityRevealDuration)
    present()
    guard isVisible else { return }
    revealPendingInteraction()
    setExpanded(true, animated: true)
    setHovering(false)
  }

  private func revealPendingInteraction() {
    interaction.reconcile(runStore.presentationRuns)
    guard interaction.expandedRunID == nil,
      let run = runStore.presentationRuns.first(where: \.needsAttention) else { return }
    interaction.select(run)
  }

  /// Debug previews must remain testable from the menu even if a floating chat
  /// happens to be open. This only changes presentation, never run state.
  func showDebugPreview() {
    show()
  }

  private func present() {
    guard AppSettings.notchLiveActivitiesEnabled else {
      hide()
      return
    }
    completionDismissWorkItem?.cancel()
    completionDismissWorkItem = nil
    guard !runStore.presentationRuns.isEmpty || AgentQuestionCenter.shared.current != nil else {
      hide()
      return
    }
    if islandWindow == nil { createWindow() }
    guard let window = islandWindow else { return }

    applyFrame(to: window, expanded: isExpanded, animated: isVisible)
    window.alphaValue = 1
    window.orderFrontRegardless()
    isVisible = true
    scheduleCompletionExpiry()
  }

  /// Lets the user register a successful background run, then removes the island
  /// once it is no longer carrying useful live state.
  func showCompletion() { show() }

  func showApproval() {
    // Reveal the actual request without making the panel key or replacing another draft.
    show()
  }

  func focusQuestion() {
    show()
    if let request = AgentQuestionCenter.shared.current,
      let run = runStore.presentationRuns.first(where: { $0.id == request.runId }) {
      interaction.select(run)
    }
    setExpanded(true, animated: true)
    focusForInteraction()
  }

  func focusForInteraction() {
    hoverCollapseWorkItem?.cancel()
    hoverCollapseWorkItem = nil
    hasKeyboardInteraction = true
    islandWindow?.allowsKeyFocus = true
    islandWindow?.makeKeyAndOrderFront(nil)
  }

  /// Makes the notch visible just before a composer animates into it. Returning
  /// the final panel frame lets the source panel use the same destination,
  /// producing a single continuous handoff rather than two unrelated fades.
  func beginComposerHandoff() -> NSRect? {
    guard AppSettings.notchLiveActivitiesEnabled else { return nil }
    guard runStore.hasActiveRuns else { return nil }
    if hasPendingInterrupt || interaction.expandedRunID != nil || activityVisibleUntil > .now {
      showApproval()
      return islandWindow?.frame
    }
    if islandWindow == nil { createWindow() }
    guard let window = islandWindow else { return nil }

    isExpanded = false
    applyFrame(to: window, expanded: false)
    window.alphaValue = 0
    window.orderFrontRegardless()
    isVisible = true

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      window.animator().alphaValue = 1
    }
    return window.frame
  }

  func hide() {
    activityVisibleUntil = .distantPast
    resetPendingFrameWork()
    hoverCollapseWorkItem?.cancel()
    hoverCollapseWorkItem = nil
    isPointerHovering = false
    hasKeyboardInteraction = false
    interaction.collapse()
    completionDismissWorkItem?.cancel()
    completionDismissWorkItem = nil
    isExpanded = false
    isVisible = false
    guard let window = islandWindow else { return }
    window.allowsKeyFocus = false
    window.orderOut(nil)
  }

  func toggleExpanded() {
    setExpanded(true, animated: true)
    focusForInteraction()
  }

  func setExpanded(_ expanded: Bool, animated: Bool) {
    guard isExpanded != expanded else { return }
    isExpanded = expanded
    guard let window = islandWindow else { return }
    if !expanded {
      window.allowsKeyFocus = false
      if window.isKeyWindow { window.resignKey() }
    }
    applyFrame(to: window, expanded: isExpanded, animated: animated)
    window.orderFrontRegardless()
  }

  func collapse() {
    hasKeyboardInteraction = false
    interaction.collapse()
    setExpanded(false, animated: true)
  }

  func setHovering(_ isHovering: Bool) {
    guard isVisible else { return }
    // SwiftUI replaces the compact/expanded subtree during a resize and can emit
    // synthetic exit/entry pairs. The native panel's screen bounds are authoritative.
    let isHovering = islandWindow.map { $0.frame.contains(NSEvent.mouseLocation) } ?? isHovering
    isPointerHovering = isHovering
    hoverCollapseWorkItem?.cancel()
    hoverCollapseWorkItem = nil

    if isHovering {
      setExpanded(true, animated: true)
      return
    }
    guard !hasPendingInterrupt, interaction.expandedRunID == nil && !hasKeyboardInteraction else { return }

    // Resizing the panel can briefly move the AppKit hover boundary. Waiting
    // through that handoff prevents a false exit/re-entry loop from making
    // the notch pulse forever.
    let collapse = DispatchWorkItem { [weak self] in
      guard let self, !self.isPointerHovering, !self.hasPendingInterrupt,
        self.activityVisibleUntil <= .now,
        self.interaction.expandedRunID == nil, !self.hasKeyboardInteraction else { return }
      self.setExpanded(false, animated: true)
    }
    hoverCollapseWorkItem = collapse
    let delay = max(0.32, activityVisibleUntil.timeIntervalSinceNow)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: collapse)
  }

  private func createWindow() {
    let screen = NSScreen.main ?? NSScreen.screens.first
    physicalNotchHeight = physicalNotchSize(for: screen).height
    let initialSize = panelFrame(for: screen, expanded: false).size
    let panel = AgentQuestionPanel(
      contentRect: NSRect(origin: .zero, size: initialSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    panel.isFloatingPanel = true
    panel.allowsKeyFocus = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    panel.hidesOnDeactivate = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.isMovable = false
    panel.ignoresMouseEvents = false

    let view = ActivityIslandView(
      store: runStore,
      controller: self,
      controls: controls,
      interaction: interaction,
      onToggle: { [weak self] in self?.toggleExpanded() },
      onOpenConversation: { [weak self] conversationId in
        self?.onOpenConversation?(conversationId)
      },
      onApprovalResponse: { [weak self] requestId, approved in
        // Keep the row and its busy state until the original runtime acknowledges the reply.
        self?.onApprovalResponse?(requestId, approved)
      }
    )
    let hostingView = NSHostingView(rootView: view)
    hostingView.sizingOptions = []
    hostingView.autoresizingMask = [.width, .height]
    panel.contentView = hostingView
    islandWindow = panel
    installOutsideClickMonitors()
  }

  private func installOutsideClickMonitors() {
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
      DispatchQueue.main.async { self?.collapseForOutsideClick() }
    }
    localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      guard let self else { return event }
      if event.window === self.islandWindow {
        self.focusForInteraction()
        return event
      }
      guard event.window !== self.islandWindow,
        event.window?.parent !== self.islandWindow,
        (event.window?.level.rawValue ?? 0) < NSWindow.Level.popUpMenu.rawValue else { return event }
      self.collapseForOutsideClick()
      return event
    }
  }

  private func collapseForOutsideClick() {
    guard isVisible, isExpanded, !hasPendingInterrupt, activityVisibleUntil <= .now,
      let window = islandWindow, !window.frame.contains(NSEvent.mouseLocation) else { return }
    collapse()
  }

  private func applyFrame(to window: NSWindow, expanded: Bool, animated: Bool = false) {
    if isAnimatingFrame {
      // The latest semantic state wins. In particular, an approval or Touch ID
      // interrupt must resize after a hover animation instead of being dropped.
      pendingFrameRequest = PendingFrameRequest(expanded: expanded, animated: animated)
      return
    }

    let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
    guard let screen else { return }
    let frame = panelFrame(for: screen, expanded: expanded)
    guard window.frame != frame else {
      frameUpdateDidSettle(on: window)
      return
    }
    guard animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      window.setFrame(frame, display: true)
      frameUpdateDidSettle(on: window)
      return
    }

    isAnimatingFrame = true
    frameAnimationGeneration &+= 1
    let generation = frameAnimationGeneration
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.24
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      context.allowsImplicitAnimation = true
      window.animator().setFrame(frame, display: true)
      context.completionHandler = { [weak self, weak window] in
        guard let self, let window, self.frameAnimationGeneration == generation else { return }
        self.isAnimatingFrame = false
        self.frameUpdateDidSettle(on: window)
      }
    }
  }

  private func frameUpdateDidSettle(on window: NSWindow) {
    if let pendingFrameRequest {
      self.pendingFrameRequest = nil
      applyFrame(
        to: window,
        expanded: pendingFrameRequest.expanded,
        animated: pendingFrameRequest.animated
      )
      return
    }
  }

  private func resetPendingFrameWork() {
    frameAnimationGeneration &+= 1
    pendingFrameRequest = nil
    isAnimatingFrame = false
  }

  private func panelFrame(for screen: NSScreen?, expanded: Bool) -> NSRect {
    let physicalNotch = physicalNotchSize(for: screen)
    if physicalNotchHeight != physicalNotch.height { physicalNotchHeight = physicalNotch.height }
    let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    return ActivityIslandLayout.frame(
      placement: placement,
      screenFrame: screenFrame,
      visibleFrame: screen?.visibleFrame ?? screenFrame,
      physicalNotch: physicalNotch,
      expanded: expanded,
      contentSize: sizeForExpandedState
    )
  }

  private var sizeForExpandedState: CGSize {
    let runs = runStore.presentationRuns
    let selected = runs.first { $0.id == interaction.expandedRunID }
    return ActivityIslandContentLayout.size(
      taskCount: runs.count,
      hasQuestion: selected?.state == .awaitingInput,
      hasApproval: selected?.approval != nil,
      hasCredential: selected?.credential != nil,
      sectionCount: Set(runs.map { ActivityIslandTaskState.section(for: $0) }).count,
      interactionHeight: interaction.expandedInteractionHeight
    )
  }

  private var hasPendingCredential: Bool {
    runStore.presentationRuns.contains { $0.credential != nil }
  }

  private var hasPendingInterrupt: Bool {
    runStore.hasPendingApproval || hasPendingCredential || AgentQuestionCenter.shared.current != nil
  }

  /// The compact state must occupy the hardware cutout exactly. Using the
  /// screen's safe-area height directly prevents the island from forming a
  /// second black lobe below the real MacBook notch.
  private func physicalNotchSize(for screen: NSScreen?) -> CGSize {
    guard let screen, screen.safeAreaInsets.top > 0 else {
      return CGSize(width: 460, height: 40)
    }

    let leftSafeAreaWidth = screen.auxiliaryTopLeftArea?.width ?? 0
    let rightSafeAreaWidth = screen.auxiliaryTopRightArea?.width ?? 0
    let measuredWidth = screen.frame.width - leftSafeAreaWidth - rightSafeAreaWidth + 4
    // Some macOS configurations omit the auxiliary top-area rectangles. Do
    // not mistake that for a notch spanning the entire display.
    let hasReliableAuxiliaryAreas = leftSafeAreaWidth > 0 && rightSafeAreaWidth > 0
    let isPlausibleNotchWidth = measuredWidth > 0 && measuredWidth < screen.frame.width * 0.5
    let width = hasReliableAuxiliaryAreas && isPlausibleNotchWidth ? measuredWidth : 460
    return CGSize(width: width, height: screen.safeAreaInsets.top)
  }
}
