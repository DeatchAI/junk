import AppKit
import SwiftUI

/// The foreground stays inside the native material and retains its full opacity.
struct LiquidGlassSurface<SurfaceShape: Shape, Content: View>: View {
  let shape: SurfaceShape
  let isEnabled: Bool
  let readabilityTint: Color
  let opaqueColor: Color
  @ViewBuilder let content: Content

  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    materialContent
      .clipShape(shape)
      .contentShape(shape)
  }

  @ViewBuilder private var materialContent: some View {
    if #available(macOS 26.0, *) {
      content
        .background { tintLayer }
        .glassEffect(resolvedGlass, in: shape)
    } else {
      content.background {
        if isEnabled && !reduceTransparency {
          LegacyGlassBackdrop()
            .overlay { shape.fill(readabilityTint) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else {
          tintLayer
        }
      }
    }
  }

  @ViewBuilder private var tintLayer: some View {
    if isEnabled {
      shape.fill(reduceTransparency ? opaqueColor : readabilityTint)
    }
  }

  @available(macOS 26.0, *) private var resolvedGlass: Glass {
    guard isEnabled && !reduceTransparency else { return .identity }
    return contrast == .increased ? .regular : .clear
  }
}

private struct LegacyGlassBackdrop: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .hudWindow
    view.blendingMode = .behindWindow
    view.state = .active
    return view
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
