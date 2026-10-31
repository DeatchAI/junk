import SwiftUI

struct OnboardingWelcomeView: View {
  let onStartTrial: () -> Void
  let onUnlockWithKey: () -> Void

  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject private var license = LicenseManager.shared

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
        Button(license.hasAccess ? "Continue setup" : license.canStartTrial ? "Start 3 day trial" : "Buy Detach", action: onStartTrial)
          .buttonStyle(OnboardingActionButtonStyle(isPrimary: true))
          .keyboardShortcut(.defaultAction)
        Button("Unlock with key", action: onUnlockWithKey)
          .buttonStyle(OnboardingActionButtonStyle(isPrimary: false))
      }
      .disabled(license.isWorking || license.status == .checking)

      if license.isWorking || license.status == .checking {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("Checking your license…")
        }
        .font(OnboardingWelcomeFonts.inter(size: 12))
        .padding(.top, 18)
      } else if let message = license.message {
        Text(message)
          .font(OnboardingWelcomeFonts.inter(size: 12))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 420)
          .padding(.top, 18)
      } else {
        Text(license.hasAccess || license.hasExpiredTrial ? license.statusDescription : "No card required. Full access for 3 days.")
          .font(OnboardingWelcomeFonts.inter(size: 12))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 420)
          .padding(.top, 18)
      }
      if license.hasSavedLicense, !license.isWorking {
        Button("Retry license check") { Task { await license.refresh(force: true) } }
          .buttonStyle(.plain)
          .font(OnboardingWelcomeFonts.inter(size: 12))
          .foregroundStyle(.secondary)
          .padding(.top, 12)
      }
    }
    .foregroundStyle(.primary)
    .padding(.horizontal, 32)
    .offset(y: 10)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(OnboardingPalette.background(for: colorScheme))
  }
}
