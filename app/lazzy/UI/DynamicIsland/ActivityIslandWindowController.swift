import AppKit
import Combine
import SwiftUI

/// An always-on-top control surface for work that continues after the composer closes.
/// Its frame changes only when the user opens or closes the island, never for streaming
/// activity updates, which avoids AppKit/SwiftUI sizing feedback during tool bursts.
@MainActor
final class ActivityIslandWindowController: NSObject, ObservableObject {
  private struct PendingFrameRequest {
    let expanded: Bool
    let animated: Bool
  }

  private var islandWindow: NSPanel?
  private let runStore: DetachedRunStore
  private var completionDismissWorkItem: DispatchWorkItem?
  private var hoverCollapseWorkItem: DispatchWorkItem?
  private var approvalShakeWorkItems: [DispatchWorkItem] = []
  private var approvalShakeRestingFrame: NSRect?
  private var pendingFrameRequest: PendingFrameRequest?
  private var cancellables = Set<AnyCancellable>()
  private var isDismissedByUser = false
  private var isSuppressedByVisibleComposer = false
  private var isPointerHovering = false
  private var isAnimatingFrame = false
  private var isShakingApproval = false
  private var shouldShakeForInterrupt = false
  private var frameAnimationGeneration = 0
  private var approvalShakeGeneration = 0

  @Published private(set) var isVisible = false
  @Published private(set) var isExpanded = false

  var onOpenConversation: ((String) -> Void)?
  var onApprovalResponse: ((String, Bool) -> Void)?

  private var physicalNotchHeight: CGFloat = 40
  /// The compact controls retain their existing 48pt inset, while this extra
  /// lane moves each one 16pt beyond the opaque camera cutout.
  private let compactSideLaneWidth: CGFloat = 96

