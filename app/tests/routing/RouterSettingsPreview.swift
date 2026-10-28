import AppKit
import SwiftUI
@testable import Detach

/// Offscreen production Settings components with synthetic catalogs; no network or agent process.
@main struct RouterSettingsPreview {
  @MainActor static func main() throws {
    _ = NSApplication.shared
    let output = URL(fileURLWithPath: CommandLine.arguments[1])
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let manager = WebSocketManager()
    manager.session?.invalidateAndCancel()
    manager.session = nil
    manager.agentCapabilities = ["codex", "claude"].map { agent in
      AgentCapability(id: agent, displayName: agent.capitalized, installed: true,
        executablePath: nil, authHint: nil,
        models: [AgentModelCapability(id: "example-model", displayName: "Example model",
          reasoningEfforts: ["low", "medium", "high"], defaultReasoningEffort: "medium", reasoningLabel: "Reasoning")], defaultModel: "example-model")
    }
    var configuration = RouterConfiguration()
    configuration.preferences["ui"] = RouterPreset(agent: "claude", model: "example-model", effort: "medium")
    for (name, preset) in [("dark", ThemePreset.lazzydark), ("light", ThemePreset.lazzywhite)] {
      UserDefaults.standard.setVolatileDomain([
        RouterConfiguration.storageKey: try JSONEncoder().encode(configuration),
        "appearance_preset": preset.rawValue, "appearance_mode": AppearanceMode.solid.rawValue,
      ], forName: UserDefaults.argumentDomain)
      ThemeManager.shared.refreshFromSettings()
      AutoRouter.shared.configuration = configuration
      let bounds = NSRect(x: 0, y: 0, width: 680, height: 760)
      let view = RouterSettingsView(wsManager: manager)
        .environment(\.colorScheme, name == "dark" ? .dark : .light)
        .padding(26).frame(width: bounds.width, height: bounds.height)
        .background(ThemeManager.shared.backgroundColor)
      let host = NSHostingView(rootView: view)
      let window = NSWindow(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
      window.appearance = NSAppearance(named: name == "dark" ? .darkAqua : .aqua)
      window.contentView = host
      host.frame = bounds
      host.layoutSubtreeIfNeeded()
      RunLoop.current.run(until: Date().addingTimeInterval(0.8))
      guard let bitmap = host.bitmapImageRepForCachingDisplay(in: bounds) else { fatalError("No settings bitmap") }
      host.cacheDisplay(in: bounds, to: bitmap)
      try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("router-\(name).png"))
      let classification = RouterClassification(kind: .ui, complexity: "standard", candidateID: "fixture",
        confidence: 0.91, decisionModel: "jev-fixture")
      let selection = RouterSelection(preset: .init(agent: "claude", model: "example-model", effort: "medium"),
        kind: .ui, confidence: 0.91, reason: "Used your UI and design preference.", decisionModel: "jev-fixture")
      let result = RouterEvaluation(classification: classification, selection: selection, usedFallback: false, summary: selection.reason)
      let resultView = VStack(alignment: .leading, spacing: 16) {
        Text("Test result · synthetic preview").font(.system(size: 16, weight: .semibold))
        RouterTestResultView(result: result)
      }
      .foregroundStyle(ThemeManager.shared.textColor)
      .environment(\.colorScheme, name == "dark" ? .dark : .light)
      .padding(26).frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
      .background(ThemeManager.shared.backgroundColor)
      let resultHost = NSHostingView(rootView: resultView)
      window.contentView = resultHost
      resultHost.frame = bounds
      resultHost.layoutSubtreeIfNeeded()
      RunLoop.current.run(until: Date().addingTimeInterval(0.4))
      let resultBitmap = resultHost.bitmapImageRepForCachingDisplay(in: bounds)!
      resultHost.cacheDisplay(in: bounds, to: resultBitmap)
      try resultBitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("result-\(name).png"))
      withExtendedLifetime(window) {}
    }
    print("Rendered production Auto router settings in light and dark themes with synthetic catalogs")
  }
}
