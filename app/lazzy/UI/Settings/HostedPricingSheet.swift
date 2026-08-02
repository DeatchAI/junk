import AppKit
import SwiftUI

/// The small purchase decision shown before a person switches to Hosted AI.
/// Polar Checkout itself stays in the browser; this window never receives a card.
struct HostedPricingSheet: View {
  let onClose: () -> Void

  @StateObject private var auth = AuthManager.shared
  @StateObject private var hostedSubscription = HostedSubscriptionManager.shared
  @ObservedObject private var theme = ThemeManager.shared

  private let fallbackPlans = [
    HostedSubscriptionPlan(id: "pro_lite", displayName: "Pro Lite", monthlyPriceCents: 1_000, monthlyCredits: 1_500),
    HostedSubscriptionPlan(id: "pro", displayName: "Pro", monthlyPriceCents: 2_000, monthlyCredits: 3_000),
    HostedSubscriptionPlan(id: "more_pro", displayName: "More Pro", monthlyPriceCents: 10_000, monthlyCredits: 17_000),
  ]

  private var plans: [HostedSubscriptionPlan] {
    hostedSubscription.plans.isEmpty ? fallbackPlans : hostedSubscription.plans
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Hosted AI")
            .font(.appFont(size: 20, weight: .bold))
            .foregroundColor(theme.textColor)
          Text(headerSubtitle)
            .font(.appFont(size: 11))
            .foregroundColor(theme.secondaryTextColor)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.appFont(size: 10, weight: .bold))
            .foregroundColor(theme.secondaryTextColor)
            .frame(width: 24, height: 24)
            .background(theme.textColor.opacity(0.06))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
      }

      if let subscription = hostedSubscription.subscription {
        activeSubscription(subscription)
      } else if hostedSubscription.hasHostedCredits {
        creditedAccess
      } else {
        VStack(spacing: 8) {
          ForEach(plans) { plan in
            planButton(plan)
          }
        }
      }

      if let error = hostedSubscription.errorMessage {
        Text(error)
          .font(.appFont(size: 10))
          .foregroundColor(.red)
      }

      Text("Monthly credits are added after payment confirmation. Cancel anytime from your account.")
        .font(.appFont(size: 10))
        .foregroundColor(theme.secondaryTextColor.opacity(0.8))
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(20)
    .frame(width: 390)
    .background(theme.backgroundFill)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(theme.textColor.opacity(0.1), lineWidth: 0.5)
    )
    .task {
      await hostedSubscription.refresh()
    }
  }

  private var headerSubtitle: String {
    if !auth.isAuthenticated {
      return "Sign in to choose a monthly credit allocation."
    }
    return "Choose a monthly credit allocation for Detach-hosted models."
  }

  private func planButton(_ plan: HostedSubscriptionPlan) -> some View {
    Button {
      if !auth.isAuthenticated {
        openAccountSettings()
      } else {
        Task { await hostedSubscription.startCheckout(planId: plan.id) }
      }
    } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(plan.displayName)
            .font(.appFont(size: 13, weight: .semibold))
            .foregroundColor(theme.textColor)
          Text("\(plan.monthlyCredits.formatted()) hosted credits / month")
            .font(.appFont(size: 10))
            .foregroundColor(theme.secondaryTextColor)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 2) {
          Text("$\(plan.monthlyPriceCents / 100)/mo")
            .font(.appFont(size: 13, weight: .semibold))
            .foregroundColor(theme.accentColor)
          Text(buttonLabel)
            .font(.appFont(size: 9, weight: .medium))
            .foregroundColor(theme.secondaryTextColor)
        }
      }
      .padding(.horizontal, 13)
      .padding(.vertical, 11)
      .background(theme.textColor.opacity(0.045))
      .overlay(
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .stroke(theme.textColor.opacity(0.1), lineWidth: 0.5)
      )
      .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(hostedSubscription.isLoading)
  }

  private var buttonLabel: String {
    if !auth.isAuthenticated { return "Sign in" }
    return hostedSubscription.isLoading ? "Opening…" : "Choose"
  }

  private func activeSubscription(_ subscription: HostedSubscriptionSummary) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("\(subscription.displayName) is active")
            .font(.appFont(size: 13, weight: .semibold))
            .foregroundColor(theme.textColor)
          if let credits = hostedSubscription.credits {
            Text("\(credits.available) credits available")
              .font(.appFont(size: 10))
              .foregroundColor(theme.secondaryTextColor)
          }
        }
        Spacer()
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(.green)
      }

      Button {
        Task { await hostedSubscription.openCustomerPortal() }
      } label: {
        Text(hostedSubscription.isLoading ? "Opening…" : "Manage subscription")
          .font(.appFont(size: 11, weight: .medium))
          .foregroundColor(theme.accentColor)
      }
      .buttonStyle(.plain)
      .disabled(hostedSubscription.isLoading)
    }
    .padding(14)
    .background(theme.textColor.opacity(0.045))
    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
  }

  private var creditedAccess: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Hosted AI is ready")
          .font(.appFont(size: 13, weight: .semibold))
          .foregroundColor(theme.textColor)
        if let credits = hostedSubscription.credits {
          Text("\(credits.available) credits available")
            .font(.appFont(size: 10))
            .foregroundColor(theme.secondaryTextColor)
        }
      }
      Spacer()
      Image(systemName: "checkmark.circle.fill")
        .foregroundColor(.green)
    }
    .padding(14)
    .background(theme.textColor.opacity(0.045))
    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
  }

  private func openAccountSettings() {
    onClose()
    guard let coordinator = AppCoordinator.shared else { return }
    DispatchQueue.main.async {
      MenuBarContentView.showSettings(
        wsManager: coordinator.wsManager,
        launchIntent: .account
      )
    }
  }
}

