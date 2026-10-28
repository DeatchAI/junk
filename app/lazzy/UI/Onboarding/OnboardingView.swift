import AppKit
import SwiftUI

struct OnboardingView: View {
  private enum Page {
    case welcome, keyboard, router, browserExtension, permissions
  }

  @ObservedObject private var theme = ThemeManager.shared
  @Environment(\.colorScheme) private var colorScheme
  @State private var page: Page = .welcome

  var onComplete: () -> Void

  var body: some View {
    Group {
      switch page {
      case .welcome:
        OnboardingWelcomeView(
          onStartTrial: advance,
          onUnlockWithKey: advance
        )
      case .keyboard:
        OnboardingStepScreen(
          step: .keyboard,
          title: "Keyboard shortcuts",
          subtitle: "Set the keys you want to use across Detach.",
          footnote: "You can change these in the settings any time.",
          onBack: goBack,
          onContinue: advance
        ) {
          OnboardingShortcutSetupView()
        }
      case .router:
        OnboardingStepScreen(
          step: .router,
          title: "Auto router",
          subtitle: "Choose how Detach should route new conversations.",
          footnote: "These choices are saved on this Mac. You can enable Auto and add preferences in Settings when you're ready.",
          onBack: goBack,
          onContinue: advance
        ) {
          RoutingOnboardingView()
        }
      case .browserExtension:
        OnboardingStepScreen(
          step: .browserExtension,
          title: "Connect Chrome",
          subtitle: "Load the included extension manually while the Chrome Web Store listing is unavailable.",
          footnote: "After setup, pin Detach Browser Agent and open its popup once to connect.",
          onBack: goBack,
          onContinue: advance
        ) {
          BrowserExtensionOnboardingView()
        }
      case .permissions:
        OnboardingStepScreen(
          step: .permissions,
          title: "Choose permissions",
          subtitle: "Allow the features you want Detach to use on your Mac.",
          footnote: "Chat works without these. You can grant access later in Settings.",
          continueTitle: "Finish setup",
          onBack: goBack,
          onContinue: onComplete
        ) {
          OnboardingPermissionsView()
        }
      }
    }
    .preferredColorScheme(theme.surfaceColorScheme)
    .frame(minWidth: 700, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity)
    .background(OnboardingPalette.background(for: resolvedColorScheme))
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      AppCoordinator.shared?.permissionsManager.checkPermissions()
    }
  }

  private var resolvedColorScheme: ColorScheme {
    theme.surfaceColorScheme ?? colorScheme
  }

  private func advance() {
    withAnimation(.easeInOut(duration: 0.2)) {
      switch page {
      case .welcome: page = .keyboard
      case .keyboard: page = .router
      case .router: page = .browserExtension
      case .browserExtension: page = .permissions
      case .permissions: onComplete()
      }
    }
  }

  private func goBack() {
    withAnimation(.easeInOut(duration: 0.2)) {
      switch page {
      case .welcome: break
      case .keyboard: page = .welcome
      case .router: page = .keyboard
      case .browserExtension: page = .router
      case .permissions: page = .browserExtension
      }
    }
  }
}
