import AppKit
import SwiftUI

@MainActor final class GitChangeWindowController: NSWindowController, NSWindowDelegate {
  private static var windows: [String: GitChangeWindowController] = [:]
  let model: GitReviewModel
  private weak var sourceWindow: NSWindow?

  static func open(workspace: String, runID: String? = nil, path: String? = nil, discard: Bool = false,
                   conversationID: String? = nil, revertSession: Bool = false, undo: Bool = false,
                   endpoint: RuntimeEndpoint? = nil) {
    let endpoint = endpoint ?? .local
    let source = NSApp.keyWindow
    let identity = URL(fileURLWithPath: workspace).standardizedFileURL.resolvingSymlinksInPath().path
    let scope = "|\(endpoint.machineID?.uuidString ?? "local")|\(conversationID ?? runID ?? "project")"
    let owner: GitChangeWindowController
    if let existing = windows[identity + scope] {
      owner = existing
      owner.model.runID = runID; owner.model.projectScope = runID == nil
      owner.model.conversationID = conversationID; owner.model.sessionScope = conversationID != nil && (!discard || revertSession)
      if let path { owner.model.selectedPath = path }
    } else {
      owner = GitChangeWindowController(model: GitReviewModel(workspace: identity, runID: runID,
        path: path, conversationID: conversationID, endpoint: endpoint))
      owner.model.sessionScope = conversationID != nil && (!discard || revertSession)
      windows[identity + scope] = owner
    }
    if source !== owner.window { owner.sourceWindow = source }
    owner.showWindow(nil); owner.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    Task {
      await owner.model.refresh()
      if let root = owner.model.review?.repository?.root {
        if let existing = windows[root + scope], existing !== owner {
          existing.model.runID = runID; existing.model.projectScope = runID == nil
          existing.model.conversationID = conversationID; existing.model.sessionScope = conversationID != nil && (!discard || revertSession)
          existing.model.selectedPath = path; existing.sourceWindow = source
          owner.close(); windows[identity + scope] = existing
          existing.showWindow(nil); existing.window?.makeKeyAndOrderFront(nil)
          await existing.model.refresh()
          if discard { await existing.model.prepare(undo: undo) }
          return
        }
        windows[root + scope] = owner
      }
      if discard { await owner.model.prepare(undo: undo) }
    }
  }

  init(model: GitReviewModel) {
    self.model = model
    let bounds = (NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)).insetBy(dx: 24, dy: 24)
    let window = GitReviewWindow(contentRect: NSRect(x: bounds.midX - min(1180, bounds.width) / 2,
      y: bounds.midY - min(760, bounds.height) / 2, width: min(1180, bounds.width), height: min(760, bounds.height)),
      styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
    window.title = "Changes · \(URL(fileURLWithPath: model.workspace).lastPathComponent)"
    window.contentMinSize = NSSize(width: min(760, bounds.width), height: min(480, bounds.height))
    window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
    window.isMovableByWindowBackground = false
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.delegate = self
    let host = NSHostingView(rootView: GitReviewView(model: model, onClose: { [weak self] in self?.close() },
      onZoom: { [weak window] in window?.zoom(nil) }))
    host.sizingOptions = []
    window.contentView = host
    window.setFrameAutosaveName("DetachGitReviewBorderless")
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func windowDidBecomeKey(_ notification: Notification) { Task { await model.refresh() } }
  func windowWillClose(_ notification: Notification) {
    if sourceWindow?.isVisible == true { sourceWindow?.makeKeyAndOrderFront(nil) }
  }
}

final class GitReviewWindow: NSWindow {
  private var previousFrame: NSRect?
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  override func zoom(_ sender: Any?) {
    if let frame = previousFrame { previousFrame = nil; setFrame(frame, display: true, animate: true) }
    else if let visible = screen?.visibleFrame {
      previousFrame = frame
      setFrame(visible.insetBy(dx: 16, dy: 16), display: true, animate: true)
    }
  }
}
