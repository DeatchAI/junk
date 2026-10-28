import AppKit
import SwiftUI

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
  var contentRevision: AnyHashable? = nil
  var acceptsKeyboardInput = false

  func makeCoordinator() -> Coordinator {
    Coordinator(isPresented: $isPresented)
  }

  func makeNSView(context: Context) -> NSView {
    let view = DropdownAnchorView()
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
        contentRevision: contentRevision,
        acceptsKeyboardInput: acceptsKeyboardInput,
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
    private var panel: DropdownMenuPanel?
    private var hostingView: NSHostingView<AnyView>?
    private weak var parentWindow: NSWindow?
    private weak var anchorView: NSView?
    private var clickMonitor: Any?
    private var hoverMonitor: Any?
    private var keyMonitor: Any?
    private var dismissalWorkItem: DispatchWorkItem?
    private var opensOnHover = false
    private var lastContentRevision: AnyHashable?
    private var lastMenuWidth: CGFloat = 0

    init(isPresented: Binding<Bool>) {
      self._isPresented = isPresented
    }

    func present(
      menu: MenuContent,
      menuWidth: CGFloat,
      placement: DropdownPanelPlacement,
      opensOnHover: Bool,
      contentRevision: AnyHashable?,
      acceptsKeyboardInput: Bool = false,
      from anchorView: NSView
    ) {
      guard let window = anchorView.window else { return }

      self.anchorView = anchorView
      self.opensOnHover = opensOnHover
      cancelDismissal()

      let needsLayout = hostingView == nil || contentRevision == nil
        || lastContentRevision != contentRevision || lastMenuWidth != menuWidth
      let rootView = AnyView(menu)
      let menuHostingView: NSHostingView<AnyView>
      if let existingHostingView = hostingView {
        if needsLayout { existingHostingView.rootView = rootView }
        menuHostingView = existingHostingView
      } else {
        let newHostingView = FirstClickHostingView(rootView: rootView)
        newHostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView = newHostingView
        menuHostingView = newHostingView
      }

      let menuPanel: DropdownMenuPanel
      if let panel {
        menuPanel = panel
        menuPanel.contentView = menuHostingView
      } else {
        menuPanel = DropdownMenuPanel(
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
        menuPanel.acceptsMouseMovedEvents = true
        menuPanel.level = window.level
        menuPanel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        menuPanel.contentView = menuHostingView
        panel = menuPanel
      }
      menuPanel.acceptsKeyboardInput = acceptsKeyboardInput
      menuPanel.becomesKeyOnlyIfNeeded = !acceptsKeyboardInput

      setupClickMonitor()
      setupKeyMonitor()

      if parentWindow !== window {
        parentWindow?.removeChildWindow(menuPanel)
        window.addChildWindow(menuPanel, ordered: .above)
        parentWindow = window
      }
      menuPanel.level = window.level
      DropdownPanelSession.shared.activate(menuPanel, parent: window) { [weak self] in
        self?.dismiss()
        DispatchQueue.main.async { [weak self] in self?.isPresented = false }
      }

      if needsLayout {
        menuHostingView.frame.size.width = menuWidth
        menuHostingView.layoutSubtreeIfNeeded()
        let fittingHeight = min(max(menuHostingView.fittingSize.height, 40), 320)
        menuPanel.setContentSize(NSSize(width: menuWidth, height: fittingHeight))
        lastContentRevision = contentRevision
        lastMenuWidth = menuWidth
      }
      position(menuPanel, relativeTo: anchorView, placement: placement)

      if opensOnHover {
        setupHoverMonitor()
      } else {
        removeHoverMonitor()
      }
      if !menuPanel.isVisible {
        if acceptsKeyboardInput { menuPanel.makeKeyAndOrderFront(nil) }
        else { menuPanel.orderFront(nil) }
      }
    }

    func dismiss() {
      cancelDismissal()
      removeClickMonitor()
      removeHoverMonitor()
      removeKeyMonitor()
      guard let panel else { return }
      let restoreParentFocus = panel.isKeyWindow
      DropdownPanelSession.shared.remove(panel)
      lastContentRevision = nil

      for child in panel.childWindows ?? [] {
        panel.removeChildWindow(child)
        child.orderOut(nil)
      }
      parentWindow?.removeChildWindow(panel)
      panel.orderOut(nil)
      if restoreParentFocus { parentWindow?.makeKey() }
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
      let frame = DropdownPanelLayout.frame(anchor: boundsInScreen, size: panel.frame.size,
                                            visibleFrame: visibleFrame, placement: placement)
      if panel.frame.origin != frame.origin { panel.setFrameOrigin(frame.origin) }
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

    private func setupKeyMonitor() {
      guard keyMonitor == nil else { return }
      keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self, let panel = self.panel, panel.isVisible,
          event.window === panel || event.window === self.parentWindow,
          event.keyCode == 53,
          event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        else { return event }
        self.isPresented = false
        self.dismiss()
        return nil
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
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120), execute: workItem)
    }

    private func pointerIsInsidePanelOrAnchor(_ location: NSPoint) -> Bool {
      if let panel, containsMouse(location, in: panel) {
        return true
      }

      guard let anchorView, let window = anchorView.window else { return false }
      let boundsInWindow = anchorView.convert(anchorView.bounds, to: nil)
      let boundsInScreen = window.convertToScreen(boundsInWindow)
      if boundsInScreen.insetBy(dx: -2, dy: -2).contains(location) { return true }
      guard let panel else { return false }
      return DropdownPanelLayout.hoverBridge(anchor: boundsInScreen, panel: panel.frame).contains(location)
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

    private func removeKeyMonitor() {
      if let keyMonitor {
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
      }
    }
  }
}

/// Searchable custom menus can take focus without changing ordinary hover menus.
private final class DropdownMenuPanel: NSPanel {
  var acceptsKeyboardInput = false
  override var canBecomeKey: Bool { acceptsKeyboardInput }
}

/// The geometry anchor is behind the SwiftUI button and must never take its clicks.
private final class DropdownAnchorView: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