/// Pricing is deliberately its own window rather than a SwiftUI sheet. A sheet
/// presented from the transparent floating composer becomes an AppKit child
/// window, which locks the two surfaces together and exposes the composer's
/// otherwise-transparent rectangular bounds while the parent is dimmed.
@MainActor
final class HostedPricingWindowController: NSObject {
  static let shared = HostedPricingWindowController()

  private var windowController: NSWindowController?

  func show() {
    let targetScreen = NSApp.keyWindow?.screen
      ?? screenContainingMouse()
      ?? NSScreen.main
      ?? NSScreen.screens.first

    let controller = windowController ?? makeWindowController()
    windowController = controller

    if let window = controller.window {
      center(window, on: targetScreen)
      NSApp.activate(ignoringOtherApps: true)
      controller.showWindow(nil)
      window.makeKeyAndOrderFront(nil)
    }
  }

  func close() {
    windowController?.window?.orderOut(nil)
  }

  private func makeWindowController() -> NSWindowController {
    let window = HostedPricingWindow(
      contentRect: NSRect(x: 0, y: 0, width: 390, height: 300),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.isMovableByWindowBackground = true
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = true
    window.level = .floating
    window.hidesOnDeactivate = false
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    window.animationBehavior = .utilityWindow
    window.onCancelOperation = { [weak self] in
      self?.close()
    }

    let hostingView = NSHostingView(
      rootView: HostedPricingSheet { [weak self] in
        self?.close()
      }
    )
    hostingView.sizingOptions = [.intrinsicContentSize]
    hostingView.layoutSubtreeIfNeeded()
    let fittingSize = hostingView.fittingSize
    let contentSize = NSSize(
      width: 390,
      height: max(1, ceil(fittingSize.height))
    )
    hostingView.frame = NSRect(origin: .zero, size: contentSize)
    window.contentView = hostingView
    window.setContentSize(contentSize)

    return NSWindowController(window: window)
  }

  private func center(_ window: NSWindow, on screen: NSScreen?) {
    guard let screen else {
      window.center()
      return
    }
    let visibleFrame = screen.visibleFrame
    window.setFrameOrigin(
      NSPoint(
        x: visibleFrame.midX - window.frame.width / 2,
        y: visibleFrame.midY - window.frame.height / 2
      )
    )
  }

  private func screenContainingMouse() -> NSScreen? {
    let location = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
  }
}

private final class HostedPricingWindow: KeyableWindow {
  var onCancelOperation: (() -> Void)?

  override func cancelOperation(_ sender: Any?) {
    if let onCancelOperation {
      onCancelOperation()
    } else {
      super.cancelOperation(sender)
    }
  }
}
