import AppKit

/// Observe clicks without consuming them: the destination app still receives its click.
@MainActor final class HistoryClickAwayMonitor {
  private weak var panel: NSWindow?
  private var onDismiss: (() -> Void)?
  private var localMonitor: Any?
  private var globalMonitor: Any?
  private var menuObservers: [NSObjectProtocol] = []
  private var trackingMenus = 0
  private var generation = 0

  func start(for panel: NSWindow, onDismiss: @escaping () -> Void) {
    stop()
    self.panel = panel; self.onDismiss = onDismiss
    let generation = self.generation
    let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
      MainActor.assumeIsolated { self?.handleLocalClick(in: event.window) }
      return event
    }
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.generation == generation else { return }
        self.handleExternalClick()
      }
    }
    let center = NotificationCenter.default
    menuObservers = [
      center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.trackingMenus += 1 }
      },
      center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { if let self { self.trackingMenus = max(0, self.trackingMenus - 1) } }
      },
    ]
  }

  func handleLocalClick(in window: NSWindow?) {
    guard let panel, trackingMenus == 0 else { return }
    var candidate = window
    while let current = candidate {
      if current === panel { return }
      candidate = current.parent ?? current.sheetParent
    }
    onDismiss?()
  }

  func handleExternalClick() { if panel != nil { onDismiss?() } }

  func stop() {
    generation &+= 1
    if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    menuObservers.forEach(NotificationCenter.default.removeObserver)
    localMonitor = nil; globalMonitor = nil; menuObservers = []
    trackingMenus = 0; panel = nil; onDismiss = nil
  }

  deinit {
    if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    menuObservers.forEach(NotificationCenter.default.removeObserver)
  }
}
