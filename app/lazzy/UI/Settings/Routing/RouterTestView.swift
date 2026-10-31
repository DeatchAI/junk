import SwiftUI

struct RouterTestView: View {
  @ObservedObject var router: AutoRouter
  @StateObject private var state = RouterTestState()
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SettingsSectionHeader(title: "Test a request", subtitle: "See how Jev classifies a sample and which choice your settings would use.")
      SettingsCard {
        VStack(alignment: .leading, spacing: 14) {
          ZStack(alignment: .topLeading) {
            TextEditor(text: $state.prompt)
              .font(.appFont(size: 12))
              .scrollContentBackground(.hidden)
              .padding(5)
              .disabled(state.isRunning)
              .accessibilityLabel("Sample request for the auto router")
            if state.prompt.isEmpty {
              Text("For example: Build a compact settings panel for my Mac app.")
                .font(.appFont(size: 12)).foregroundStyle(theme.secondaryTextColor)
                .padding(.horizontal, 10).padding(.vertical, 9).allowsHitTesting(false)
            }
          }
          .frame(height: 94)
          .background(theme.controlBackgroundColor, in: RoundedRectangle(cornerRadius: 8))
          HStack(spacing: 14) {
            Button(state.isRunning ? "Classifying…" : "Test routing") {
              state.run { try await router.test($0, capabilities: router.capabilities) }
            }
            .disabled(state.isRunning || !router.hasKey || !router.capabilities.contains(where: \.installed)
              || state.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if state.isRunning {
              AppSpinner()
              Button("Cancel") { state.cancel() }
            }
            Spacer()
            if state.result != nil || state.error != nil { Button("Clear result") { state.cancel(clearResult: true) } }
          }.font(.appFont(size: 11))
          if !router.hasKey {
            Text("Save a Jev API key above to test classification.").foregroundStyle(theme.secondaryTextColor)
          } else if !router.capabilities.contains(where: \.installed) {
            Text("Connect an agent so the test can use its available models.").foregroundStyle(theme.secondaryTextColor)
          }
          Text("This sends the sample to Jev using your key. Auto can stay off. No agent runs and no conversation is created. Results use your current preferences, override and fallback settings.")
            .font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
          if let error = state.error { Label(error, systemImage: "exclamationmark.circle").font(.appFont(size: 11)) }
          if let result = state.result { RouterTestResultView(result: result) }
        }.padding(16).font(.appFont(size: 12))
      }
    }
    .onChange(of: state.prompt) { _, _ in state.cancel(clearResult: true) }
    .onChange(of: router.configuration) { _, _ in state.cancel(clearResult: true) }
    .onChange(of: router.hasKey) { _, _ in state.cancel(clearResult: true) }
    .onChange(of: router.capabilities) { _, _ in state.cancel(clearResult: true) }
    .onDisappear { state.cancel(clearResult: true); state.prompt = "" }
  }

}
