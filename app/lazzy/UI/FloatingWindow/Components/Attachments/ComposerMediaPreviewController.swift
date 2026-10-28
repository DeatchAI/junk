import AppKit
import QuickLookUI

/// A reusable native preview window for original image and video attachments.
@MainActor
final class ComposerMediaPreviewController: NSObject, NSWindowDelegate {
  static let shared = ComposerMediaPreviewController()
  private var panel: NSPanel?
  private var preview: QLPreviewView?
  private var scopedURL: URL?

  func show(_ attachment: ChatAttachment) {
    guard attachment.isMedia else { return }
    let url = URL(fileURLWithPath: attachment.fileRequest.path)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    scopedURL?.stopAccessingSecurityScopedResource()
    if url.startAccessingSecurityScopedResource() { scopedURL = url }
    else { scopedURL = nil }

    if panel == nil {
      let visibleFrame = NSApp.keyWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
      let size = NSSize(width: min(860, visibleFrame.width - 80), height: min(620, visibleFrame.height - 80))
      let window = NSPanel(contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.isFloatingPanel = true
      window.hidesOnDeactivate = false
      window.level = NSApp.keyWindow?.level ?? .floating
      window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
      window.minSize = NSSize(width: 320, height: 240)
      window.delegate = self
      let view = QLPreviewView(frame: NSRect(origin: .zero, size: size), style: .normal)!
      view.autoresizingMask = [.width, .height]
      view.autostarts = false
      view.shouldCloseWithWindow = false
      window.contentView = view
      window.center()
      preview = view
      panel = window
    }
    panel?.title = attachment.fileName
    preview?.previewItem = url as NSURL
    panel?.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    preview?.close()
    preview = nil
    panel = nil
    scopedURL?.stopAccessingSecurityScopedResource()
    scopedURL = nil
  }
}
