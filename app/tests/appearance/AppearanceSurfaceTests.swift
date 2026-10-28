import AppKit
import SwiftUI

@main struct AppearanceSurfaceTests {
  @MainActor static func main() {
    assert(Bundle.main.bundleIdentifier == "local.detach.appearance-checks")
    if CommandLine.arguments.contains("--check-saved-translucency") {
      assert(AppearanceSettings.glassTranslucency == 0.37)
      assert(ThemeManager.shared.glassTranslucency == 0.37)
      print("Saved translucency restored in a fresh process")
      return
    }
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    // This executable has an isolated bundle identifier, never Detach's preferences.
    let theme = ThemeManager.shared
    for (input, expected) in [(-1.0, 0.0), (2.0, 1.0), (.nan, 0.6), (.infinity, 0.6)] {
      theme.updateGlassTranslucency(input)
      assert(theme.glassTranslucency == expected, "Stored translucency must remain finite and bounded")
    }
    theme.updatePreset(.lazzydark)
    theme.updateMode(.solid)
    let probe = EditorProbe()
    let host = FirstClickHostingView(rootView: SurfaceFixture(probe: probe))
    let bounds = CGRect(x: 0, y: 0, width: 420, height: 80)
    let window = NSWindow(contentRect: bounds, styleMask: .borderless,
                          backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.contentView = host
    host.frame = bounds
    pump(host)
    guard let editor = probe.editor else { fatalError("The native editor must be mounted") }
    editor.stringValue = "Keep this draft while changing appearance"
    assert(window.makeFirstResponder(editor))
    let responder = window.firstResponder

    for preset in [ThemePreset.lazzydark, .lazzywhite] {
      theme.updatePreset(preset)
      assert(theme.surfaceColorScheme == (preset == .lazzydark ? .dark : .light))
      for mode in AppearanceMode.allCases + [.solid] {
        theme.updateMode(mode)
        pump(host)
        assert(AppearanceSettings.appearanceMode == mode, "Style selection must persist")
        assert(probe.editor === editor && probe.creationCount == 1,
               "Appearance changes must retain the native editor")
        assert(editor.stringValue == "Keep this draft while changing appearance")
        assert(window.firstResponder === responder, "Changing material must preserve focus")
        assert(host.fittingSize == bounds.size, "Materials must not change composer dimensions")
        assert(host.acceptsFirstMouse(for: nil))
        if mode == .liquidGlass {
          for translucency in [0.0, 0.25, 0.6, 1.0] {
            theme.updateGlassTranslucency(translucency)
            pump(host)
            assert(AppearanceSettings.glassTranslucency == translucency)
            assert(probe.editor === editor && probe.creationCount == 1)
            assert(editor.stringValue == "Keep this draft while changing appearance")
            assert(window.firstResponder === responder)
            assert(host.fittingSize == bounds.size)
          }
        }
      }
    }
    theme.updatePreset(.system)
    assert(theme.surfaceColorScheme == nil, "System theme must inherit the window appearance")
    theme.resetToDefaults()
    assert(theme.glassTranslucency == AppearanceSettings.defaultGlassTranslucency)
    theme.updateGlassTranslucency(0.37)
    UserDefaults.standard.synchronize()
    window.orderOut(nil)
    print("Appearance checks passed: saved style and translucency, bounds and reset, stable editor and draft, focus, dimensions, light/dark themes")
  }

  @MainActor private static func pump(_ host: NSView) {
    RunLoop.current.run(until: Date().addingTimeInterval(0.03))
    host.layoutSubtreeIfNeeded()
  }
}

@MainActor private final class EditorProbe: ObservableObject {
  weak var editor: NSTextField?
  var creationCount = 0
}

private struct SurfaceFixture: View {
  @ObservedObject var probe: EditorProbe
  var body: some View {
    NativeEditor(probe: probe)
      .padding(14)
      .frame(width: 420, height: 80)
      .themedSurface(in: RoundedRectangle(cornerRadius: 12))
  }
}

private struct NativeEditor: NSViewRepresentable {
  let probe: EditorProbe
  func makeNSView(context: Context) -> NSTextField {
    let editor = NSTextField()
    probe.editor = editor
    probe.creationCount += 1
    return editor
  }
  func updateNSView(_ view: NSTextField, context: Context) {}
}
