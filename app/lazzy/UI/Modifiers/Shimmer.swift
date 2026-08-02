import SwiftUI

/// A custom ViewModifier to apply a shimmer effect.
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: CGFloat = -0.7

    let duration: Double = 1.15

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .overlay {
                    LinearGradient(
                        colors: [
                            .clear,
                            shimmerHighlight.opacity(0.18),
                            shimmerHighlight.opacity(0.72),
                            shimmerHighlight.opacity(0.18),
                            .clear,
                        ],
                        startPoint: UnitPoint(x: phase, y: 0.5),
                        endPoint: UnitPoint(x: phase + 0.42, y: 0.5)
                    )
                    .mask(content)
                    .allowsHitTesting(false)
                }
                .onAppear {
                    phase = -0.7
                    withAnimation(
                        .linear(duration: duration)
                        .repeatForever(autoreverses: false)
                    ) {
                        phase = 1.35
                    }
                }
                .onDisappear {
                    phase = -0.7
                }
        }
    }

    private var shimmerHighlight: Color {
        colorScheme == .dark ? .white : .black
    }
}

extension View {
    /// Applies a shimmer loading effect to the view.
    func shimmer() -> some View {
        modifier(Shimmer())
    }
}
