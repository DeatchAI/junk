import AppKit
import SwiftUI

struct MessagesPollSettings: View {
  @ObservedObject var remote: MessagesRemoteController
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    SettingsSection(title: "Interactive polls") {
      SettingsRow(title: "Use native polls",
        subtitle: "Approve actions and answer choices by voting. Messages opens briefly to send each poll.") {
        Toggle("Use native polls", isOn: Binding(get: { remote.pollsEnabled }, set: remote.setPollsEnabled))
          .labelsHidden().toggleStyle(.switch).tint(theme.textColor)
      }
      if remote.pollsEnabled {
        SettingsCardDivider()
        SettingsRow(title: !remote.hasPollAccess ? "Allow Accessibility" : (remote.pollsPaused ? "Polls paused" : "Polls are ready"),
          subtitle: remote.hasPollAccess
            ? (remote.pollsPaused ? "Check the status below before resuming." : "Choose one option. After a short pause, your decision is final.")
            : "Allow Detach to fill and send the native Messages poll.") {
          HStack(spacing: 6) {
            if !remote.hasPollAccess {
              Button("Allow access") {
                NativePermissionRequests.requestAccessibility()
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
              }
                .buttonStyle(AppButtonStyle())
            }
            Button("Send test poll") { remote.sendTestPoll() }
              .buttonStyle(AppButtonStyle())
              .disabled(!remote.hasPollAccess || remote.state != .ready || remote.isSendingPoll || remote.isSendingTestPoll)
          }
        }
        #if DEBUG
        SettingsCardDivider()
        SettingsRow(title: "Consecutive poll test", subtitle: "Send a harmless clarification and approval poll.") {
          Button("Send two test polls") { remote.sendConsecutiveTestPolls() }
            .buttonStyle(AppButtonStyle())
            .disabled(!remote.hasPollAccess || remote.state != .ready || remote.isSendingPoll || remote.isSendingTestPoll)
        }
        #endif
        if let status = remote.pollStatus {
          SettingsCardDivider()
          HStack(alignment: .top, spacing: 10) {
            Text(status).font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
              .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            if remote.pollsPaused && !remote.isSendingPoll {
              Button("Resume polls") { remote.resumePolls() }.buttonStyle(AppButtonStyle(kind: .quiet))
            }
          }.padding(14)
        }
      }
    }
  }
}