  init(runStore: DetachedRunStore) {
    self.runStore = runStore
    super.init()
    runStore.$runs
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        guard let self, self.isVisible, self.isExpanded, let window = self.islandWindow else { return }
        self.applyFrame(to: window, expanded: true)
      }
      .store(in: &cancellables)
  }

  func show() {
    present(ignoringComposerVisibility: false)
  }

  /// Debug previews must remain testable from the menu even if a floating chat
  /// happens to be open. This only changes presentation, never run state.
  func showDebugPreview() {
    isDismissedByUser = false
    present(ignoringComposerVisibility: true)
  }

  private func present(ignoringComposerVisibility: Bool) {
    completionDismissWorkItem?.cancel()
    completionDismissWorkItem = nil
    guard !isSuppressedByVisibleComposer || ignoringComposerVisibility else {
      hideForVisibleComposer()
      return
    }
    guard !isDismissedByUser else { return }
    guard !runStore.presentationRuns.isEmpty else {
      hide()
      return
    }
    if islandWindow == nil { createWindow() }
    guard let window = islandWindow else { return }

    applyFrame(to: window, expanded: isExpanded)
    window.alphaValue = 1
    window.orderFrontRegardless()
    isVisible = true
  }

  /// Lets the user register a successful background run, then removes the island
  /// once it is no longer carrying useful live state.
  func showCompletion(for duration: TimeInterval = 4) {
    show()
    guard isVisible else { return }

    let dismissal = DispatchWorkItem { [weak self] in
      guard let self, !self.runStore.hasActiveRuns else { return }
      self.hide()
    }
    completionDismissWorkItem = dismissal
    DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: dismissal)
  }

  func showApproval() {
    isDismissedByUser = false
    // Approval and credential requests are interrupts: they must be visible
    // even while the originating chat is open, otherwise a waiting agent looks stuck.
    isExpanded = true
    shouldShakeForInterrupt = true
    present(ignoringComposerVisibility: true)
    startInterruptShakeIfReady()
  }

  /// Makes the notch visible just before a composer animates into it. Returning
  /// the final panel frame lets the source panel use the same destination,
  /// producing a single continuous handoff rather than two unrelated fades.
  func beginComposerHandoff() -> NSRect? {
    guard runStore.hasActiveRuns, !isDismissedByUser else { return nil }
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

  /// A floating chat already carries the full streamed activity. Keep the
  /// island out of the way until the user closes every visible composer.
  func setComposerVisible(_ isVisible: Bool) {
    guard isSuppressedByVisibleComposer != isVisible else { return }
    isSuppressedByVisibleComposer = isVisible
    if isVisible {
      if runStore.hasPendingApproval || hasPendingCredential {
        showApproval()
      } else {
        hideForVisibleComposer()
      }
    } else if runStore.hasActiveRuns {
      show()
    }
  }

  /// Keep the island hidden for the current task after an explicit dismissal.
  /// Starting another task, or an approval request, deliberately makes it visible again.
  func dismiss() {
    isDismissedByUser = true
    hide()
  }

  func prepareForNewRun() {
    isDismissedByUser = false
  }

  func hide() {
    stopApprovalShake()
    resetPendingFrameWork()
    hoverCollapseWorkItem?.cancel()
    hoverCollapseWorkItem = nil
    isPointerHovering = false
    completionDismissWorkItem?.cancel()
    completionDismissWorkItem = nil
    isExpanded = false
    isVisible = false
    guard let window = islandWindow else { return }
    window.orderOut(nil)
  }

  /// Unlike a user dismissal, this is a reversible presentation rule. It
  /// intentionally does not set the dismissed flag or discard run state.
  private func hideForVisibleComposer() {
    stopApprovalShake()
    resetPendingFrameWork()
    hoverCollapseWorkItem?.cancel()
    hoverCollapseWorkItem = nil
    isPointerHovering = false
    completionDismissWorkItem?.cancel()
    completionDismissWorkItem = nil
    isExpanded = false
    isVisible = false
    islandWindow?.orderOut(nil)
  }

  func toggleExpanded() {
    setExpanded(true, animated: true)
  }

  func setExpanded(_ expanded: Bool, animated: Bool) {
    guard isExpanded != expanded else { return }
    isExpanded = expanded
    guard let window = islandWindow else { return }
    applyFrame(to: window, expanded: isExpanded, animated: animated)
    if isExpanded {
      window.makeKeyAndOrderFront(nil)
    } else {
      window.orderFrontRegardless()
    }
  }

  func collapse() {
    setExpanded(false, animated: true)
  }

  func setHovering(_ isHovering: Bool) {
    guard isVisible, !isSuppressedByVisibleComposer else { return }
    isPointerHovering = isHovering
    hoverCollapseWorkItem?.cancel()
    hoverCollapseWorkItem = nil

    if isHovering {
      setExpanded(true, animated: true)
      return
    }

    // Resizing the panel can briefly move the AppKit hover boundary. Waiting
    // through that handoff prevents a false exit/re-entry loop from making
    // the notch pulse forever.
    let collapse = DispatchWorkItem { [weak self] in
      guard let self, !self.isPointerHovering else { return }
      self.setExpanded(false, animated: true)
    }
    hoverCollapseWorkItem = collapse
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: collapse)
  }

  private func createWindow() {
    let screen = NSScreen.main ?? NSScreen.screens.first
    physicalNotchHeight = physicalNotchSize(for: screen).height
    let initialSize = panelSize(for: screen, expanded: false)
    let panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: initialSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    panel.isFloatingPanel = true
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
      physicalNotchHeight: physicalNotchHeight,
      onToggle: { [weak self] in self?.toggleExpanded() },
      onDismiss: { [weak self] in self?.dismiss() },
      onOpenConversation: { [weak self] conversationId in
        self?.onOpenConversation?(conversationId)
      },
      onApprovalResponse: { [weak self] requestId, approved in
        self?.runStore.resolveApproval(id: requestId)
        self?.onApprovalResponse?(requestId, approved)
      }
    )
    let hostingView = NSHostingView(rootView: view)
    hostingView.sizingOptions = []
    hostingView.autoresizingMask = [.width, .height]
    panel.contentView = hostingView
    islandWindow = panel
  }

  private func applyFrame(to window: NSWindow, expanded: Bool, animated: Bool = false) {
    if isAnimatingFrame || isShakingApproval {
      // The latest semantic state wins. In particular, an approval or Touch ID
      // interrupt must resize after a hover animation instead of being dropped.
      pendingFrameRequest = PendingFrameRequest(expanded: expanded, animated: animated)
      return
    }

    let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
    guard let screen else { return }
    let size = panelSize(for: screen, expanded: expanded)
    let frame = NSRect(
      x: screen.frame.midX - size.width / 2,
      y: screen.frame.maxY - size.height,
      width: size.width,
      height: size.height
    )
    guard window.frame != frame else {
      frameUpdateDidSettle(on: window)
      return
    }
    guard animated else {
      window.setFrame(frame, display: true)
      frameUpdateDidSettle(on: window)
      return
    }

    isAnimatingFrame = true
    frameAnimationGeneration &+= 1
    let generation = frameAnimationGeneration
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.28
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
    startInterruptShakeIfReady()
  }

  private func resetPendingFrameWork() {
    frameAnimationGeneration &+= 1
    pendingFrameRequest = nil
    isAnimatingFrame = false
    shouldShakeForInterrupt = false
  }

  private func startInterruptShakeIfReady() {
    guard shouldShakeForInterrupt,
      isVisible,
      !isAnimatingFrame,
      !isShakingApproval,
      pendingFrameRequest == nil
    else { return }

    shouldShakeForInterrupt = false
    shakeForApproval()
  }

  /// A brief lateral nudge makes an approval perceptible without turning the
  /// notch into a notification banner or repeatedly moving it during updates.
  private func shakeForApproval() {
    stopApprovalShake()
    guard let window = islandWindow else { return }
    let restingFrame = window.frame
    let offsets: [CGFloat] = [-6, 6, -4, 4, -2, 2, 0]
    approvalShakeRestingFrame = restingFrame
    isShakingApproval = true
    approvalShakeGeneration &+= 1
    let generation = approvalShakeGeneration

    for (index, offset) in offsets.enumerated() {
      let workItem = DispatchWorkItem { [weak self, weak window] in
        guard let self, let window, self.approvalShakeGeneration == generation else { return }
        var frame = restingFrame
        frame.origin.x += offset
        window.setFrame(frame, display: true)
        if index == offsets.count - 1 {
          self.isShakingApproval = false
          self.approvalShakeRestingFrame = nil
          self.approvalShakeWorkItems.removeAll()
          self.frameUpdateDidSettle(on: window)
        }
      }
      approvalShakeWorkItems.append(workItem)
      DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.055, execute: workItem)
    }
  }

  private func stopApprovalShake() {
    approvalShakeGeneration &+= 1
    approvalShakeWorkItems.forEach { $0.cancel() }
    approvalShakeWorkItems.removeAll()
    if let approvalShakeRestingFrame, let window = islandWindow {
      window.setFrame(approvalShakeRestingFrame, display: true)
    }
    approvalShakeRestingFrame = nil
    isShakingApproval = false
  }

  private func panelSize(for screen: NSScreen?, expanded: Bool) -> CGSize {
    let physicalNotch = physicalNotchSize(for: screen)
    guard expanded else {
      return CGSize(
        width: physicalNotch.width + (compactSideLaneWidth * 2),
        // The first notch-height is physically obscured by the camera. The
        // second is the visible compact activity lane beneath it.
        height: physicalNotch.height * 2
      )
    }

    let contentSize = sizeForExpandedState
    let availableWidth = max(360, (screen?.visibleFrame.width ?? contentSize.width) - 48)
    let compactWidth = physicalNotch.width + (compactSideLaneWidth * 2)
    return CGSize(
      width: min(max(contentSize.width, compactWidth), availableWidth),
      height: physicalNotch.height + contentSize.height
    )
  }

  private var sizeForExpandedState: CGSize {
    if runStore.hasPendingApproval || hasPendingCredential {
      return CGSize(width: 560, height: 70)
    }
    let taskCount = min(max(runStore.presentationRuns.count, 1), 5)
    let dividerCount = max(taskCount - 1, 0)
    return CGSize(
      width: 560,
      height: min(380, 36 + CGFloat(taskCount * 64 + dividerCount))
    )
  }

  private var hasPendingCredential: Bool {
    runStore.presentationRuns.contains { $0.credential != nil }
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
