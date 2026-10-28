import SwiftUI

struct WorkingDirectoryTray: View {
  @ObservedObject var store: WorkingDirectoryStore
  var onMenuPresentationChanged: (Bool) -> Void = { _ in }
  @ObservedObject private var theme = ThemeManager.shared
  @Environment(\.colorScheme) private var colorScheme

  private var trayTint: Color {
    let isDark = (theme.surfaceColorScheme ?? colorScheme) == .dark
    return .black.opacity(theme.mode == .liquidGlass ? 0.08 : isDark ? 0.38 : 0.035)
  }

  var body: some View {
    HStack {
      ComposerProjectSelector(store: store, onMenuPresentationChanged: onMenuPresentationChanged)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 6)
    .frame(height: 32)
    .background { trayShape.fill(trayTint).allowsHitTesting(false) }
    .themedSurface(in: trayShape)
    .clipShape(trayShape)
    .padding(.horizontal, 14)
    .padding(.bottom, 5)
  }

  private var trayShape: UnevenRoundedRectangle {
    UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0,
      bottomLeading: theme.borderRadius, bottomTrailing: theme.borderRadius, topTrailing: 0),
      style: .continuous)
  }
}
