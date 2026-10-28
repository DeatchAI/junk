import AppKit
import SwiftUI

/// Exercise the production viewport with real native text and scroll views.
/// Nothing is submitted to an agent or displayed over the user's workspace.
@MainActor enum ExpandedViewportTests {
  static func run() {
    let panel = FloatingComposerPanel(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
    )
    panel.fixedContentWidth = 520
    panel.isMovableByWindowBackground = true

    for lines in [1, 80, 400] {
      let measurement = ViewportMeasurement()
      let state = ComposerFixtureState()
      let host = FirstClickHostingView(rootView: ViewportFixture(
        lines: lines, state: state, measurement: measurement
      ))
      host.sizingOptions = []
      host.autoresizingMask = [.width, .height]
      panel.contentView = host

      // Resize the same mounted host, including a window restored at a height
      // different from the controller's old expanded-height value.
      for height: CGFloat in [700, 420, 280, 600] {
        for composerHeight: CGFloat in [148, min(330, height - 40)] {
          state.height = composerHeight
          panel.setContentSize(NSSize(width: 520, height: height))
          for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
          }
          guard let composer = measurement.frames["composer"],
            let transcript = measurement.frames["transcript"]
          else { fatalError("Native viewport geometry was not measured") }
          assert(abs(composer.maxY - (height - 8)) < 1, "Composer must stay at the bottom after resizing")
          assert(composer.minY >= 8, "The entire composer must fit inside the panel")
          assert(abs(composer.height - composerHeight) < 1, "Multiline input and attachments must retain their height")
          assert(transcript.maxY <= composer.minY - 11, "History must scroll above the composer")
          assert(abs(transcript.minY - 8) < 1, "No invisible area above the transcript")
          if lines > 1 {
            let scroll = descendants(of: host).compactMap { $0 as? NSScrollView }
              .first { ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height + 10 }
            guard let scroll, let document = scroll.documentView else {
              fatalError("Long history must overflow a scroll viewport instead of the panel")
            }
            scroll.contentView.scroll(to: NSPoint(x: 0, y: document.bounds.maxY - scroll.contentView.bounds.height))
            scroll.reflectScrolledClipView(scroll.contentView)
            assert(scroll.contentView.bounds.maxY >= document.bounds.maxY - 1, "The end of history must remain reachable")
          }
        }
      }
    }
    print("Native expanded viewport passed: long history, composer growth, attachments and mounted-host resizing")
  }

  private static func descendants(of view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants(of: $0) }
  }
}

private final class ComposerFixtureState: ObservableObject {
  @Published var height: CGFloat = 148
}

private final class ViewportMeasurement {
  var frames: [String: CGRect] = [:]
}

private struct ViewportFramesKey: PreferenceKey {
  static var defaultValue: [String: CGRect] { [:] }
  static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
  }
}

private extension View {
  func measureViewportFrame(_ name: String) -> some View {
    background {
      GeometryReader { geometry in
        Color.clear.preference(key: ViewportFramesKey.self, value: [name: geometry.frame(in: .global)])
      }
    }
  }
}

private struct ViewportFixture: View {
  let lines: Int
  @ObservedObject var state: ComposerFixtureState
  let measurement: ViewportMeasurement

  var body: some View {
    FloatingChatExpandedLayout {
      ScrollView {
        Text(String(repeating: "A long conversation with multiple paragraphs.\n", count: lines))
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .measureViewportFrame("transcript")
    } composer: {
      NativeEditorFixture()
        .frame(height: state.height)
        .measureViewportFrame("composer")
    }
    .padding(8)
    .frame(width: 520)
    .onPreferenceChange(ViewportFramesKey.self) { measurement.frames = $0 }
  }
}

private struct NativeEditorFixture: NSViewRepresentable {
  func makeNSView(context: Context) -> NSScrollView {
    let editor = NSTextView()
    editor.string = "Anything .."
    let scroll = NSScrollView()
    scroll.documentView = editor
    return scroll
  }

  func updateNSView(_ view: NSScrollView, context: Context) {}
}
