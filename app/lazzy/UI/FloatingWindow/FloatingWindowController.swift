import AppKit
import Combine
import Foundation
import SwiftUI
struct VoiceDictationInsertion: Equatable {
  let id = UUID()
  let text: String
}
/// Controller for the floating AI chat window
class FloatingWindowController: NSObject, ObservableObject, NSWindowDelegate {
#if DEBUG
  private static weak var debugPointerTarget: FloatingWindowController?
#endif

  private(set) var chatWindow: NSPanel?
  let taskId = UUID()
  @Published var initialDraftText: String?
  @Published private(set) var isVisible = false
  @Published private(set) var isFrontmost = false
  @Published var isExpanded = false
  @Published private(set) var expandedContentHeight: CGFloat = 600
  @Published var selectedAgent: String
  @Published var selectedModel: String?
  @Published var selectedModelSettings: AgentModelSettings?
  @Published private(set) var voiceDictationState: VoiceDictationState = .idle
  @Published private(set) var voicePartialTranscript = ""
  @Published private(set) var dictationInsertion: VoiceDictationInsertion?
  private var voiceFunctionKeyMonitor: Any?
  private var isVoiceFunctionKeyHeld = false

  // Stable anchor to prevent drifting during resize
  private var stableTopVisibleY: CGFloat?
  private var stableBottomVisibleY: CGFloat?
  private var pendingWindowHeight: CGFloat?
  private var isWindowHeightUpdateScheduled = false
  private var isApplyingProgrammaticFrame = false
  var placementState = FloatingWindowPlacementState()

  enum AnchorRegion {
    case top, center, bottom
  }
  private var activeAnchor: AnchorRegion = .center

  // Content to send to AI
  @Published var detectedContent: DetectedContent?

  /// Each floating task owns a connection. Sharing a manager would cause streamed
  /// responses and conversation IDs to leak between independently-opened panels.
  let wsManager: WebSocketManager

  // Callback to toggle history panel
  var onToggleHistory: (() -> Void)?

  // Callback to refresh history panel after new chat
  var onHistoryRefresh: (() -> Void)?

  // Callback when user starts a new chat
  var onNewChat: (() -> Void)?
  var onVoiceInputBegan: (() -> Void)?
  var onVoiceInputEnded: (() -> Void)?
  var onVoiceInputToggled: (() -> Void)?
  var onVoiceInputCancelled: (() -> Void)?
#if DEBUG
  var onDebugDemoKeyDown: ((NSEvent, Bool) -> Bool)?
#endif
  var onDismiss: (() -> Void)?
  /// Returns the on-screen notch frame when this composer should visibly hand
  /// off to a detached run. A nil result keeps ordinary close behavior.
  var onDismissTransition: (() -> NSRect?)?
  var onFrontmostStateChanged: (() -> Void)?
  /// Lets the workspace coordinate companion surfaces (such as the notch)
  /// against the actual panel visibility, not just key-window focus.
  var onVisibilityChanged: (() -> Void)?

  // Window configuration
  /// The compact composer is deliberately fixed-width. Without a width
  /// contract, NSHostingView can re-fit a borderless panel when a media view
  /// changes from its loading state to its natural video size.
  static let compactWindowWidth = FloatingChatWindowLayout.width
  private let windowWidth: CGFloat = FloatingWindowController.compactWindowWidth
  // Initial height until SwiftUI reports the visible content's natural height.
  private let windowHeight = FloatingChatWindowLayout.minimumHeight

  init(
    wsManager: WebSocketManager,
    selectedAgent: String = DetachSettings.selectedAgent,
    selectedModel: String? = DetachSettings.selectedModel(for: DetachSettings.selectedAgent)
  ) {
    self.wsManager = wsManager
    self.selectedAgent = selectedAgent
    self.selectedModel = selectedModel
    self.selectedModelSettings = DetachSettings.modelSettings(for: selectedAgent, model: selectedModel)
    super.init()
  }

  deinit {
    if let voiceFunctionKeyMonitor {
      NSEvent.removeMonitor(voiceFunctionKeyMonitor)
    }
  }

  // MARK: - Show/Hide

  /// Show the chat window at the specified location
  /// Always reuses existing window to preserve chat state
  func show(at location: NSPoint, with content: DetectedContent?, centered: Bool = false) {
    placementState.handoffInProgress = false
    placementState.handoffID = nil
    // Store content for the chat view (available for next message)
    if content != nil {
      self.detectedContent = content
    }

    // Always reuse existing window to preserve chat state
    if chatWindow == nil {
      createChatWindow()
    }

    // Calculate smart frame based on cursor location
    // Use current window height if visible to maintain size during re-trigger
    let currentH = chatWindow?.frame.height ?? windowHeight
    let result = calculateWindowFrame(for: location, currentHeight: currentH, centered: centered)
    let frame = result.frame
    self.activeAnchor = result.region

    chatWindow?.setFrame(frame, display: true)
    chatWindow?.alphaValue = 1
    resetAnchor()
    chatWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    isVisible = true
    rememberCurrentWindowFrame()
    onVisibilityChanged?()
    updateFrontmostState()

    print("💬 Chat window shown (\(activeAnchor) region) at \(frame.origin)")
  }

