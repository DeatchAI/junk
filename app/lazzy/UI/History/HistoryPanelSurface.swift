import SwiftUI

/// Same appearance settings as the composer; the existing panel silhouette is retained.
struct HistoryPanelSurface: ViewModifier {
  let placement: ActivityIslandPlacement

  func body(content: Content) -> some View {
    content.themedSurface(in: ScreenEdgeNotchShape(placement: placement))
  }

  static func colorScheme(for theme: ThemeManager) -> ColorScheme? {
    theme.surfaceColorScheme
  }
}
