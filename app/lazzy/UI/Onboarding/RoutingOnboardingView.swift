import SwiftUI

struct RoutingOnboardingView: View {
  @ObservedObject private var router = AutoRouter.shared
  @State private var newRule: RouterRule?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      RouterKeyEditor(router: router)
      Text("Auto sends new request text and routing preferences to TypeSafe when enabled. You can review this in Settings.")
        .font(OnboardingWelcomeFonts.inter(size: 11)).foregroundStyle(.secondary)
      RouterPreferencesForm(router: router, compact: true)
      HStack {
        AppLabeledToggle(title: "Consider my remaining allowance", isOn: $router.configuration.considerUsage)
        Spacer()
        Button("Add a preference") { newRule = RouterRule() }
          .disabled(router.configuration.activeRules.count >= RouterConfiguration.maxRules)
      }
        .font(OnboardingWelcomeFonts.inter(size: 12))
    }
    .padding(20)
    .frame(maxWidth: 540)
    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    }
    .tint(.primary)
    .sheet(item: $newRule) { rule in
      RouterRuleEditor(rule: rule, capabilities: router.capabilities) { saved in
        router.configuration.setRules(router.configuration.activeRules + [saved])
        newRule = nil
      } onCancel: { newRule = nil }
    }
  }
}