  /// Restores a retained task at the exact place the user last left it. This
  /// is intentionally different from `show(at:with:)`, which is the new-task
  /// launcher and positions a fresh composer near the current pointer.
  func bringToFront() {
    guard let chatWindow else { return }
    if !isVisible || placementState.handoffInProgress {
      let preferredFrame = isExpanded ? placementState.expandedFrame : placementState.collapsedFrame
      let visibleFrame = FloatingChatWindowLayout.visibleFrame(
        for: preferredFrame, fallbackLocation: NSEvent.mouseLocation)
      let restoredFrame = FloatingChatWindowLayout.restoredFrame(
        from: preferredFrame, visibleFrame: visibleFrame, expanded: isExpanded,
        fallbackHeight: chatWindow.frame.height)
      chatWindow.setFrame(restoredFrame, display: true)
      resetAnchor()
      placementState.handoffInProgress = false
      placementState.handoffID = nil
    }
    chatWindow.alphaValue = 1
    chatWindow.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    isVisible = true
    rememberCurrentWindowFrame()
    onVisibilityChanged?()
    updateFrontmostState()
    print("💬 Existing chat window restored")
  }

  func updateVoiceDictation(state: VoiceDictationState, partialTranscript: String) {
    voiceDictationState = state
    voicePartialTranscript = partialTranscript
  }

  func insertVoiceTranscription(_ transcript: String) {
    dictationInsertion = VoiceDictationInsertion(text: transcript)
  }

  /// Hide the chat window
  func hide() {
    updateDebugPointerHover(false)
    cancelVoiceInputIfNeeded()
    rememberCurrentWindowFrame()
    chatWindow?.orderOut(nil)
    isVisible = false
    onVisibilityChanged?()
    updateFrontmostState()
    print("💬 Chat window hidden")
  }

