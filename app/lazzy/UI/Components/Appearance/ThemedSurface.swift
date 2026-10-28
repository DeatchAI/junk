import SwiftUI

/// One material policy for floating surfaces, without changing their layout or controls.
private struct ThemedSurface<SurfaceShape: Shape>: ViewModifier {
  let shape: SurfaceShape
  let solidColor: Color?
  let fixedColorScheme: ColorScheme?
  @ObservedObject private var theme = ThemeManager.shared
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  private var opaqueColor: Color { solidColor ?? theme.solidBackground }
  private var resolvedScheme: ColorScheme {
    fixedColorScheme ?? theme.surfaceColorScheme ?? colorScheme
  }

  func body(content: Content) -> some View {
    // Keep one foreground hierarchy so changing style preserves editor state and focus.
    LiquidGlassSurface(
      shape: shape,
      isEnabled: theme.mode == .liquidGlass,
      readabilityTint: (resolvedScheme == .dark ? Color.black : .white)
        .opacity(theme.glassBackgroundOpacity),
      opaqueColor: opaqueColor
    ) {
      content.background { legacyBackground }
    }
    .environment(\.colorScheme, resolvedScheme)
  }

  @ViewBuilder private var legacyBackground: some View {
    if theme.mode != .liquidGlass {
      if theme.mode == .solid || reduceTransparency || contrast == .increased {
        shape.fill(opaqueColor)
      } else {
        shape.fill(.ultraThinMaterial)
          .overlay { shape.fill(opaqueColor.opacity(0.3)) }
      }
    }
  }
}

extension View {
  func themedSurface<S: Shape>(
    in shape: S,
    solidColor: Color? = nil,
    colorScheme: ColorScheme? = nil
  ) -> some View {
    modifier(ThemedSurface(shape: shape, solidColor: solidColor,
                          fixedColorScheme: colorScheme))
  }
}
