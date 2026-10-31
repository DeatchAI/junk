import AppKit
import SwiftUI

struct CursorProviderSettingsView: View {
  @ObservedObject var wsManager: WebSocketManager
  @ObservedObject private var theme = ThemeManager.shared
  @State private var apiKey = ""
  @State private var hasSavedKey = false
  @State private var isSaving = false
  @State private var isOpeningLogin = false
  @State private var isCheckingSignIn = false
  @State private var loginMonitorTask: Task<Void, Never>?
  @State private var status: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      SettingsSectionHeader(
        title: "Cursor",
        subtitle: "Connect through Cursor CLI. Browser sign-in and API keys are supported."
      )

      SettingsCard {
        SettingsRow(
          title: "Account",
          subtitle: "Open Cursor's browser sign-in flow from the CLI."
        ) {
          HStack(spacing: 8) {
            Button(loginButtonTitle) { openLogin() }
              .disabled(isOpeningLogin || isCheckingSignIn)
            Button("Check sign-in") { checkSignIn() }
              .disabled(isOpeningLogin || isCheckingSignIn)
          }
          .font(.appFont(size: 11))
        }

        SettingsCardDivider()

        SettingsRow(
          title: "Cursor API key",
          subtitle: "Optional. Overrides browser sign-in and is stored in macOS Keychain.",
          controlWidth: 215
        ) {
          VStack(alignment: .trailing, spacing: 6) {
            AppTextField("Paste API key", text: $apiKey, secure: true)
              .accessibilityLabel("Cursor API key")
            HStack(spacing: 8) {
              Button(isSaving ? "Saving…" : "Save key") { saveKey() }
                .disabled(isSaving || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
              if hasSavedKey {
                Button("Remove") { removeKey() }
                  .disabled(isSaving)
              }
            }
            .font(.appFont(size: 10.5))
          }
        }

        SettingsCardDivider()

        VStack(alignment: .leading, spacing: 5) {
          Text(hasSavedKey
            ? "An API key is saved. It takes precedence over Cursor CLI browser sign-in."
            : "No API key is saved. Cursor CLI will use its browser sign-in.")
            .font(.appFont(size: 10.5))
            .foregroundStyle(theme.secondaryTextColor)
          Text("Use cursor-agent login. The shorter agent command can resolve to Grok CLI on Macs with both installed.")
            .font(.appFont(size: 10.5))
            .foregroundStyle(theme.secondaryTextColor)
            .fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 14) {
            Button("Copy cursor-agent login") { copyLoginCommand() }
            Link("Cursor CLI guide", destination: URL(string: "https://cursor.com/docs/cli/installation")!)
          }
          .font(.appFont(size: 10.5))
          .buttonStyle(.plain)
          .foregroundStyle(theme.textColor)
          if let status {
            Text(status)
              .font(.appFont(size: 10.5))
              .foregroundStyle(theme.secondaryTextColor)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
      }
    }
    .onAppear(perform: refreshSavedKeyState)
    .task { await updateCursorStatus(includeAPIKey: true, refreshCapabilities: true) }
    .onDisappear {
      loginMonitorTask?.cancel()
      loginMonitorTask = nil
      apiKey = ""
    }
  }

  private var loginButtonTitle: String {
    if isOpeningLogin { return "Opening…" }
    if isCheckingSignIn { return "Checking…" }
    return "Sign in with Cursor"
  }

  private func refreshSavedKeyState() {
    hasSavedKey = (try? CursorProviderKeychain.read()) != nil
  }

  private func saveKey() {
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return }
    isSaving = true
    do {
      try CursorProviderKeychain.save(key)
      apiKey = ""
      hasSavedKey = true
      status = "Saved in Keychain. Syncing with the local runtime…"
      Task {
        do {
          try await CursorProviderClient.setAPIKey(key)
          status = "API key saved and connected to the local runtime."
        } catch {
          status = "Saved in Keychain. It will sync when Detach reconnects."
        }
        isSaving = false
        wsManager.requestCapabilities(force: true)
      }
    } catch {
      status = error.localizedDescription
      isSaving = false
    }
  }

  private func removeKey() {
    isSaving = true
    do {
      try CursorProviderKeychain.remove()
      hasSavedKey = false
      status = "API key removed. Cursor CLI browser sign-in will be used."
      Task {
        try? await CursorProviderClient.setAPIKey(nil)
        isSaving = false
        wsManager.requestCapabilities(force: true)
      }
    } catch {
      status = error.localizedDescription
      isSaving = false
    }
  }

  private func openLogin() {
    isOpeningLogin = true
    loginMonitorTask?.cancel()
    loginMonitorTask = Task {
      do {
        try await CursorProviderClient.startLogin()
        isOpeningLogin = false
        status = "Finish sign-in in the browser. Detach will detect it and refresh Cursor models."
        await waitForCursorSignIn()
      } catch {
        status = error.localizedDescription
        isOpeningLogin = false
      }
    }
  }

  private func checkSignIn() {
    Task { await updateCursorStatus(includeAPIKey: true, refreshCapabilities: true) }
  }

  private func updateCursorStatus(includeAPIKey: Bool, refreshCapabilities: Bool) async {
    guard let executable = LocalAgentDetector.executable(for: .cursor) else {
      status = "Cursor CLI is not installed. Install it, then run cursor-agent login."
      return
    }

    isCheckingSignIn = true
    defer { isCheckingSignIn = false }
    let readiness = await AgentStatusProbe.check(
      .cursor,
      executable: executable,
      includeCursorAPIKey: includeAPIKey
    )
    switch readiness.state {
    case .ready:
      status = "Cursor sign-in confirmed. Refreshing models…"
      if refreshCapabilities { wsManager.requestCapabilities(force: true) }
    case .signInNeeded:
      status = "Cursor CLI is signed out. Finish browser sign-in, then check again."
    case .missing:
      status = "Cursor CLI is not installed. Install it, then run cursor-agent login."
    case .checking:
      status = "Checking Cursor sign-in…"
    case .installed:
      status = "Could not confirm Cursor sign-in yet. Try checking again after the browser flow finishes."
    }
  }

  private func waitForCursorSignIn() async {
    guard let executable = LocalAgentDetector.executable(for: .cursor) else {
      status = "Cursor CLI is not installed. Install it, then run cursor-agent login."
      return
    }

    isCheckingSignIn = true
    defer { isCheckingSignIn = false }
    let deadline = Date().addingTimeInterval(120)
    while Date() < deadline && !Task.isCancelled {
      let readiness = await AgentStatusProbe.check(
        .cursor,
        executable: executable,
        includeCursorAPIKey: false
      )
      if readiness.state == .ready {
        status = "Cursor sign-in confirmed. Refreshing models…"
        wsManager.requestCapabilities(force: true)
        return
      }
      status = "Waiting for Cursor browser sign-in to finish…"
      do { try await Task.sleep(nanoseconds: 2_000_000_000) }
      catch { return }
    }
    if !Task.isCancelled {
      status = "Still waiting for sign-in. Finish it in the browser, then select Check sign-in."
    }
  }

  private func copyLoginCommand() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("cursor-agent login", forType: .string)
    status = "Copied cursor-agent login."
  }
}
