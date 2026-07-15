import AppKit
import Combine
import Foundation
import SwiftUI

/// Controller for the floating quick actions menu
class QuickActionsMenuController: NSObject, ObservableObject {

  private var menuWindow: NSWindow?
  @Published private(set) var isVisible = false

  // WebSocket manager for custom actions
  weak var wsManager: WebSocketManager?
  private var cancellables = Set<AnyCancellable>()
  private var hideWorkItem: DispatchWorkItem?

  // Configuration
  var theme: ThemeManager = ThemeManager.shared

  // Computed property that combines custom + default actions
  var allActions: [QuickAction] {
    let customActions = (wsManager?.customQuickActions ?? []).filter { $0.enabled }
    // Insert custom actions before the "more" action
    var actions = QuickAction.defaultActions
    if let moreIndex = actions.firstIndex(where: { $0.id == "more" }) {
      actions.insert(contentsOf: customActions, at: moreIndex)
    } else {
      actions.append(contentsOf: customActions)
    }
    return actions
  }

  // Callback when an action is selected
  var onActionSelected: ((QuickAction) -> Void)?

  // Window sizing
  private let menuHeight: CGFloat = 36
  private let offset: CGFloat = 10
  private let minimumMenuWidth: CGFloat = 112

  override init() {
    super.init()
  }

  /// Setup observation of custom quick actions changes
  func observeCustomActions() {
    wsManager?.$customQuickActions
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.refreshMenu()
      }
      .store(in: &cancellables)
  }

  // MARK: - Auto-Hide Management

  func scheduleAutoHide() {
    cancelAutoHide()

    let item = DispatchWorkItem { [weak self] in
      print("⏱️ Auto-hide timer fired")
      self?.hide()
    }
    hideWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: item)
  }

  func cancelAutoHide() {
    hideWorkItem?.cancel()
    hideWorkItem = nil
  }

  // MARK: - Show/Hide

  /// Show the menu at the specified location
  func show(at location: NSPoint) {
    if menuWindow == nil {
      createMenuWindow()
    }

    let menuWidth = calculatedMenuWidth()
    let menuHeight = self.menuHeight

    // Position menu near cursor, ensuring it stays on screen
    let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
    var x = location.x + offset
    var y = location.y - menuHeight - offset

    // Keep on screen horizontally
    if x + menuWidth > screenFrame.maxX {
      x = location.x - menuWidth - offset
    }
    if x < screenFrame.minX {
      x = screenFrame.minX + 10
    }

    // Keep on screen vertically
    if y < screenFrame.minY {
      y = location.y + offset
    }

    let frame = NSRect(x: x, y: y, width: menuWidth, height: menuHeight)
    menuWindow?.setFrame(frame, display: true)
    menuWindow?.orderFront(nil)
    isVisible = true

    scheduleAutoHide()

    print("📋 Quick actions menu shown at \(location)")
  }

  /// Hide the menu
  func hide() {
    cancelAutoHide()
    menuWindow?.orderOut(nil)
    isVisible = false
    print("📋 Quick actions menu hidden")
  }

  // MARK: - Window Creation

  private func createMenuWindow() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: calculatedMenuWidth(), height: menuHeight),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = false  // View handles shadow
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]
    window.ignoresMouseEvents = false

    var menuView = QuickActionsMenuView(
      actions: allActions,
      onActionSelected: { [weak self] action in
        self?.onActionSelected?(action)
        self?.hide()
      }
    )

    menuView.onHoverStatusChanged = { [weak self] isHovered in
      if isHovered {
        print("🖱️ Menu hovered - canceling auto-hide")
        self?.cancelAutoHide()
      } else {
        print("🖱️ Menu unhovered - scheduling auto-hide")
        self?.scheduleAutoHide()
      }
    }

    let hostingView = NSHostingView(rootView: menuView)
    window.contentView = hostingView

    menuWindow = window
  }

  private func calculatedMenuWidth() -> CGFloat {
    let visibleActionCount = min(allActions.filter { $0.id != "more" }.count, 5)
    let overflowWidth: CGFloat = allActions.filter { $0.id != "more" }.count > 5 ? 28 : 0
    let actionWidths = allActions.filter { $0.id != "more" }.prefix(5).reduce(CGFloat(0)) {
      partial, action in
      partial + max(44, CGFloat(action.title.count * 8 + 18))
    }
    let width = actionWidths + overflowWidth + CGFloat(max(0, visibleActionCount - 1)) * 2
    return max(minimumMenuWidth, width)
  }

  /// Recreate window if theme or actions change
  func refreshMenu() {
    let wasVisible = isVisible
    let location = menuWindow?.frame.origin ?? .zero
    menuWindow?.close()
    menuWindow = nil
    if wasVisible {
      show(at: location)
    }
  }
}
