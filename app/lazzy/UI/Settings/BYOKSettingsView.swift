//
//  BYOKSettingsView.swift
//  lazzy
//
//  BYOK (Bring Your Own Key) settings UI for custom API keys
//

import SwiftUI

struct BYOKSettingsView: View {
  @ObservedObject var wsManager: WebSocketManager
  @ObservedObject private var theme = ThemeManager.shared
  @ObservedObject private var authManager = AuthManager.shared

  @State private var isExpanded = false
  @State private var apiKeys: [AIProvider: String] = [:]
  @State private var showSuccess = false
  @State private var isSaving = false
  @State private var byokEnabled = BYOKSettings.isEnabled

  /// Whether the current user's plan has BYOK access
  private var hasBYOKAccess: Bool {
    authManager.planType.hasBYOKAccess
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header row with toggle and expand/collapse
      HStack(spacing: 16) {
        // Clickable area for expand/collapse
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
          HStack(spacing: 16) {
            ZStack {
              RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
                .fill(byokEnabled ? theme.accentColor.opacity(0.1) : theme.textColor.opacity(0.05))
                .frame(width: 44, height: 44)

              Image(systemName: "key.fill")
                .font(.appFont(size: 18))
                .foregroundColor(byokEnabled ? theme.accentColor : theme.secondaryTextColor)
            }

            VStack(alignment: .leading, spacing: 4) {
              HStack(spacing: 8) {
                Text("Custom API Keys")
                  .font(.appFont(size: 14, weight: .semibold))
                  .foregroundColor(theme.textColor)

                if byokEnabled && configuredCount > 0 {
                  Text("\(configuredCount) configured")
                    .font(.appFont(size: 10, weight: .medium))
                    .foregroundColor(theme.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.accentColor.opacity(0.1))
                    .cornerRadius(theme.borderRadius / 3)
                }
              }

              Text(
                byokEnabled
                  ? "Using your own API keys"
                  : (hasBYOKAccess ? "Using hosted API keys" : "Upgrade to Pro to enable")
              )
              .font(.appFont(size: 12))
              .foregroundColor(hasBYOKAccess ? theme.secondaryTextColor : theme.accentColor)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Spacer()

        // BYOK Toggle
        Toggle("", isOn: $byokEnabled)
          .toggleStyle(SwitchToggleStyle(tint: theme.accentColor))
          .labelsHidden()
          .disabled(!hasBYOKAccess)
          .opacity(hasBYOKAccess ? 1.0 : 0.5)
          .help(hasBYOKAccess ? "" : "Upgrade to Pro to use your own API keys")
          .onChange(of: byokEnabled) { _, newValue in
            BYOKSettings.isEnabled = newValue
            syncBYOKState()
          }

        // Expand/collapse chevron
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.appFont(size: 12, weight: .medium))
            .foregroundColor(theme.secondaryTextColor)
        }
        .buttonStyle(.plain)
      }
      .padding(12)

      // Expanded content
      if isExpanded {
        VStack(alignment: .leading, spacing: 16) {
          Divider().opacity(0.3)

          // Provider list
          ForEach(BYOKSettings.cloudProviders) { provider in
            ProviderKeyRow(
              provider: provider,
              apiKey: binding(for: provider),
              theme: theme
            )
          }

          // Save button
          HStack {
            Spacer()

            if showSuccess {
              HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundColor(.green)
                Text("Saved")
                  .foregroundColor(.green)
              }
              .font(.appFont(size: 12))
            }

            Button(action: saveKeys) {
              HStack(spacing: 4) {
                if isSaving {
                  ProgressView()
                    .scaleEffect(0.6)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
                Text(isSaving ? "Saving..." : "Save Keys")
              }
              .font(.appFont(size: 12, weight: .medium))
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
              .background(theme.accentColor)
              .foregroundColor(.white)
              .cornerRadius(theme.borderRadius / 2)
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
          }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
      }
    }
    .background(
      RoundedRectangle(cornerRadius: theme.borderRadius)
        .stroke(theme.borderColor.opacity(0.3), lineWidth: 0.5)
        .background(theme.textColor.opacity(0.02))
    )
    .cornerRadius(theme.borderRadius)
    .onAppear { loadKeys() }
  }

  // MARK: - Helpers

  private var configuredCount: Int {
    BYOKSettings.cloudProviders.filter { BYOKSettings.isConfigured($0) }.count
  }

  private func binding(for provider: AIProvider) -> Binding<String> {
    Binding(
      get: { apiKeys[provider] ?? "" },
      set: { apiKeys[provider] = $0 }
    )
  }

  private func loadKeys() {
    for provider in AIProvider.allCases {
      apiKeys[provider] = BYOKSettings.apiKey(for: provider)
    }
  }

  private func saveKeys() {
    isSaving = true
    showSuccess = false

    // Save to UserDefaults
    for provider in AIProvider.allCases {
      BYOKSettings.setAPIKey(apiKeys[provider] ?? "", for: provider)
    }

    // Sync to server
    let keys = BYOKSettings.allConfiguredKeys()
    wsManager.updateAPIKeys(keys: keys)

    // Show success feedback
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      isSaving = false
      showSuccess = true

      DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        showSuccess = false
      }
    }
  }

  /// Sync BYOK enabled state to server
  private func syncBYOKState() {
    if byokEnabled {
      // Send custom keys to server
      let keys = BYOKSettings.allConfiguredKeys()
      wsManager.updateAPIKeys(keys: keys, enabled: true)
    } else {
      // Send empty keys to tell server to use hosted keys
      wsManager.updateAPIKeys(keys: [:], enabled: false)
    }
  }
}

// MARK: - Provider Key Row

private struct ProviderKeyRow: View {
  let provider: AIProvider
  @Binding var apiKey: String
  let theme: ThemeManager

  @State private var isSecure = true

  var body: some View {
    HStack(spacing: 12) {
      // Provider name
      Text(provider.displayName)
        .font(.appFont(size: 13, weight: .medium))
        .foregroundColor(theme.textColor)
        .frame(width: 80, alignment: .leading)

      // API key input
      HStack(spacing: 8) {
        if isSecure {
          SecureField("", text: $apiKey)
            .placeholder(when: apiKey.isEmpty) {
              Text(provider.placeholder)
                .foregroundColor(theme.secondaryTextColor)
            }
            .textFieldStyle(.plain)
            .font(.appFont(size: 12, design: .monospaced))
            .foregroundColor(theme.textColor)
        } else {
          TextField("", text: $apiKey)
            .placeholder(when: apiKey.isEmpty) {
              Text(provider.placeholder)
                .foregroundColor(theme.secondaryTextColor)
            }
            .textFieldStyle(.plain)
            .font(.appFont(size: 12, design: .monospaced))
            .foregroundColor(theme.textColor)
        }

        // Toggle visibility
        Button(action: { isSecure.toggle() }) {
          Image(systemName: isSecure ? "eye.slash" : "eye")
            .font(.appFont(size: 12))
            .foregroundColor(theme.secondaryTextColor)
        }
        .buttonStyle(.plain)

        // Status indicator
        if !apiKey.isEmpty {
          Image(systemName: "checkmark.circle.fill")
            .font(.appFont(size: 12))
            .foregroundColor(.green)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(theme.inputBackgroundColor)
      .cornerRadius(theme.borderRadius / 2)
    }
  }
}

// MARK: - Preview

#Preview {
  BYOKSettingsView(wsManager: WebSocketManager())
    .padding()
    .frame(width: 500)
    .background(Color(white: 0.1))
}
