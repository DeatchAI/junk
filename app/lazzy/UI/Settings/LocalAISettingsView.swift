//
//  LocalAISettingsView.swift
//  lazzy
//
//  Settings view for configuring local AI providers (Ollama, LM Studio)
//

import SwiftUI

/// Result of testing a local AI provider connection
enum ConnectionTestResult {
  case idle
  case testing
  case success(models: [String])
  case error(message: String)
}

struct LocalAISettingsView: View {
  @ObservedObject var wsManager: WebSocketManager
  @ObservedObject private var theme = ThemeManager.shared

  @State private var isExpanded = false
  @State private var apiKeys: [AIProvider: String] = [:]
  @State private var modelNames: [AIProvider: String] = [:]
  @State private var showSuccess = false
  @State private var isSaving = false
  @State private var loaded = false
  @State private var testResults: [AIProvider: ConnectionTestResult] = [:]

  // Local providers to display
  private let localProviders = BYOKSettings.localProviders

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header row
      HStack(spacing: 16) {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
          HStack(spacing: 16) {
            ZStack {
              RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
                .fill(theme.textColor.opacity(0.05))
                .frame(width: 44, height: 44)

              Image(systemName: "macmini.fill")
                .font(.appFont(size: 18))
                .foregroundColor(theme.textColor.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 4) {
              Text("Local AI Integration")
                .font(.appFont(size: 14, weight: .semibold))
                .foregroundColor(theme.textColor)

              Text("Run models locally on your Mac")
                .font(.appFont(size: 12))
                .foregroundColor(theme.secondaryTextColor)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Spacer()

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

          Text(
            "Connect to local AI providers running on your machine. These models run privately and offline."
          )
          .font(.appFont(size: 12))
          .foregroundColor(theme.secondaryTextColor)
          .padding(.bottom, 4)

          // Local Provider List
          ForEach(localProviders) { provider in
            LocalProviderRow(
              provider: provider,
              apiKey: binding(for: provider),
              modelName: modelBinding(for: provider),
              testResult: testResults[provider] ?? .idle,
              onTest: { testConnection(for: provider) },
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
                Text(isSaving ? "Saving..." : "Save Settings")
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

  private func binding(for provider: AIProvider) -> Binding<String> {
    Binding(
      get: { apiKeys[provider] ?? "" },
      set: { apiKeys[provider] = $0 }
    )
  }

  private func modelBinding(for provider: AIProvider) -> Binding<String> {
    Binding(
      get: { modelNames[provider] ?? "" },
      set: { modelNames[provider] = $0 }
    )
  }

  private func loadKeys() {
    for provider in localProviders {
      apiKeys[provider] = BYOKSettings.apiKey(for: provider)
      modelNames[provider] = BYOKSettings.model(for: provider)
    }
  }

  /// Test connection to a local AI provider
  private func testConnection(for provider: AIProvider) {
    testResults[provider] = .testing

    let baseURL = apiKeys[provider]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let url: URL?

    switch provider {
    case .ollama:
      // Ollama: GET /api/tags returns list of models
      let base = baseURL.isEmpty ? "http://localhost:11434" : baseURL
      url = URL(string: "\(base.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/api/tags")
    case .lmstudio:
      // LM Studio: GET /v1/models (OpenAI-compatible)
      let base = baseURL.isEmpty ? "http://localhost:1234/v1" : baseURL
      let normalizedBase = base.hasSuffix("/v1") ? base : "\(base)/v1"
      url = URL(string: "\(normalizedBase.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/models")
    default:
      testResults[provider] = .error(message: "Unsupported provider")
      return
    }

    guard let requestURL = url else {
      testResults[provider] = .error(message: "Invalid URL")
      return
    }

    var request = URLRequest(url: requestURL)
    request.timeoutInterval = 5

    URLSession.shared.dataTask(with: request) { data, response, error in
      DispatchQueue.main.async {
        if let error = error {
          let message =
            (error as? URLError)?.code == .timedOut
            ? "Connection timed out"
            : (error as? URLError)?.code == .cannotConnectToHost
              ? "Cannot connect - is \(provider.displayName) running?"
              : error.localizedDescription
          testResults[provider] = .error(message: message)
          return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
          testResults[provider] = .error(message: "Invalid response")
          return
        }

        guard httpResponse.statusCode == 200, let data = data else {
          testResults[provider] = .error(message: "HTTP \(httpResponse.statusCode)")
          return
        }

        // Parse model list based on provider
        let models = parseModels(data: data, provider: provider)
        if models.isEmpty {
          testResults[provider] = .error(message: "Connected but no models found")
        } else {
          testResults[provider] = .success(models: models)
        }
      }
    }.resume()
  }

  /// Parse model list from provider response
  private func parseModels(data: Data, provider: AIProvider) -> [String] {
    switch provider {
    case .ollama:
      // Ollama response: { "models": [{ "name": "llama3", ... }] }
      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let models = json["models"] as? [[String: Any]]
      {
        return models.compactMap { $0["name"] as? String }
      }
    case .lmstudio:
      // LM Studio response: { "data": [{ "id": "model-name", ... }] }
      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let models = json["data"] as? [[String: Any]]
      {
        return models.compactMap { $0["id"] as? String }
      }
    default:
      break
    }
    return []
  }

  private func saveKeys() {
    isSaving = true
    showSuccess = false

    // Save to UserDefaults
    for provider in localProviders {
      BYOKSettings.setAPIKey(apiKeys[provider] ?? "", for: provider)
      BYOKSettings.setModel(modelNames[provider] ?? "", for: provider)
    }

    // Sync to server (update environment variables/context for server)
    // Note: Local AI keys (URLs) are sent similarly to BYOK keys
    // We send ALL configured keys, including cloud and local
    let keys = BYOKSettings.allConfiguredKeys()

    // We must respect the global BYOK enabled state for cloud keys,
    // but usually local keys might be independent?
    // However, the current backend reinitializes functionality based on `updateProviderKeys`.
    // We send current state.
    let byokEnabled = BYOKSettings.isEnabled
    wsManager.updateAPIKeys(keys: keys, enabled: byokEnabled)

    // Also trigger a settings sync to ensure the new model is picked up if selected
    // Note: This matches AISettingsView behavior
    // We might need a delay or callback, but simple sync is good for now
    // Also trigger a settings sync to ensure the new model is picked up if selected
    // Note: This matches AISettingsView behavior
    // We might need a delay or callback, but simple sync is good for now
    // wsManager.refreshSettings() - Implementation pending

    // Instead we can just re-send settings if needed, but updateAPIKeys triggers re-init
    // on server side which is enough.

    // Show success feedback
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      isSaving = false
      showSuccess = true

      DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        showSuccess = false
      }
    }
  }
}

// MARK: - Local Provider Row

private struct LocalProviderRow: View {
  let provider: AIProvider
  @Binding var apiKey: String
  @Binding var modelName: String
  let testResult: ConnectionTestResult
  let onTest: () -> Void
  let theme: ThemeManager

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(provider.displayName)
          .font(.appFont(size: 13, weight: .medium))
          .foregroundColor(theme.textColor)

        Spacer()

        // Test Connection Button
        Button(action: onTest) {
          HStack(spacing: 4) {
            if case .testing = testResult {
              ProgressView()
                .scaleEffect(0.5)
                .progressViewStyle(CircularProgressViewStyle(tint: theme.accentColor))
            } else {
              Image(systemName: "bolt.fill")
                .font(.appFont(size: 10))
            }
            Text("Test")
              .font(.appFont(size: 11, weight: .medium))
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(theme.textColor.opacity(0.08))
          .foregroundColor(theme.accentColor)
          .cornerRadius(theme.borderRadius / 2)
        }
        .buttonStyle(.plain)
        .disabled(testResult.isTesting)
      }

      // Base URL input
      HStack(spacing: 8) {
        TextField("", text: $apiKey)
          .placeholder(when: apiKey.isEmpty) {
            Text(provider.placeholder)
              .foregroundColor(theme.secondaryTextColor)
          }
          .textFieldStyle(.plain)
          .font(.appFont(size: 12, design: .monospaced))
          .foregroundColor(theme.textColor)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(theme.inputBackgroundColor)
      .cornerRadius(theme.borderRadius / 2)

      // Helper hint
      if provider == .ollama && apiKey.isEmpty {
        Text("Default: http://localhost:11434")
          .font(.appFont(size: 10))
          .foregroundColor(theme.secondaryTextColor.opacity(0.8))
      } else if provider == .lmstudio && apiKey.isEmpty {
        Text("Default: http://localhost:1234/v1")
          .font(.appFont(size: 10))
          .foregroundColor(theme.secondaryTextColor.opacity(0.8))
      }

      // Test Result Display
      switch testResult {
      case .idle:
        EmptyView()
      case .testing:
        HStack(spacing: 4) {
          ProgressView()
            .scaleEffect(0.6)
          Text("Testing connection...")
            .font(.appFont(size: 11))
            .foregroundColor(theme.secondaryTextColor)
        }
      case .success(let models):
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(.green)
            Text("Connected! Found \(models.count) model\(models.count == 1 ? "" : "s")")
              .foregroundColor(.green)
          }
          .font(.appFont(size: 11, weight: .medium))

          // Model selector
          if !models.isEmpty {
            HStack(spacing: 8) {
              Text("Model:")
                .font(.appFont(size: 11))
                .foregroundColor(theme.secondaryTextColor)

              Picker("", selection: $modelName) {
                ForEach(models, id: \.self) { model in
                  Text(model)
                    .font(.appFont(size: 11, design: .monospaced))
                    .tag(model)
                }
              }
              .pickerStyle(.menu)
              .labelsHidden()
              .frame(maxWidth: 200)
              .onAppear {
                // Auto-select first model if none selected
                if modelName.isEmpty, let first = models.first {
                  modelName = first
                }
              }
            }
          }
        }
        .padding(8)
        .background(Color.green.opacity(0.1))
        .cornerRadius(theme.borderRadius / 2)

      case .error(let message):
        HStack(spacing: 4) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.red)
          Text(message)
            .foregroundColor(.red)
        }
        .font(.appFont(size: 11))
        .padding(8)
        .background(Color.red.opacity(0.1))
        .cornerRadius(theme.borderRadius / 2)
      }
    }
  }
}

// MARK: - ConnectionTestResult Helpers

extension ConnectionTestResult {
  var isTesting: Bool {
    if case .testing = self { return true }
    return false
  }
}
