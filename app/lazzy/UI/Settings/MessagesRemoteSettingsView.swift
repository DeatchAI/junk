import AppKit
import SwiftUI

struct MessagesRemoteSettingsView: View {
  @ObservedObject private var remote: MessagesRemoteController
  @ObservedObject private var theme = ThemeManager.shared
  @State private var agentAddress: String
  @State private var showSetup = false
  private let accessChecksEnabled: Bool

  init(remote: MessagesRemoteController? = nil, accessChecksEnabled: Bool = true) {
    let remote = remote ?? .shared
    self.accessChecksEnabled = accessChecksEnabled
    _remote = ObservedObject(wrappedValue: remote)
    _agentAddress = State(initialValue: remote.agentAddress)
  }

  var body: some View {
    SettingsPage(title: "Messages Remote",
      subtitle: "Finished tasks and decisions that need you, on your iPhone.") {
      if case .error(let message) = remote.state {
        Text(message).font(.appFont(size: 11)).foregroundStyle(theme.textColor)
          .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 14)
      }
      if remote.isPaired {
        pairedConnection
        MessagesPollSettings(remote: remote)
      } else {
        pairingCard
      }
      AppDisclosure("Setup and permissions", isExpanded: $showSetup) {
        connectionSection
      }
      Text(remote.pollsEnabled
        ? "All projects are included. Sending polls needs this Mac awake and unlocked, with Detach open."
        : "All projects are included. Keep this Mac awake with Detach open.")
        .font(.appFont(size: 10.5)).foregroundStyle(theme.secondaryTextColor).padding(.horizontal, 14)
    }
    .onAppear {
      guard accessChecksEnabled else { return }
      remote.refreshPollAccess()
      if remote.isEnabled { remote.resumeIfPaired() }
      remote.checkMessagesAccess(offerPairing: true)
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      if accessChecksEnabled { remote.checkMessagesAccess(); remote.refreshPollAccess() }
    }
    .onChange(of: remote.agentAddress) { _, address in agentAddress = address }
    .onChange(of: remote.state) { _, state in
      if state == .needsPermission { showSetup = true }
    }
  }

  private var pairingCard: some View {
    SettingsCard {
      if let session = remote.pairing {
        MessagesPairingQRCode(session: session,
          onCancel: { remote.stop() }, onChangeAddress: { remote.stop() })
          .padding(.vertical, 26).padding(.horizontal, 20)
      } else if remote.isDiscoveringAddress || remote.state == .connecting || remote.isCheckingMessagesAccess {
        VStack(spacing: 12) {
          AppSpinner()
          Text(remote.isDiscoveringAddress ? "Finding your Messages address…" : "Preparing Messages…")
            .font(.appFont(size: 12)).foregroundStyle(theme.secondaryTextColor)
        }.frame(maxWidth: .infinity).padding(.vertical, 72)
      } else if !remote.hasMessagesAccess {
        VStack(spacing: 12) {
          Image(systemName: "message").font(.system(size: 30, weight: .light))
          Text("Connect your iPhone").font(.appFont(size: 16, weight: .semibold))
          Text("Allow Messages access to show your pairing QR code.")
            .font(.appFont(size: 12)).foregroundStyle(theme.secondaryTextColor)
          Button("Allow Messages access") { openPrivacy("Privacy_AllFiles"); showSetup = true }
            .buttonStyle(AppButtonStyle(kind: .primary))
        }.frame(maxWidth: .infinity).padding(.vertical, 45)
      } else {
        addressEntry
      }
      if let hint = remote.pairingHint, remote.state != .pairing {
        Text(hint).font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
          .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.bottom, 16)
      } else if let hint = remote.pairingHint,
        hint != "Scan with your iPhone Camera, open Messages, then tap Send." {
        Text(hint).font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
          .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.bottom, 16)
      }
    }
  }

  private var addressEntry: some View {
    VStack(spacing: 14) {
      Text("Connect your iPhone").font(.appFont(size: 16, weight: .semibold))
      Text("Enter the agent’s address from Messages → Settings → iMessage on this Mac.")
        .font(.appFont(size: 12)).foregroundStyle(theme.secondaryTextColor)
        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
      AppTextField("iMessage email or phone number", text: $agentAddress)
        .frame(maxWidth: 300)
      Button("Show QR code") { remote.beginPairing(agentAddress: agentAddress) }
        .buttonStyle(AppButtonStyle(kind: .primary))
        .disabled(agentAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }.frame(maxWidth: .infinity).padding(30)
  }

  private var connectionSection: some View {
    SettingsCard {
      SettingsRow(title: "Messages account",
        subtitle: "Sign Messages on this Mac into a separate Apple Account for your agents. Keep your personal account on your iPhone.") {
        Button("Open Messages", action: openMessages).buttonStyle(AppButtonStyle())
      }
      SettingsCardDivider()
      SettingsRow(title: "Messages access",
        subtitle: remote.hasMessagesAccess
          ? "Messages read access is ready."
          : "Allow Detach in Full Disk Access, then reopen it.") {
        HStack(spacing: 6) {
          Button("Privacy settings") { openPrivacy("Privacy_AllFiles") }
            .buttonStyle(AppButtonStyle())
          Button { remote.checkMessagesAccess(offerPairing: true) } label: {
            Image(systemName: "arrow.clockwise").font(.system(size: 10))
          }
          .buttonStyle(AppButtonStyle(kind: .quiet))
          .disabled(remote.isCheckingMessagesAccess).help("Check Messages access")
          .accessibilityLabel("Check Messages access")
        }
      }
      SettingsCardDivider()
      AppDisclosure("Help with setup") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Detach suggests the address from recent Messages account details when they agree. If the address is missing or you changed accounts, enter the address shown in Messages settings. Your iPhone’s sending address is detected when you pair.")
          Text("If Detach isn’t listed in Full Disk Access, add the app with the + button. Allow Detach → Messages in Automation to send replies. Private questions and Touch ID stay on your Mac.")
          HStack(spacing: 6) {
            Button("Show Detach in Finder") {
              NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            }
            Button("Automation settings") { openPrivacy("Privacy_Automation") }
            Button("Create Apple Account") {
              NSWorkspace.shared.open(URL(string: "https://account.apple.com/")!)
            }
          }.buttonStyle(AppButtonStyle())
        }.fixedSize(horizontal: false, vertical: true)
      }.padding(.horizontal, 14)
    }
  }

  private var pairedConnection: some View {
    SettingsSection(title: "Your iPhone") {
      SettingsRow(title: remote.state.label, subtitle: remote.pairedSender,
        controlWidth: 250) {
        HStack(spacing: 6) {
          if remote.state != .ready {
            Button("Connect") { remote.enablePairedConnection() }
          }
          if remote.isEnabled {
            Button("Turn off") { remote.disable() }
          }
          Button("Unpair") { remote.stop(clearPairing: true) }
        }.buttonStyle(AppButtonStyle())
      }
      SettingsCardDivider()
      VStack(alignment: .leading, spacing: 6) {
        Text("Only when you’re needed").font(.appFont(size: 12, weight: .medium))
        Text("Get a compact result when a task finishes, plus approval requests and clarification questions. Progress updates stay in Detach.")
        Text("Send status any time. Vote in a poll to respond to a decision. Send reply with the task ID for a follow-up.")
      }.font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor).padding(14)
    }
  }

  private func openMessages() {
    let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.MobileSMS")
      ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iChat")
      ?? URL(fileURLWithPath: "/System/Applications/Messages.app")
    NSWorkspace.shared.open(url)
  }

  private func openPrivacy(_ section: String) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)") {
      NSWorkspace.shared.open(url)
    }
  }
}
