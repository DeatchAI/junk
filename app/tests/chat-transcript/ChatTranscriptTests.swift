import AppKit
import SwiftUI

@main struct ChatTranscriptTests {
  @MainActor static func main() throws {
    let parts = [
      MessagePart(type: "text", text: "I’ll check the build and review the changed files."),
      MessagePart(type: "activity", text: "/Users/you/Projects/app/Example.swift", title: "Read Example.swift", kind: "read", status: "completed"),
      MessagePart(type: "activity", title: "Ran command", kind: "command", status: "completed",
        command: "/bin/zsh -lc 'xcodebuild -project app/detach.xcodeproj -scheme lazzy build'",
        output: String(repeating: "Build diagnostic output\n", count: 100)),
      MessagePart(type: "activity", text: "Example.swift", title: "Updated files", kind: "file_change", status: "completed"),
      MessagePart(type: "text", text: "The build passed. The chat now keeps replies readable, with command details available when you need them."),
    ]
    let decoded = try JSONDecoder().decode([MessagePart].self, from: JSONEncoder().encode(parts))
    assert(decoded == parts, "Tool details must survive the history transport")
    let segments = ChatTranscript.segments(parts)
    assert(segments.count == 3 && segments[1].parts.count == 3)
    assert(segments[1].summary == "Read files, ran commands")
    let prose = ChatTranscript.readableText(parts)
    assert(!prose.contains("xcodebuild") && !prose.contains("diagnostic"), "Copy reply excludes tool payloads")
    let failed = MessagePart(type: "activity", title: "Ran command", kind: "command", status: "failed")
    assert(ChatTranscript.segments([failed])[0].summary.contains("failed"), "Failures stay visible while collapsed")
    let literalCode = "```shell\n[Command]\necho hello\n```"
    assert(ChatTranscript.parts(text: literalCode, structured: nil).first?.text == literalCode)
    assert(ChatTranscript.parts(text: "Legacy answer", structured: [MessagePart(type: "unknown")]).first?.text == "Legacy answer")
    let payload = Data("{\"command\":\"echo hello\",\"output\":\"hello\",\"exitCode\":0,\"ok\":true,\"extra\":[null,{}]}".utf8)
    let details = try JSONDecoder().decode([String: ActivityJSONValue].self, from: payload)
    assert(details["command"]?.displayText == "echo hello")
    assert(ActivityJSONValue.object(details).displayText.contains("exitCode"))
    print("Chat transcript grouping, failure visibility, copy text and detail decoding passed")

    guard CommandLine.arguments.count > 1 else { return }
    _ = NSApplication.shared
    let output = URL(fileURLWithPath: CommandLine.arguments[1])
    for preset in [ThemePreset.lazzywhite, .lazzydark] {
      UserDefaults.standard.setVolatileDomain([
        "appearance_preset": preset.rawValue, "appearance_mode": AppearanceMode.solid.rawValue,
      ], forName: UserDefaults.argumentDomain)
      ThemeManager.shared.refreshFromSettings()
      let bounds = NSRect(x: 0, y: 0, width: 520, height: 320)
      let view = ChatTranscriptView(parts: parts).padding(24)
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .background(ThemeManager.shared.backgroundColor)
      let host = NSHostingView(rootView: view)
      let window = NSWindow(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
      window.contentView = host; host.frame = bounds; host.layoutSubtreeIfNeeded()
      RunLoop.current.run(until: Date().addingTimeInterval(0.7))
      guard let bitmap = host.bitmapImageRepForCachingDisplay(in: bounds) else { fatalError("No bitmap") }
      host.cacheDisplay(in: bounds, to: bitmap)
      let png = bitmap.representation(using: .png, properties: [:])!
      try png.write(to: output.appendingPathComponent(preset == .lazzydark ? "chat-dark.png" : "chat-light.png"))
      withExtendedLifetime(window) {}
    }
    print("Rendered the actual SwiftUI transcript in light and dark themes")
  }
}
