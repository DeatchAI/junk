import AppKit
import Combine
import SwiftUI

@MainActor final class GitTaskCardModel: ObservableObject {
  @Published var summary: GitTaskSummary?
  @Published var files: [GitFileChange] = []
  @Published private(set) var error: String?
  private var loadID = UUID()
  private var loadedContext: String?

  func load(workspace: String?, runID: String?, conversationID: String?, prompt: String,
            timestamp: Int?, ordinal: Int?, endpoint: RuntimeEndpoint) async {
    let id = UUID(); loadID = id
    guard let workspace else { summary = nil; files = []; error = nil; loadedContext = nil; return }
    let context = workspace + "|" + (endpoint.machineID?.uuidString ?? "local") + "|"
      + (conversationID ?? runID ?? ConversationPrompt.fingerprint(prompt))
    if context != loadedContext {
      summary = nil; files = []; error = nil; loadedContext = context
    }
    do {
      if let conversationID {
        let review = try await GitReviewAPI.review(workspace: workspace, runID: runID, project: false,
          conversationID: conversationID, endpoint: endpoint)
        guard loadID == id, !Task.isCancelled else { return }
        summary = review.task; files = review.files; error = nil
      } else {
        let response: GitTaskList = try await GitReviewAPI.request("tasks", query: ["workspace": workspace], endpoint: endpoint)
        guard loadID == id, !Task.isCancelled else { return }
        summary = GitTaskMatcher.match(response.tasks, runID: runID, promptHash: ConversationPrompt.fingerprint(prompt), timestamp: timestamp, ordinal: ordinal)
        files = summary?.files.filter { $0.discarded != true } ?? []; error = nil
      }
    } catch {
      if loadID == id, !Task.isCancelled { self.error = error.localizedDescription }
    }
  }
}

/// A single action at the end of the chat, visible only when captured files changed.
struct GitTaskChangeCard: View {
  var workspace: String?
  var runID: String?
  var conversationID: String?
  var prompt: String
  var timestamp: Int?
  var ordinal: Int? = nil
  var revision = 0
  var endpoint: RuntimeEndpoint = .local
  @StateObject private var model = GitTaskCardModel()
  @ObservedObject private var theme = ThemeManager.shared
  @State private var hovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let summary = model.summary, !model.files.isEmpty {
        Button {
          GitChangeWindowController.open(workspace: summary.repository.root, runID: summary.runId,
            conversationID: conversationID, endpoint: endpoint)
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "rectangle.split.2x1").font(.system(size: 12))
              .foregroundStyle(Color(nsColor: theme.gitReviewPalette.modified))
            Text("Review diff").font(.appFont(size: 12, weight: .medium))
            Text("\(model.files.count) \(model.files.count == 1 ? "file" : "files")")
              .font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
            GitChangeCounts(additions: model.files.reduce(0) { $0 + $1.additions }, deletions: model.files.reduce(0) { $0 + $1.deletions })
            Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(theme.secondaryTextColor)
          }
          .padding(.horizontal, 11).padding(.vertical, 9)
          .foregroundStyle(theme.textColor)
          .background(theme.textColor.opacity(hovering ? 0.07 : 0.035), in: RoundedRectangle(cornerRadius: 8))
          .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(theme.textColor.opacity(0.10), lineWidth: 0.7) }
          .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }
          .accessibilityLabel("Review diff, \(model.files.count) files changed in this chat")
          .help("Review files changed in this chat")
      } else if let error = model.error {
        Button { Task { await load() } } label: {
          Label("Retry changes", systemImage: "arrow.clockwise")
            .font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
        }.buttonStyle(.plain).help(error).accessibilityLabel("Changes unavailable. Retry loading changes")
      }
    }
    .task(id: "\(workspace ?? "")|\(endpoint.machineID?.uuidString ?? "local")|\(runID ?? "")|\(conversationID ?? "")|\(prompt)|\(revision)") { await load() }
    .onReceive(NotificationCenter.default.publisher(for: .gitReviewChanged)) { _ in Task { await load() } }
    .onReceive(NotificationCenter.default.publisher(for: .serverDidBecomeReady)) { _ in Task { await load() } }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await load() } }
  }

  private func load() async {
    await model.load(workspace: workspace, runID: runID, conversationID: conversationID,
      prompt: prompt, timestamp: timestamp, ordinal: ordinal, endpoint: endpoint)
  }
}
