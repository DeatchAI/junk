import SwiftUI

enum OnboardingStep: Int {
  case keyboard = 1
  case router
  case browserExtension
  case permissions
}

enum OnboardingPalette {
  static func background(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? .black : .white
  }
}

struct OnboardingBrand: View {
  var body: some View {
    HStack(spacing: 7) {
      Image("DetachMarkLight")
        .resizable()
        .renderingMode(.template)
        .scaledToFit()
        .frame(width: 27, height: 24.5)
        .accessibilityHidden(true)

      Text("Detach")
        .font(OnboardingWelcomeFonts.display(size: 27))
        .tracking(-1.25)
    }
    .accessibilityElement(children: .combine)
  }
}

struct OnboardingActionButtonStyle: ButtonStyle {
  let isPrimary: Bool
  @Environment(\.colorScheme) private var colorScheme

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(OnboardingWelcomeFonts.inter(size: 14))
      .foregroundStyle(foregroundColor)
      .padding(.horizontal, 22)
      .frame(height: 42)
      .background(background, in: Capsule())
      .overlay {
        if !isPrimary {
          Capsule().stroke(Color.primary.opacity(0.18), lineWidth: 1)
        }
      }
      .opacity(configuration.isPressed ? 0.7 : 1)
  }

  private var foregroundColor: Color {
    if !isPrimary { return .primary }
    return colorScheme == .dark ? .black : .white
  }

  private var background: Color {
    guard isPrimary else { return .clear }
    return colorScheme == .dark ? .white : .black
  }
}

struct OnboardingStepScreen<Content: View>: View {
  let step: OnboardingStep
  let title: String
  let subtitle: String
  var footnote: String?
  var continueTitle = "Continue"
  let onBack: () -> Void
  let onContinue: () -> Void
  @ViewBuilder let content: () -> Content

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(spacing: 0) {
      OnboardingBrand()
        .padding(.bottom, 24)

      // progress
      //   .padding(.bottom, 23)

      Text(title)
        .font(OnboardingWelcomeFonts.inter(size: 27))
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)

      Text(subtitle)
        .font(OnboardingWelcomeFonts.inter(size: 14))
        .foregroundStyle(.secondary)
        .lineSpacing(3)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 520)
        .padding(.top, 9)

      content()
        .frame(maxWidth: 580)
        .padding(.top, 26)

      if let footnote {
        Text(footnote)
          .font(OnboardingWelcomeFonts.inter(size: 12))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.top, 14)
      }

      HStack(spacing: 12) {
        Button("Back", action: onBack)
          .buttonStyle(OnboardingActionButtonStyle(isPrimary: false))
        Button(continueTitle, action: onContinue)
          .buttonStyle(OnboardingActionButtonStyle(isPrimary: true))
          .keyboardShortcut(.defaultAction)
      }
      .padding(.top, 28)
    }
    .foregroundStyle(.primary)
    .padding(.horizontal, 44)
    .padding(.vertical, 32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(OnboardingPalette.background(for: colorScheme))
  }

  // private var progress: some View {
  //   HStack(spacing: 9) {
  //     Text("\(step.rawValue) of 4")
  //       .font(OnboardingWelcomeFonts.inter(size: 12))
  //       .foregroundStyle(.secondary)
  //     HStack(spacing: 5) {
  //       ForEach(1...4, id: \.self) { position in
  //         Capsule()
  //           .fill(position == step.rawValue ? Color.primary : Color.primary.opacity(0.16))
  //           .frame(width: position == step.rawValue ? 17 : 5, height: 5)
  //       }
  //     }
  //     .accessibilityHidden(true)
  //   }
  //   .accessibilityElement(children: .combine)
  // }
}
