import SwiftUI

/// A custom ViewModifier to apply a shimmer effect.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = 0

    let duration: Double = 0.85   // Speed of the shimmer
    let gradient: Gradient = Gradient(colors: [
        Color.gray.opacity(0.5),  // Darker part of the shimmer
        Color.white.opacity(0.8), // Bright, reflective part
        Color.gray.opacity(0.5)   // Darker part
    ])

    func body(content: Content) -> some View {
        content
            .overlay(
                // The moving gradient layer
                LinearGradient(gradient: gradient,
                               startPoint: .leading,
                               endPoint: .trailing)
                    // The gradient is shifted based on the 'phase' state
                    .offset(x: phase * 200) // 200 is an arbitrary width multiplier
                    // The text itself is used as the mask
                    .mask(content)
            )
            .onAppear {
                withAnimation(
                    .linear(duration: duration)
                    .repeatForever(autoreverses: false)
                ) {
                    // Start the phase off-screen and let it move across
                    phase = 1.5
                }
            }
            // Reset phase when disappearing (optional, but good practice)
            .onDisappear {
                phase = 0
            }
    }
}

extension View {
    /// Applies a shimmer loading effect to the view.
    func shimmer() -> some View {
        modifier(Shimmer())
    }
}
