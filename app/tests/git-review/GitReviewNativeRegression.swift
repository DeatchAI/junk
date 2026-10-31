import AppKit
import SwiftUI
#if !GIT_REVIEW_STANDALONE
@testable import Detach
#endif

@MainActor final class GitReviewRegressionDelegate: NSObject, NSApplicationDelegate {
  private var child: Process?
  private var owner: GitChangeWindowController?
  private var directory: URL?

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent("detach-git-native-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      self.directory = directory
      let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("GitReviewPreviewServer.ts")
      let process = Process(), output = Pipe()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = ["bun", script.path]
      var environment = ProcessInfo.processInfo.environment
      environment["PATH"] = FileManager.default.homeDirectoryForCurrentUser.path + "/.bun/bin:/opt/homebrew/bin:/usr/bin:/bin"
      environment["DETACH_GIT_PREVIEW_DIR"] = directory.path
      environment["DETACH_RUNTIME_TOKEN"] = ServerConfig.runtimeToken
      process.environment = environment; process.standardOutput = output; process.standardError = FileHandle.standardError
      try process.run(); child = process
      let ready = output.fileHandleForReading.availableData
      let info = try JSONSerialization.jsonObject(with: ready) as! [String: Any]
      ServerConfig.updatePort(info["port"] as! Int)
      let workspace = info["workspace"] as! String
      let model = GitReviewModel(workspace: workspace, runID: "native-preview", path: "UI/Composer.swift")
      owner = GitChangeWindowController(model: model)
      owner?.window?.setContentSize(NSSize(width: 960, height: 680))
      owner?.showWindow(nil); owner?.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
      Task { await check(model, workspace: workspace) }
    } catch { finish(error: error.localizedDescription) }
  }

  private func check(_ model: GitReviewModel, workspace: String) async {
    await model.refresh()
    for _ in 0..<40 {
      if model.review != nil, !model.isLoading { break }
      try? await Task.sleep(for: .milliseconds(25))
    }
    guard model.review?.files.count == 3, model.canDiscardTask else { finish(error: model.error ?? "Review did not load"); return }
    guard let window = owner?.window, !window.styleMask.contains(.titled), window.canBecomeKey,
      window.standardWindowButton(.closeButton) == nil else { finish(error: "Window has native title chrome"); return }
    ThemeManager.shared.preset = .lazzywhite
    try? await Task.sleep(for: .milliseconds(250))
    func textViews(_ view: NSView) -> [NSTextView] {
      (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
    }
    let code = owner?.window?.contentView.map(textViews) ?? []
    guard code.count == 2, code.allSatisfy({ !$0.string.isEmpty && ($0.layoutManager?.numberOfGlyphs ?? 0) > 0 }) else {
      let details = code.map { "text=\($0.string.count), storage=\($0.textStorage?.length ?? -1), glyphs=\($0.layoutManager?.numberOfGlyphs ?? -1), frame=\($0.frame)" }.joined(separator: "; ")
      finish(error: "Code text is missing from \(code.count) split diff panes: \(details)"); return
    }
    capture("review")
    ThemeManager.shared.preset = .lazzydark
    try? await Task.sleep(for: .milliseconds(200))
    capture("review-dark")
    model.conversationID = "preview-chat"; model.sessionScope = true
    await model.refresh()
    guard model.review?.files.count == 3, !model.canDiscardTask else { finish(error: model.error ?? "Chat review did not load"); return }
    try? await Task.sleep(for: .milliseconds(200))
    capture("session-dark")
    let card = NSWindow(contentRect: NSRect(x: 80, y: 100, width: 520, height: 340), styleMask: [.titled], backing: .buffered, defer: false)
    card.isReleasedWhenClosed = false
    card.contentView = NSHostingView(rootView: GitTaskChangeCard(workspace: workspace, runID: "native-preview", conversationID: "preview-chat",
      prompt: "Add change review", timestamp: nil).padding(18).frame(width: 520).background(ThemeManager.shared.solidBackground))
    card.orderFront(nil)
    try? await Task.sleep(for: .milliseconds(250))
    capture("card", view: card.contentView)
    card.close()
    model.sessionScope = false; await model.refresh()
    await model.prepare(paths: ["UI/Composer.swift"])
    guard model.preview != nil else { finish(error: model.error ?? "No confirmation preview"); return }
    try? await Task.sleep(for: .milliseconds(250))
    capture("confirmation")
    await model.confirm()
    let path = URL(fileURLWithPath: workspace).appendingPathComponent("UI/Composer.swift")
    guard (try? String(contentsOf: path, encoding: .utf8))?.contains("Before") == true else { finish(error: model.error ?? "Discard failed"); return }
    await model.prepare(undo: true)
    guard model.preview?.isUndo == true else { finish(error: model.error ?? "Undo unavailable"); return }
    await model.confirm()
    guard (try? String(contentsOf: path, encoding: .utf8))?.contains("Review changes") == true else { finish(error: model.error ?? "Undo failed"); return }
    model.sessionScope = true
    await model.refresh()
    await model.prepare()
    guard model.preview?.isSession == true else { finish(error: model.error ?? "No session revert confirmation"); return }
    try? await Task.sleep(for: .milliseconds(250))
    capture("session-confirmation")
    await model.confirm()
    guard (try? String(contentsOf: path, encoding: .utf8))?.contains("Before") == true,
      !FileManager.default.fileExists(atPath: URL(fileURLWithPath: workspace).appendingPathComponent("UI/Changes.swift").path) else {
      finish(error: model.error ?? "Session revert failed"); return
    }
    await model.prepare(undo: true); await model.confirm()
    guard (try? String(contentsOf: path, encoding: .utf8))?.contains("Review changes") == true else {
      finish(error: model.error ?? "Session Undo failed"); return
    }
    let working = GitWorkingModel()
    await working.refresh(workspace: workspace)
    guard working.status?.canCommit == true,
      await working.commit(workspace: workspace, scope: "session", id: "preview-chat", paths: ["UI/Changes.swift"], message: "Add review file") else {
      finish(error: working.error ?? "Native commit failed"); return
    }
    guard await working.push(workspace: workspace, remote: "origin"), working.status?.upstream == "origin/main" else {
      finish(error: working.error ?? "Native push to the fixture remote failed"); return
    }
    owner?.window?.setContentSize(NSSize(width: 700, height: 580))
    try? await Task.sleep(for: .milliseconds(200))
    capture("narrow")
    finish(error: nil)
  }

  private func capture(_ name: String, view explicitView: NSView? = nil) {
    guard let view = explicitView ?? (["confirmation", "session-confirmation"].contains(name) ? owner?.window?.attachedSheet?.contentView : nil) ?? owner?.window?.contentView,
      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let output = outputDirectory
    try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("\(name).png"))
  }

  private func finish(error: String?) {
    let output = outputDirectory
    try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let result: [String: Any] = ["passed": error == nil, "error": error ?? "", "scope": "Borderless review, native Git commit/push to a local fixture remote, task/session revert and Undo, light/dark rendering"]
    try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted]).write(to: output.appendingPathComponent("result.json"))
    NSApp.terminate(nil)
  }

  private var outputDirectory: URL {
    URL(fileURLWithPath: ProcessInfo.processInfo.environment["DETACH_GIT_REVIEW_OUTPUT"] ?? "/tmp/detach-git-review-native")
  }

  func applicationWillTerminate(_ notification: Notification) {
    if child?.isRunning == true { child?.terminate() }
    child?.waitUntilExit()
    if let directory { try? FileManager.default.removeItem(at: directory) }
  }
}

@main struct GitReviewRegressionApp {
  @MainActor static func main() {
    let app = NSApplication.shared, delegate = GitReviewRegressionDelegate()
    app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
    withExtendedLifetime(delegate) {}
  }
}