  /// Dismisses only this composer. Any active run keeps its dedicated connection
  /// and remains visible through the shared notch task list.
  func dismiss() {
    updateDebugPointerHover(false)
    cancelVoiceInputIfNeeded()
    guard let window = chatWindow, isVisible else {
      hide()
      onDismiss?()
      return
    }

    guard let destination = onDismissTransition?() else {
      hide()
      onDismiss?()
      return
    }

    rememberCurrentWindowFrame()
    placementState.handoffInProgress = true
    let handoffID = UUID()
    placementState.handoffID = handoffID

    let duration: TimeInterval = 0.26
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      window.animator().setFrame(destination, display: true)
      window.animator().alphaValue = 0
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak window] in
      guard let self else { return }
      guard self.placementState.handoffID == handoffID else { return }
      window?.orderOut(nil)
      // The panel is retained for a live task. Restore its opacity now so a
      // later notch reopen starts from a normal fully-visible composer.
      window?.alphaValue = 1
      self.isVisible = false
      self.placementState.handoffInProgress = false
      self.placementState.handoffID = nil
      self.onVisibilityChanged?()
      self.updateFrontmostState()
      self.onDismiss?()
      print("💬 Chat window merged into detached task")
    }
  }

  /// Toggle visibility
  func toggle(at location: NSPoint, with content: DetectedContent?) {
    if isVisible {
      hide()
    } else {
      show(at: location, with: content)
    }
  }

  /// Show chat with a specific conversation loaded from history
  /// Forces window recreation so the conversation is loaded fresh
  func showWithConversation(at location: NSPoint) {
    // Force recreate window so onAppear fires and loads the conversation
    if chatWindow != nil {
      cancelVoiceInputIfNeeded()
      chatWindow?.close()
      chatWindow = nil
    }
    self.detectedContent = nil  // No new content, just loading from history
    createChatWindow()

    // Calculate smart frame
    let result = calculateWindowFrame(for: location, currentHeight: windowHeight)
    let frame = result.frame
    self.activeAnchor = result.region

    chatWindow?.setFrame(frame, display: true)
    resetAnchor()
    chatWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    isVisible = true
    rememberCurrentWindowFrame()
    onVisibilityChanged?()
    updateFrontmostState()

    print("💬 Chat window shown (history, \(activeAnchor) region) at \(frame.origin)")
  }

  // MARK: - Window Creation

  private func createChatWindow() {
    // Create a floating panel - borderless for clean look
    let panel = FloatingComposerPanel(
      contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    // Keep AppKit from adopting the hosting view's intrinsic width. Height
    // remains managed by updateWindowHeight below.
    panel.fixedContentWidth = windowWidth
    panel.minSize = NSSize(width: windowWidth, height: FloatingChatWindowLayout.compactMinimumHeight)
    panel.maxSize = NSSize(width: windowWidth, height: .greatestFiniteMagnitude)

    panel.isMovableByWindowBackground = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.acceptsMouseMovedEvents = true
    // The visible composer draws its own rounded shadow. Letting AppKit shadow
    // this transparent panel adds a rectangular halo around the whole window.
    panel.hasShadow = false

    // Create the chat view
    let chatView = FloatingChatView(
      controller: self,
      wsManager: wsManager,
      onClose: { [weak self] in
        self?.dismiss()
      },
      onToggleHistory: onToggleHistory,
      onHistoryRefresh: onHistoryRefresh,
      onNewChat: onNewChat
    )

    let hostingView = FirstClickHostingView(rootView: chatView.font(.custom("Geist-Regular", size: 14)))
    // Window height is measured and applied explicitly below. Prevent the
    // hosting view from independently changing NSWindow size constraints.
    hostingView.sizingOptions = []
    hostingView.autoresizingMask = [.width, .height]
    panel.contentView = hostingView
    panel.onCancelOperation = { [weak self] in
      self?.dismiss()
    }

    chatWindow = panel
    panel.delegate = self
    installLocalVoiceFunctionKeyMonitor()
  }

  /// Fn is intentionally local to the focused composer. This avoids a global
  /// key-tap race with App Shot and prevents a hidden task from recording.
  private func installLocalVoiceFunctionKeyMonitor() {
    // Voice mode is temporarily disabled while its UX is finalized. Do not
    // install a monitor or consume Fn events until the feature is re-enabled.
    guard FeatureFlags.voiceModeEnabled else { return }
    guard voiceFunctionKeyMonitor == nil else { return }

    voiceFunctionKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
      [weak self] event in
      guard let self,
        self.isVisible,
        self.chatWindow?.isKeyWindow == true,
        event.keyCode == 63
      else {
        return event
      }

      let functionIsDown = event.modifierFlags.contains(.function)
      if functionIsDown && !self.isVoiceFunctionKeyHeld {
        self.isVoiceFunctionKeyHeld = true
        self.onVoiceInputBegan?()
      } else if !functionIsDown && self.isVoiceFunctionKeyHeld {
        self.isVoiceFunctionKeyHeld = false
        self.onVoiceInputEnded?()
      }

      // The focused composer owns Fn, so it should not also trigger the
      // system Emoji/Dictation action.
      return nil
    }
  }

  /// Update window height with animation
  func updateWindowHeight(_ newHeight: CGFloat) {
    guard newHeight.isFinite, newHeight > 0, !isExpanded else { return }

    pendingWindowHeight = newHeight
    guard !isWindowHeightUpdateScheduled else { return }
    isWindowHeightUpdateScheduled = true

    // Streaming can update the response dozens of times per second. Coalesce
    // those measurements so the panel grows smoothly instead of relocating on
    // every token.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
      guard let self else { return }
      self.isWindowHeightUpdateScheduled = false
      guard let height = self.pendingWindowHeight else { return }
      self.pendingWindowHeight = nil
      self.applyWindowHeight(height)
    }
  }

  private func applyWindowHeight(_ requestedHeight: CGFloat) {
    guard let window = chatWindow, !isExpanded else { return }

    let currentFrame = window.frame
    let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect.zero
    let minimumHeight = FloatingChatWindowLayout.compactMinimumHeight
    let maximumHeight = max(minimumHeight, screenFrame.height)
    let newHeight = min(max(requestedHeight, minimumHeight), maximumHeight)

    // Capture the anchors if we don't have them
    if stableTopVisibleY == nil || stableBottomVisibleY == nil {
      stableTopVisibleY = currentFrame.origin.y + currentFrame.height
      stableBottomVisibleY = currentFrame.origin.y
    }

    // If change is negligible, skip to avoid jitter
    if abs(currentFrame.height - newHeight) < 2 { return }

    // Calculate new origin based on ACTIVE anchor
    var newOriginY: CGFloat

    switch activeAnchor {
    case .bottom:
      // Growth goes UPWARDS from bottom anchor
      newOriginY = stableBottomVisibleY ?? currentFrame.origin.y
    case .top, .center:
      // Growth goes DOWNWARDS from top anchor
      newOriginY = (stableTopVisibleY ?? (currentFrame.origin.y + currentFrame.height)) - newHeight
    }

    // Clamp to screen bounds to prevent window from going off-screen
    if newOriginY < screenFrame.minY {
      newOriginY = screenFrame.minY
    }
    if newOriginY + newHeight > screenFrame.maxY {
      newOriginY = screenFrame.maxY - newHeight
    }

    let newFrame = NSRect(
      x: currentFrame.origin.x,
      y: newOriginY,
      width: windowWidth,
      height: newHeight
    )

    isApplyingProgrammaticFrame = true
    window.setFrame(newFrame, display: true)
    rememberCurrentWindowFrame()
    DispatchQueue.main.async { [weak self] in
      self?.isApplyingProgrammaticFrame = false
    }
  }

  // Reset anchor whenever the window is moved manually or shown at a new spot
  func resetAnchor() {
    guard let window = chatWindow else { return }
    stableTopVisibleY = window.frame.origin.y + window.frame.height
    stableBottomVisibleY = window.frame.origin.y
    print("📍 Anchors reset: Top=\(stableTopVisibleY!), Bottom=\(stableBottomVisibleY!)")
  }

  // MARK: - NSWindowDelegate

  func windowDidMove(_ notification: Notification) {
    guard !isApplyingProgrammaticFrame else { return }
    // When the user moves the window manually, we must refresh the anchors
    // otherwise the next height update will "snap" it back to the old position.
    resetAnchor()
    rememberCurrentWindowFrame()
  }

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    guard sender === chatWindow else { return frameSize }
    let screen = sender.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? sender.frame
    return FloatingChatWindowLayout.resize(frameSize, visibleFrame: screen, expanded: isExpanded)
  }

  func windowDidResize(_ notification: Notification) {
    updateExpandedContentHeight()
    rememberCurrentWindowFrame()
  }

  func updateExpandedContentHeight(to proposedHeight: CGFloat? = nil) {
    guard isExpanded, let window = chatWindow else { return }
    let nativeHeight = window.contentRect(forFrameRect: window.frame).height
    let height = proposedHeight ?? nativeHeight
    guard height.isFinite, height > 0 else { return }
    if abs(expandedContentHeight - height) > 0.5 { expandedContentHeight = height }
  }

  func windowDidBecomeKey(_ notification: Notification) {
    // Optional: Refresh anchor when we focus to be extra safe
    resetAnchor()
    rememberCurrentWindowFrame()
    updateFrontmostState()
  }

  func windowDidResignKey(_ notification: Notification) {
    if isVoiceFunctionKeyHeld {
      isVoiceFunctionKeyHeld = false
      onVoiceInputEnded?()
    }
    updateFrontmostState()
  }

  private func updateFrontmostState() {
    guard let window = chatWindow, isVisible else {
      if isFrontmost {
        isFrontmost = false
      }
      return
    }

    let isKey = window.isKeyWindow || NSApp.keyWindow === window
    let newValue = NSApp.isActive && isKey
    if isFrontmost != newValue {
      isFrontmost = newValue
      onFrontmostStateChanged?()
    }
  }

  /// Debug demo shortcuts follow the panel under the pointer. This matters
  /// when several retained floating composers are visible at once: keyboard
  /// events otherwise reach every local monitor and the first panel wins.
  func updateDebugPointerHover(_ isHovering: Bool) {
#if DEBUG
    if isHovering {
      Self.debugPointerTarget = self
    } else if Self.debugPointerTarget === self {
      Self.debugPointerTarget = nil
    }
#endif
  }

  func ownsDebugWindow(_ window: NSWindow) -> Bool {
#if DEBUG
    return chatWindow === window
#else
    return false
#endif
  }

  func containsPointer(_ point: NSPoint = NSEvent.mouseLocation) -> Bool {
    guard isVisible, let window = chatWindow else { return false }

#if DEBUG
    // SwiftUI's hover hit-test is the authoritative target when panels
    // overlap. It follows the actual visible surface rather than the order in
    // which the AppKit local key monitors were installed.
    if let debugPointerTarget = Self.debugPointerTarget {
      if debugPointerTarget.isVisible {
        return debugPointerTarget === self
      }
      Self.debugPointerTarget = nil
    }
#endif

    guard window.frame.contains(point) else { return false }

    // Several panels can overlap while retained tasks are being restored. In
    // that case only the panel the user can actually see at this point should
    // consume the Debug shortcut.
    return NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
      == window.windowNumber
  }

  private func cancelVoiceInputIfNeeded() {
    let shouldCancel = isVoiceFunctionKeyHeld || voiceDictationState != .idle
    isVoiceFunctionKeyHeld = false
    guard shouldCancel else { return }
    onVoiceInputCancelled?()
  }
}
