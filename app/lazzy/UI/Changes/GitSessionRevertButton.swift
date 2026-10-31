import AppKit
import SwiftUI

struct GitSessionRevertButton: View {
  let workspace: String?
  let conversationID: String?
  var endpoint: RuntimeEndpoint = .local
  var isBusy = false
  @State private var safety: GitSessionSafety?
  @ObservedObject private var theme = ThemeManager.shared

  private var undo: Bool { safety?.canUndo == true && safety?.canRevert != true }

  var body: some View {
    VStack(spacing: 0) {
      if let safety, safety.repository != nil, safety.hasChanges || safety.recoveryID != nil {
        Button {
          guard let workspace, let conversationID else { return }
          GitChangeWindowController.open(workspace: workspace, runID: safety.runID, discard: true,
            conversationID: conversationID, revertSession: true, undo: undo, endpoint: endpoint)
        } label: {
          Image(systemName: undo ? "arrow.uturn.forward" : "arrow.uturn.backward")
            .font(.appFont(size: 13)).foregroundStyle(theme.secondaryTextColor).frame(width: 26, height: 26)
        }.buttonStyle(ComposerButtonStyle())
          .disabled(isBusy || (!safety.canRevert && !safety.canUndo))
          .help(isBusy ? "Wait for this task to finish." : undo ? "Undo session revert" : safety.canRevert ? "Revert changes from this chat…" : safety.reason ?? "Session changes cannot be reverted safely.")
          .accessibilityLabel(undo ? "Undo session revert" : "Revert changes from this chat")
      }
    }
    .task(id: "\(workspace ?? "")|\(endpoint.machineID?.uuidString ?? "local")|\(conversationID ?? "")|\(isBusy)") { await refresh() }
    .onReceive(NotificationCenter.default.publisher(for: .gitReviewChanged)) { _ in Task { await refresh() } }
    .onReceive(NotificationCenter.default.publisher(for: .serverDidBecomeReady)) { _ in Task { await refresh() } }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await refresh() } }
  }

  private func refresh() async {
    guard let workspace, let conversationID else { safety = nil; return }
    do {
      let value: GitSessionSafety = try await GitReviewAPI.request("session-status",
        query: ["workspace": workspace, "conversation": conversationID], endpoint: endpoint)
      guard !Task.isCancelled else { return }; safety = value
    } catch { if !Task.isCancelled { safety = nil } }
  }
}
