import AppKit
import Combine
import Foundation
import SwiftUI

/// Controller for the floating AI chat window
class FloatingWindowController: NSObject, ObservableObject, NSWindowDelegate {

  private var chatWindow: NSPanel?
  let taskId = UUID()
  @Published private(set) var isVisible = false
  @Published private(set) var isFrontmost = false
  @Published var isExpanded = false
  @Published var selectedAgent: String
  @Published var selectedModel: String?

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
  var onDismiss: (() -> Void)?
  /// Returns the on-screen notch frame when this composer should visibly hand
  /// off to a detached run. A nil result keeps ordinary close behavior.
  var onDismissTransition: (() -> NSRect?)?
  var onFrontmostStateChanged: (() -> Void)?
  /// Lets the workspace coordinate companion surfaces (such as the notch)
  /// against the actual panel visibility, not just key-window focus.
  var onVisibilityChanged: (() -> Void)?

  // Window configuration
  private let windowWidth: CGFloat = 520
  private let windowHeight: CGFloat = 200

  init(
    wsManager: WebSocketManager,
    selectedAgent: String = DetachSettings.selectedAgent,
    selectedModel: String? = DetachSettings.selectedModel(for: DetachSettings.selectedAgent)
  ) {
    self.wsManager = wsManager
    self.selectedAgent = selectedAgent
    self.selectedModel = selectedModel
    super.init()
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

  /// Hide the chat window
  func hide() {
    chatWindow?.orderOut(nil)
    isVisible = false
    onVisibilityChanged?()
    updateFrontmostState()
    print("💬 Chat window hidden")
  }

  /// Dismisses only this composer. Any active run keeps its dedicated connection
  /// and remains visible through the shared notch task list.
  func dismiss() {
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
        y: currentFrame.maxY - 200,  // Approximate re-positioning
        width: windowWidth,
        height: 200
      )
      window.setFrame(compactFrame, display: true, animate: true)
    }
  }

  // MARK: - Window Creation

  private func createChatWindow() {
    // Create a floating panel - borderless for clean look
    let panel = KeyablePanel(
      contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    panel.isMovableByWindowBackground = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true

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
  }

  /// Update window height with animation
  func updateWindowHeight(_ newHeight: CGFloat) {
    guard newHeight.isFinite, newHeight > 0, !isExpanded else { return }

    pendingWindowHeight = newHeight
    guard !isWindowHeightUpdateScheduled else { return }
    isWindowHeightUpdateScheduled = true

    DispatchQueue.main.async { [weak self] in
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
    let maximumHeight = max(120, screenFrame.height)
    let newHeight = min(max(requestedHeight, 120), maximumHeight)

    // Capture the anchors if we don't have them
    if stableTopVisibleY == nil || stableBottomVisibleY == nil {
      stableTopVisibleY = currentFrame.origin.y + currentFrame.height
      stableBottomVisibleY = currentFrame.origin.y
    }

    // If change is negligible, skip to avoid jitter
    if abs(currentFrame.height - newHeight) < 0.1 { return }

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
      width: currentFrame.width,
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

  func windowDidBecomeKey(_ notification: Notification) {
    // Optional: Refresh anchor when we focus to be extra safe
    resetAnchor()
    updateFrontmostState()
  }

  func windowDidResignKey(_ notification: Notification) {
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
}
