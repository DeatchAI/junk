import AppKit
import Combine
import SwiftUI

/// An edge-attached history drawer, opposite the live activity surface.
@MainActor
final class HistoryWindowController: NSObject, ObservableObject {
  private var historyWindow: NSPanel?
  private var cancellables = Set<AnyCancellable>()
  private var presentationGeneration = 0
  private let clickAway = HistoryClickAwayMonitor()

  @Published private(set) var isVisible = false
  @Published private(set) var placement = AppSettings.historyPanelPlacement

  weak var wsManager: WebSocketManager?
  var onSelectConversation: ((Conversation) -> Void)?
  var onNewConversation: (() -> Void)?

  override init() {
    super.init()
    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
      .map { _ in AppSettings.historyPanelPlacement }
      .prepend(AppSettings.historyPanelPlacement)
      .removeDuplicates()
      .dropFirst()
      .receive(on: RunLoop.main)
      .sink { [weak self] placement in
        guard let self else { return }
        self.placement = placement
        self.reposition()
      }
      .store(in: &cancellables)
    NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.reposition() }
      .store(in: &cancellables)
  }

  func show() {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
    let wasCreated = historyWindow == nil
    if wasCreated { createHistoryWindow() }
    guard let window = historyWindow else { return }
    presentationGeneration &+= 1
    placement = AppSettings.historyPanelPlacement
    if !isVisible {
      window.setFrame(
        HistoryPanelLayout.frame(placement: placement, visibleFrame: screen.visibleFrame, expanded: false),
        display: false
      )
      window.alphaValue = 0
    }
    isVisible = true
    window.makeKeyAndOrderFront(nil)
    // Install after the opening click has finished dispatching.
    let generation = presentationGeneration
    DispatchQueue.main.async { [weak self, weak window] in
      guard let self, let window, self.isVisible, self.presentationGeneration == generation else { return }
      self.clickAway.start(for: window) { [weak self] in self?.hide() }
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.24
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      window.animator().setFrame(
        HistoryPanelLayout.frame(placement: placement, visibleFrame: screen.visibleFrame, expanded: true),
        display: true
      )
      window.animator().alphaValue = 1
    }
    if !wasCreated { refresh() }
  }

  func hide() {
    guard isVisible, let window = historyWindow else { return }
    isVisible = false
    clickAway.stop()
    presentationGeneration &+= 1
    let generation = presentationGeneration
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      if let screen = window.screen ?? NSScreen.main {
        window.animator().setFrame(
          HistoryPanelLayout.frame(placement: placement, visibleFrame: screen.visibleFrame, expanded: false),
          display: true
        )
      }
      window.animator().alphaValue = 0
      context.completionHandler = { [weak self, weak window] in
        Task { @MainActor in
          guard let self, self.presentationGeneration == generation, !self.isVisible else { return }
          window?.orderOut(nil)
        }
      }
    }
  }

  func toggle() {
    if isVisible { hide() } else { show() }
  }

  /// Refresh in place so loading new history preserves search and scroll state.
  func refresh() {
    if isVisible { wsManager?.refreshHistoryListing() }
  }

  private func reposition() {
    guard isVisible, let window = historyWindow,
      let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
    window.setFrame(
      HistoryPanelLayout.frame(placement: placement, visibleFrame: screen.visibleFrame, expanded: true),
      display: true
    )
  }

  private func createHistoryWindow() {
    guard let wsManager else { return }
    let panel = KeyablePanel(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isMovableByWindowBackground = false
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    panel.hidesOnDeactivate = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.onCancelOperation = { [weak self] in self?.hide() }

    let view = HistoryPanelView(
      wsManager: wsManager,
      controller: self,
      onSelectConversation: { [weak self] conversation in
        self?.onSelectConversation?(conversation)
        self?.hide()
      },
      onClose: { [weak self] in self?.hide() }
    )
    let hostingView = NSHostingView(rootView: view)
    hostingView.sizingOptions = []
    hostingView.autoresizingMask = [.width, .height]
    panel.contentView = hostingView
    historyWindow = panel
  }
}
