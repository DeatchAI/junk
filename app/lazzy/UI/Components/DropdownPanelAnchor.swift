import AppKit
import SwiftUI

enum DropdownPanelPlacement {
  case below
  case trailing
}

/// Hosts custom dropdown content in a reusable borderless panel.
///
/// Hover-enabled anchors keep the panel alive while the pointer crosses the
/// small gap between the trigger and the menu. Reusing the hosting view avoids
/// rebuilding the SwiftUI hierarchy every time the pointer moves.
struct DropdownPanelAnchor<MenuContent: View>: NSViewRepresentable {
  @Binding var isPresented: Bool
  let menuWidth: CGFloat
  let menu: MenuContent
  var placement: DropdownPanelPlacement = .below
  var opensOnHover: Bool = false

  func makeCoordinator() -> Coordinator {
    Coordinator(isPresented: $isPresented)
  }

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    view.postsFrameChangedNotifications = true
    return view
  }

  func updateNSView(_ anchorView: NSView, context: Context) {
    if isPresented {
      context.coordinator.present(
        menu: menu,
        menuWidth: menuWidth,
        placement: placement,
        opensOnHover: opensOnHover,
        from: anchorView
      )
    } else {
      context.coordinator.dismiss()
    }
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.dismiss()
  }

  @MainActor
  final class Coordinator {
    @Binding var isPresented: Bool
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private weak var parentWindow: NSWindow?
    private weak var anchorView: NSView?
    private var clickMonitor: Any?
    private var hoverMonitor: Any?
    private var dismissalWorkItem: DispatchWorkItem?
    private var opensOnHover = false

    init(isPresented: Binding<Bool>) {
      self._isPresented = isPresented
    }

    func present(
      menu: MenuContent,
      menuWidth: CGFloat,
      placement: DropdownPanelPlacement,
      opensOnHover: Bool,
      from anchorView: NSView
    ) {
      guard let window = anchorView.window else { return }

      self.anchorView = anchorView
      self.opensOnHover = opensOnHover
      cancelDismissal()

      let rootView = AnyView(menu.padding(22))
      let menuHostingView: NSHostingView<AnyView>
      if let existingHostingView = hostingView {
        existingHostingView.rootView = rootView
        menuHostingView = existingHostingView
      } else {
        let newHostingView = NSHostingView(rootView: rootView)
        newHostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView = newHostingView
        menuHostingView = newHostingView
      }

      let menuPanel: NSPanel
      if let panel {
        menuPanel = panel
        menuPanel.contentView = menuHostingView
      } else {
        menuPanel = NSPanel(
          contentRect: .zero,
          styleMask: [.borderless, .nonactivatingPanel],
          backing: .buffered,
          defer: false
        )
        menuPanel.isOpaque = false
        menuPanel.backgroundColor = .clear
        menuPanel.hasShadow = false
        menuPanel.hidesOnDeactivate = false
        menuPanel.isFloatingPanel = true
        menuPanel.becomesKeyOnlyIfNeeded = true
        menuPanel.acceptsMouseMovedEvents = true
        menuPanel.level = window.level
        menuPanel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        menuPanel.contentView = menuHostingView
        panel = menuPanel
      }

      setupClickMonitor()

      if parentWindow !== window {
        parentWindow?.removeChildWindow(menuPanel)
        window.addChildWindow(menuPanel, ordered: .above)
        parentWindow = window
      }
      menuPanel.level = window.level

      menuHostingView.frame.size.width = menuWidth + 44
      menuHostingView.layoutSubtreeIfNeeded()
      let fittingHeight = min(max(menuHostingView.fittingSize.height, 40), 320)
      menuPanel.setContentSize(NSSize(width: menuWidth + 44, height: fittingHeight))
      position(menuPanel, relativeTo: anchorView, placement: placement)

      if opensOnHover {
        setupHoverMonitor()
      } else {
        removeHoverMonitor()
      }
      menuPanel.orderFront(nil)
    }

    func dismiss() {
      cancelDismissal()
      removeClickMonitor()
      removeHoverMonitor()
      guard let panel else { return }

      for child in panel.childWindows ?? [] {
        panel.removeChildWindow(child)
        child.orderOut(nil)
      }
      parentWindow?.removeChildWindow(panel)
      panel.orderOut(nil)
      parentWindow = nil
    }

    private func position(
      _ panel: NSPanel,
      relativeTo anchorView: NSView,
      placement: DropdownPanelPlacement
    ) {
      guard let window = anchorView.window else { return }
      let boundsInWindow = anchorView.convert(anchorView.bounds, to: nil)
      let boundsInScreen = window.convertToScreen(boundsInWindow)
      let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
      let panelSize = panel.frame.size

      var originX: CGFloat
      var originY: CGFloat
      switch placement {
      case .below:
        originX = boundsInScreen.minX - 22
        originY = boundsInScreen.minY - panelSize.height + 18
      case .trailing:
        originX = boundsInScreen.maxX - 22
        originY = boundsInScreen.maxY - panelSize.height + 22
      }

      originX = min(max(originX, visibleFrame.minX), visibleFrame.maxX - panelSize.width)
      originY = min(max(originY, visibleFrame.minY), visibleFrame.maxY - panelSize.height)
      panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func setupClickMonitor() {
      guard clickMonitor == nil else { return }
      clickMonitor = NSEvent.addLocalMonitorForEvents(
        matching: [.leftMouseDown, .rightMouseDown]
      ) { [weak self] event in
        guard let self else { return event }
        if !self.pointerIsInsidePanelOrAnchor(NSEvent.mouseLocation) {
          DispatchQueue.main.async { [weak self] in
            self?.isPresented = false
          }
        }
        return event
      }
    }

    private func setupHoverMonitor() {
      guard hoverMonitor == nil else { return }
      hoverMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
        self?.updateHover(at: NSEvent.mouseLocation)
        return event
      }
    }

    private func updateHover(at location: NSPoint) {
      guard opensOnHover, panel != nil else { return }
      if pointerIsInsidePanelOrAnchor(location) {
        cancelDismissal()
      } else {
        scheduleDismissal()
      }
    }

    private func scheduleDismissal() {
      guard dismissalWorkItem == nil else { return }
      let workItem = DispatchWorkItem { [weak self] in
        guard let self else { return }
        self.dismissalWorkItem = nil
        guard self.opensOnHover,
          !self.pointerIsInsidePanelOrAnchor(NSEvent.mouseLocation)
        else { return }
        self.isPresented = false
      }
      dismissalWorkItem = workItem
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(160), execute: workItem)
    }

    private func pointerIsInsidePanelOrAnchor(_ location: NSPoint) -> Bool {
      if let panel, containsMouse(location, in: panel) {
        return true
      }

      guard let anchorView, let window = anchorView.window else { return false }
      let boundsInWindow = anchorView.convert(anchorView.bounds, to: nil)
      let boundsInScreen = window.convertToScreen(boundsInWindow)
      return boundsInScreen.insetBy(dx: -5, dy: -5).contains(location)
    }

    private func containsMouse(_ location: NSPoint, in window: NSWindow) -> Bool {
      if window.frame.insetBy(dx: 3, dy: 3).contains(location) {
        return true
      }
      return window.childWindows?.contains { containsMouse(location, in: $0) } == true
    }

    private func cancelDismissal() {
      dismissalWorkItem?.cancel()
      dismissalWorkItem = nil
    }

    private func removeHoverMonitor() {
      if let hoverMonitor {
        NSEvent.removeMonitor(hoverMonitor)
        self.hoverMonitor = nil
      }
    }

    private func removeClickMonitor() {
      if let clickMonitor {
        NSEvent.removeMonitor(clickMonitor)
        self.clickMonitor = nil
      }
    }
  }
}
