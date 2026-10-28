import SwiftUI

struct OnboardingWelcomeView: View {
  let onStartTrial: () -> Void
  let onUnlockWithKey: () -> Void

  @Environment(\.colorScheme) private var colorScheme

  init(onStartTrial: @escaping () -> Void, onUnlockWithKey: @escaping () -> Void) {
    OnboardingWelcomeFonts.register()
    self.onStartTrial = onStartTrial
    self.onUnlockWithKey = onUnlockWithKey
  }

  var body: some View {
    VStack(spacing: 0) {
      OnboardingBrand()
        .padding(.bottom, 40)

      Text("All your coding agents.\nOne detached interface.")
        .font(OnboardingWelcomeFonts.inter(size: 24))
        .lineSpacing(2)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
        .padding(.bottom, 36)

      HStack(spacing: 12) {
        Button("Start 3 day trial", action: onStartTrial)
          .buttonStyle(OnboardingActionButtonStyle(isPrimary: true))
          .keyboardShortcut(.defaultAction)
        Button("Unlock with key", action: onUnlockWithKey)
          .buttonStyle(OnboardingActionButtonStyle(isPrimary: false))
      }
    }
    .foregroundStyle(.primary)
    .padding(.horizontal, 32)
    .offset(y: 10)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(OnboardingPalette.background(for: colorScheme))
  }
}
