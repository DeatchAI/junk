import SwiftUI

struct GitSnapshotSettingsView: View {
  let connected: Bool
  @ObservedObject private var theme = ThemeManager.shared
  @State private var status: GitSnapshotSettings?
  @State private var busy = false
  @State private var error: String?
  @State private var confirmClear = false
  @State private var disableAfterClear = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SettingsSectionHeader(title: "Local code snapshots",
        subtitle: "Detach saves code before and after a task so you can review changes and discard them without losing earlier edits.")
      SettingsCard {
        SettingsToggleRow(title: "Keep task snapshots on this Mac",
          subtitle: "Task comparisons stay for up to 30 days, with a 128 MB limit. Discard recovery stays for up to seven days, up to 10 records and 128 MB.",
          isOn: Binding(get: { status?.enabled ?? true }, set: { enabled in
            if enabled { Task { await request(body: ["enabled": true]) } }
            else { disableAfterClear = true; confirmClear = true }
          })).disabled(status == nil || busy || !connected)
        SettingsCardDivider()
        SettingsRow(title: summary,
          subtitle: "Stored code stays local. Clearing removes saved comparisons and Undo copies; project files and Git staging stay unchanged.") {
          Button("Clear stored snapshots…") { disableAfterClear = false; confirmClear = true }
            .disabled(status == nil || busy || !connected || status?.bytes == 0)
        }
      }
      if let error { Text(error).font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor) }
      if !connected { Text("Reconnect Detach to manage local code snapshots.").font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor) }
    }
    .tint(theme.textColor)
    .confirmationDialog(disableAfterClear ? "Turn off snapshots and clear stored code?" : "Clear task snapshots and discard recovery?", isPresented: $confirmClear) {
      Button(disableAfterClear ? "Turn off and clear" : "Clear stored snapshots") {
        Task { await request(body: disableAfterClear ? ["enabled": false] : ["clear": true]) }
      }
      Button("Cancel", role: .cancel) {}
    } message: { Text("Saved comparisons and Undo copies will be removed from this Mac. Current project files and Git staging will be kept.") }
    .task { if connected { await request() } }
    .onChange(of: connected) { _, value in if value { Task { await request() } } }
  }

  private var summary: String {
    guard let status else { return "Stored code snapshots" }
    let size = ByteCountFormatter.string(fromByteCount: Int64(status.bytes), countStyle: .file)
    return "\(status.taskCount) task comparisons · \(status.recoveryCount) recovery copies · \(size)"
  }

  private func request(body: [String: Bool]? = nil) async {
    guard !busy else { return }
    busy = true; error = nil
    defer { busy = false }
    do {
      status = try await GitReviewAPI.request("settings", body: body?.mapValues { $0 as Any })
      if body != nil { NotificationCenter.default.post(name: .gitReviewChanged, object: nil) }
    } catch { self.error = error.localizedDescription }
  }
}
