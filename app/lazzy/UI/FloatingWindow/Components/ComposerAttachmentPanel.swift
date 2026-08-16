import AppKit
import SwiftUI

enum ComposerAttachmentMenuPage: Equatable {
  case root
  case files
  case browserTabs
  case skills
  case discoverSkills
  case remoteSkillDetail
  case mcpServers
}

/// Hosts the attachment picker in its own borderless panel. A separate panel is
/// required because content drawn inside the chat window cannot extend beyond
/// that window without covering the composer or response area.
struct ComposerAttachmentPanelAnchor<MenuContent: View>: NSViewRepresentable {
  @Binding var isPresented: Bool
  let preferredWidth: CGFloat
  /// Most picker state is owned inside the detached SwiftUI host. Refresh the
  /// root only when the page or another caller-owned mode value changes.
  /// File results are observed inside the host so AppKit does not continuously
  /// reorder and reposition the panel while the user types.
  let contentRefreshID: AnyHashable?
  let menu: MenuContent

  func makeCoordinator() -> Coordinator {
    Coordinator()
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
        preferredWidth: preferredWidth,
        contentRefreshID: contentRefreshID,
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
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private weak var parentWindow: NSWindow?
    private var lastContentRefreshID: AnyHashable?
    private var lastPreferredWidth: CGFloat?

    func present(
      menu: MenuContent,
      preferredWidth: CGFloat,
      contentRefreshID: AnyHashable?,
      from anchorView: NSView
    ) {
      guard let window = anchorView.window else { return }

      let shouldRefreshContent = hostingView == nil || lastContentRefreshID != contentRefreshID
      let hostingView: NSHostingView<AnyView>
      if let existingHostingView = self.hostingView {
        hostingView = existingHostingView
        if shouldRefreshContent {
          hostingView.rootView = AnyView(menu.padding(22))
        }
      } else {
        hostingView = NSHostingView(rootView: AnyView(menu.padding(22)))
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        self.hostingView = hostingView
      }
      lastContentRefreshID = contentRefreshID

      let menuPanel: NSPanel
      let isNewPanel: Bool
      if let panel {
        menuPanel = panel
        isNewPanel = false
      } else {
        menuPanel = KeyablePanel(
          contentRect: .zero,
          styleMask: [.borderless],
          backing: .buffered,
          defer: false
        )
        menuPanel.isOpaque = false
        menuPanel.backgroundColor = .clear
        menuPanel.hasShadow = false
        menuPanel.hidesOnDeactivate = false
        menuPanel.isFloatingPanel = true
        menuPanel.becomesKeyOnlyIfNeeded = false
        menuPanel.level = window.level
        menuPanel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        menuPanel.contentView = hostingView
        panel = menuPanel
        isNewPanel = true
      }

      let parentWindowChanged = parentWindow !== window
      if parentWindow !== window {
        parentWindow?.removeChildWindow(menuPanel)
        window.addChildWindow(menuPanel, ordered: .above)
        parentWindow = window
      }

      let widthChanged = lastPreferredWidth == nil
        || abs((lastPreferredWidth ?? preferredWidth) - preferredWidth) > 0.5
      let shouldRelayout = shouldRefreshContent || isNewPanel || parentWindowChanged || widthChanged
      var sizeChanged = false

      if shouldRelayout {
        hostingView.frame.size.width = preferredWidth + 44
        hostingView.layoutSubtreeIfNeeded()
        let fittingHeight = min(max(hostingView.fittingSize.height, 80), 390)
        let targetSize = NSSize(width: preferredWidth + 44, height: fittingHeight)
        let currentSize = menuPanel.contentView?.bounds.size ?? .zero
        sizeChanged = abs(currentSize.width - targetSize.width) > 0.5
          || abs(currentSize.height - targetSize.height) > 0.5
        if sizeChanged {
          menuPanel.setContentSize(targetSize)
        }
        if isNewPanel || parentWindowChanged || sizeChanged {
          position(menuPanel, relativeTo: anchorView)
        }
      }
      lastPreferredWidth = preferredWidth
      if !menuPanel.isVisible {
        menuPanel.orderFront(nil)
      }
    }

    func dismiss() {
      guard let panel else { return }
      parentWindow?.removeChildWindow(panel)
      panel.orderOut(nil)
      self.panel = nil
      hostingView = nil
      parentWindow = nil
      lastContentRefreshID = nil
      lastPreferredWidth = nil
    }

    private func position(_ panel: NSPanel, relativeTo anchorView: NSView) {
      guard let window = anchorView.window else { return }
      let boundsInWindow = anchorView.convert(anchorView.bounds, to: nil)
      let boundsInScreen = window.convertToScreen(boundsInWindow)
      let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
      let panelSize = panel.frame.size

      // Align visual menu left (with 22pt transparent padding) to anchorView left with a 12pt visual inset:
      // origin.x + 22 = boundsInScreen.minX + 12 => origin.x = boundsInScreen.minX - 10
      var originX = boundsInScreen.minX - 10

      // Position the visual top of the menu to overlap just below the top of the input view (14pt overlay):
      // origin.y + panelSize.height - 22 = boundsInScreen.maxY - 14 => origin.y = boundsInScreen.maxY - panelSize.height + 8
      var originY = boundsInScreen.maxY - panelSize.height + 8

      originX = min(max(originX, visibleFrame.minX), visibleFrame.maxX - panelSize.width)
      originY = min(max(originY, visibleFrame.minY), visibleFrame.maxY - panelSize.height)
      panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
  }
}

/// Compact custom menu content rendered inside the detached attachment panel.
