import AppKit
import SwiftUI

struct OnboardingView: View {
  private enum Page {
    case welcome, licenseKey, keyboard, router, browserExtension, messagesRemote, permissions
  }

  @ObservedObject private var theme = ThemeManager.shared
  @Environment(\.colorScheme) private var colorScheme
  @State private var page: Page = .welcome
  @ObservedObject private var license = LicenseManager.shared

  var licenseOnly = false

  var onComplete: () -> Void

  var body: some View {
    Group {
      switch page {
      case .welcome:
        OnboardingWelcomeView(
          onStartTrial: {
            if license.hasAccess { accessGranted() }
            else if license.canStartTrial { license.startTrial() }
            else { license.openCheckout() }
          },
          onUnlockWithKey: { page = .licenseKey }
        )
      case .licenseKey:
        LicenseActivationView(onBack: { page = .welcome })
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
      case .messagesRemote:
        OnboardingStepScreen(
          step: .messagesRemote,
          title: "Use your agents from Messages",
          subtitle: "Optional remote controls through a separate iMessage identity on this Mac.",
          footnote: "Everything you need is included. Connect Messages and pair your phone in Settings → Messages Remote.",
          onBack: goBack,
          onContinue: advance
        ) {
          MessagesRemoteOnboardingView()
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
    .onAppear {
      if license.hasAccess { accessGranted() }
    }
    .onChange(of: license.hasAccess) { _, granted in
      if granted { accessGranted() }
      else { page = .welcome }
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

  private func accessGranted() {
    if licenseOnly { onComplete() }
    else { page = .keyboard }
  }

  private func advance() {
    guard license.requireAccess() else { page = .welcome; return }
    withAnimation(.easeInOut(duration: 0.2)) {
      switch page {
      case .welcome, .licenseKey: page = .keyboard
      case .keyboard: page = .router
      case .router: page = .browserExtension
      case .browserExtension: page = .messagesRemote
      case .messagesRemote: page = .permissions
      case .permissions: onComplete()
      }
    }
  }

  private func goBack() {
    withAnimation(.easeInOut(duration: 0.2)) {
      switch page {
      case .welcome: break
      case .licenseKey: page = .welcome
      case .keyboard: page = .welcome
      case .router: page = .keyboard
      case .browserExtension: page = .router
      case .messagesRemote: page = .browserExtension
      case .permissions: page = .messagesRemote
      }
    }
  }
}
