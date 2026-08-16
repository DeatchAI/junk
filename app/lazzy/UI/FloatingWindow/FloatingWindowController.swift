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

  private var chatWindow: NSPanel?
  let taskId = UUID()
  @Published private(set) var isVisible = false
  @Published private(set) var isFrontmost = false
  @Published var isExpanded = false
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
  static let compactWindowWidth: CGFloat = 520
  private let windowWidth: CGFloat = FloatingWindowController.compactWindowWidth
  // Keep the compact composer stable while attachments are added or removed.
  // Responses may still extend the window beyond this baseline.
  private let windowHeight: CGFloat = 280

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
  func show(at location: NSPoint, with content: DetectedContent?) {
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
    let result = calculateWindowFrame(for: location, currentHeight: currentH)
    let frame = result.frame
    self.activeAnchor = result.region

    chatWindow?.setFrame(frame, display: true)
    chatWindow?.alphaValue = 1
    resetAnchor()
    chatWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    isVisible = true
    onVisibilityChanged?()
    updateFrontmostState()

    print("💬 Chat window shown (\(activeAnchor) region) at \(frame.origin)")
  }

  /// Restores a retained task at the exact place the user last left it. This
  /// is intentionally different from `show(at:with:)`, which is the new-task
  /// launcher and positions a fresh composer near the current pointer.
  func bringToFront() {
    guard let chatWindow else { return }
    chatWindow.alphaValue = 1
    chatWindow.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    isVisible = true
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
    guard let window = chatWindow, isVisible, let destination = onDismissTransition?() else {
      hide()
      onDismiss?()
      return
    }

    let duration: TimeInterval = 0.26
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      window.animator().setFrame(destination, display: true)
      window.animator().alphaValue = 0
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak window] in
      guard let self else { return }
      window?.orderOut(nil)
      // The panel is retained for a live task. Restore its opacity now so a
      // later notch reopen starts from a normal fully-visible composer.
      window?.alphaValue = 1
      self.isVisible = false
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
    onVisibilityChanged?()
    updateFrontmostState()

    print("💬 Chat window shown (history, \(activeAnchor) region) at \(frame.origin)")
  }

  // MARK: - Expansion Logic

  func toggleExpansion() {
    guard let window = chatWindow else { return }
    isExpanded.toggle()

    if isExpanded {
      // Switch to Expanded Mode
      if let screen = NSScreen.main {
        let screenFrame = screen.visibleFrame
        let padding: CGFloat = 20

        // Calculate new frame: Full height (minus padding), keep current X (clamped), allow resize
        let newX = window.frame.minX
        let newY = screenFrame.minY + padding
        let newHeight = screenFrame.height - (padding * 2)
        let expandedWidth: CGFloat = windowWidth  // Keep same width as compact mode

        let newFrame = NSRect(
          x: newX,
          y: newY,
          width: expandedWidth,
          height: newHeight
        )

        // Add resizing support
        window.styleMask.insert(.resizable)
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true

        window.setFrame(newFrame, display: true, animate: true)
      }
    } else {
      // Switch back to Compact Mode
      window.styleMask.remove(.resizable)

      // The view will re-measure its content height and call updateWindowHeight
      // But we can reset to a sensible default width
      let currentFrame = window.frame
      let compactFrame = NSRect(
        x: currentFrame.minX,
        y: currentFrame.maxY - windowHeight,
        width: windowWidth,
        height: windowHeight
      )
      window.setFrame(compactFrame, display: true, animate: true)
    }
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
    panel.minSize = NSSize(width: windowWidth, height: windowHeight)
    panel.maxSize = NSSize(width: windowWidth, height: .greatestFiniteMagnitude)

    panel.isMovableByWindowBackground = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
#if DEBUG
    panel.acceptsMouseMovedEvents = true
#endif
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

    let hostingView = NSHostingView(rootView: chatView.font(.custom("Geist-Regular", size: 14)))
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
    let maximumHeight = max(windowHeight, screenFrame.height)
    let newHeight = min(max(requestedHeight, windowHeight), maximumHeight)

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
  }

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    guard sender === chatWindow else { return frameSize }
    return NSSize(width: windowWidth, height: frameSize.height)
  }

  func windowDidBecomeKey(_ notification: Notification) {
    // Optional: Refresh anchor when we focus to be extra safe
    resetAnchor()
    updateFrontmostState()
  }

  func windowDidResignKey(_ notification: Notification) {
    if isVoiceFunctionKeyHeld {
      isVoiceFunctionKeyHeld = false
      onVoiceInputEnded?()
    }
    updateFrontmostState()
  }

  // MARK: - Smart Positioning Helpers

  /// Calculates a window frame based on cursor location relative to screen regions
  private func calculateWindowFrame(for location: NSPoint, currentHeight: CGFloat)
    -> (frame: NSRect, region: AnchorRegion)
  {
    let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
    let screenH = screenFrame.height
    let screenW = screenFrame.width
    let relY = (location.y - screenFrame.minY) / screenH
    let relX = (location.x - screenFrame.minX) / screenW

    var x: CGFloat = location.x + 20
    var y: CGFloat = location.y - currentHeight / 2
    var region: AnchorRegion = .center

    // 1. Vertical Positioning
    if relY < 0.25 {
      // Bottom 25%: Show ABOVE cursor and anchor to BOTTOM for upward growth
      y = location.y + 20
      region = .bottom
    } else if relY > 0.75 {
      // Top 25%: Show BELOW cursor and anchor to TOP for downward growth
      y = location.y - currentHeight - 20
      region = .top
    } else {
      // Center
      y = location.y - currentHeight / 2
      region = .center
    }

    // 2. Horizontal Positioning
    if relX > 0.7 {
      // Right 30%: Show to the LEFT of cursor
      x = location.x - windowWidth - 20
    } else if relX < 0.3 {
      // Left 30%: Show to the RIGHT of cursor (default)
      x = location.x + 20
    } else {
      x = location.x + 20
    }

    // 3. Strict Clamping to Visible Screen (prevents Dock/Menu overlap or off-screen)
    // We must ensure the window stays in the visible frame even at currentHeight
    x = max(screenFrame.minX + 10, min(x, screenFrame.maxX - windowWidth - 10))
    y = max(screenFrame.minY + 10, min(y, screenFrame.maxY - currentHeight - 10))

    return (NSRect(x: x, y: y, width: windowWidth, height: currentHeight), region)
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

/// AppKit can ask a borderless hosting window to adopt its content's fitting
/// width even when the panel is not user-resizable. Keep the composer width
/// stable while allowing the response area to grow vertically.
private final class FloatingComposerPanel: KeyablePanel {
  var fixedContentWidth: CGFloat = 0

  override func setFrame(
    _ frameRect: NSRect,
    display flag: Bool,
    animate animateFlag: Bool
  ) {
    guard fixedContentWidth > 0 else {
      super.setFrame(frameRect, display: flag, animate: animateFlag)
      return
    }

    var fixedFrame = frameRect
    fixedFrame.size.width = fixedContentWidth
    super.setFrame(fixedFrame, display: flag, animate: animateFlag)
  }

  override func setContentSize(_ size: NSSize) {
    guard fixedContentWidth > 0 else {
      super.setContentSize(size)
      return
    }

    super.setContentSize(NSSize(width: fixedContentWidth, height: size.height))
  }
}
