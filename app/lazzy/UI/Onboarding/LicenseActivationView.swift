import SwiftUI

struct LicenseActivationView: View {
  let onBack: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject private var license = LicenseManager.shared

  var body: some View {
    VStack(spacing: 24) {
      OnboardingBrand()
      VStack(spacing: 9) {
        Text("Unlock Detach")
          .font(OnboardingWelcomeFonts.inter(size: 27))
          .accessibilityAddTraits(.isHeader)
        Text("Enter the license key from your Polar purchase.")
          .font(OnboardingWelcomeFonts.inter(size: 14))
          .foregroundStyle(.secondary)
      }
      LicenseKeyEntryForm()
        .font(OnboardingWelcomeFonts.inter(size: 14))
        .buttonStyle(OnboardingActionButtonStyle(isPrimary: true))
        .frame(maxWidth: 380)
      HStack(spacing: 20) {
        Button("Back", action: onBack)
        Button("Buy Detach") { license.openCheckout() }
        Button("Find my key") { license.openPortal() }
      }
      .buttonStyle(.plain)
      .font(OnboardingWelcomeFonts.inter(size: 12))
      .foregroundStyle(.secondary)
      .disabled(license.isWorking)
      if license.hasSavedLicense {
        LicenseDeactivateButton()
          .buttonStyle(.plain)
          .font(OnboardingWelcomeFonts.inter(size: 12))
          .foregroundStyle(.secondary)
      }
    }
    .multilineTextAlignment(.center)
    .foregroundStyle(.primary)
    .padding(44)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(OnboardingPalette.background(for: colorScheme))
  }
}
