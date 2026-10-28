import AppKit
import SwiftUI

/// Only the empty header space moves Settings; content controls keep their drags.
struct SettingsWindowDragRegion: NSViewRepresentable {
  func makeNSView(context: Context) -> SettingsHeaderDragView {
    SettingsHeaderDragView()
  }

  func updateNSView(_ view: SettingsHeaderDragView, context: Context) {}
}

final class SettingsHeaderDragView: NSView {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  override func mouseDown(with event: NSEvent) {
    window?.performDrag(with: event)
  }
}
