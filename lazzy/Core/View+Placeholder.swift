import SwiftUI

extension View {
  /// Adds a custom placeholder to a view (typically a TextField or SecureField).
  /// - Parameters:
  ///   - when: A boolean indicating whether the placeholder should be shown.
  ///   - alignment: The alignment of the placeholder within the ZStack.
  ///   - placeholder: A ViewBuilder that produces the placeholder content.
  func placeholder<Content: View>(
    when shouldShow: Bool,
    alignment: Alignment = .leading,
    @ViewBuilder placeholder: () -> Content
  ) -> some View {
    ZStack(alignment: alignment) {
      placeholder()
        .opacity(shouldShow ? 1 : 0)
        .allowsHitTesting(false)
      self
    }
  }
}
