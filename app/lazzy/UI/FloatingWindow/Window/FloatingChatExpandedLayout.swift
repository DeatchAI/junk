import SwiftUI

/// The transcript receives only the space left above the composer. Keeping
/// these surfaces out of the same intrinsic-height stack prevents long native
/// text views from pushing the input below the window's viewport.
struct FloatingChatExpandedLayout<Transcript: View, Composer: View>: View {
  @ViewBuilder var transcript: Transcript
  @ViewBuilder var composer: Composer
  @State private var composerHeight: CGFloat = 0

  var body: some View {
    GeometryReader { viewport in
      transcript
        .frame(
          width: viewport.size.width,
          height: max(0, viewport.size.height - composerHeight - 12),
          alignment: .top
        )
        .clipped()
        .frame(height: viewport.size.height, alignment: .top)
        .overlay(alignment: .bottom) {
          composer
            .fixedSize(horizontal: false, vertical: true)
            .background {
              GeometryReader { geometry in
                Color.clear.preference(key: ComposerHeightKey.self, value: geometry.size.height)
              }
            }
        }
    }
    .onPreferenceChange(ComposerHeightKey.self) { height in
      if abs(composerHeight - height) > 0.5 { composerHeight = height }
    }
  }

  private struct ComposerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
      value = max(value, nextValue())
    }
  }
}
