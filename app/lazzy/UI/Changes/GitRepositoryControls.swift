import AppKit
import SwiftUI

struct GitRepositoryControls: View {
  let workspace: String
  let files: [GitFileChange]
  let scope: String
  let scopeID: String?
  var endpoint: RuntimeEndpoint = .local
  @StateObject private var model = GitWorkingModel()
  @ObservedObject private var theme = ThemeManager.shared
  @State private var showCommit = false
  @State private var showPush = false

  var body: some View {
    VStack(spacing: 6) {
      HStack(spacing: 10) {
        if let status = model.status, status.repository != nil {
          if let upstream = status.upstream {
            Text(upstream).lineLimit(1).help(upstream)
            if status.ahead > 0 { Text("↑\(status.ahead)").monospacedDigit() }
            if status.behind > 0 { Text("↓\(status.behind)").monospacedDigit() }
          } else { Text(status.remotes.isEmpty ? "Local repository" : "No upstream branch") }
          Spacer(minLength: 8)
          if model.isBusy { ProgressView().controlSize(.mini) }
          Button { model.clearFeedback(); showCommit = true } label: { Label("Commit…", systemImage: "checkmark.circle") }
            .disabled(!status.canCommit || model.isBusy || files.isEmpty)
          Button { model.clearFeedback(); showPush = true } label: { Label("Push…", systemImage: "arrow.up") }
            .disabled(!status.canPush || model.isBusy).help(status.pushReason ?? "Push commits to the remote branch")
        } else {
          Text("Reading Git status…")
          Spacer()
        }
      }.font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
      if let notice = model.notice {
        Text(notice).font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor).frame(maxWidth: .infinity, alignment: .leading)
      }
      if let error = model.error {
        HStack(alignment: .top, spacing: 8) {
          Text(error).font(.appFont(size: 11)).foregroundStyle(Color(nsColor: theme.gitReviewPalette.deletion))
            .lineLimit(3).textSelection(.enabled)
          Button("Refresh") { Task { await model.refresh(workspace: workspace) } }.font(.appFont(size: 11))
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
    }.buttonStyle(AppButtonStyle()).padding(.horizontal, 14).padding(.vertical, 9).tint(theme.textColor)
      .task(id: "\(workspace)|\(endpoint.machineID?.uuidString ?? "local")") {
        model.endpoint = endpoint
        await model.refresh(workspace: workspace)
      }
      .onReceive(NotificationCenter.default.publisher(for: .serverDidBecomeReady)) { _ in Task { await model.refresh(workspace: workspace) } }
      .onReceive(NotificationCenter.default.publisher(for: .gitReviewChanged)) { _ in Task { await model.refresh(workspace: workspace) } }
      .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await model.refresh(workspace: workspace) } }
      .sheet(isPresented: $showCommit) {
        GitCommitSheet(model: model, workspace: workspace, files: files.filter { $0.discarded != true }, scope: scope, scopeID: scopeID)
      }
      .sheet(isPresented: $showPush) { GitPushSheet(model: model, workspace: workspace) }
  }
}

private struct GitCommitSheet: View {
  @ObservedObject var model: GitWorkingModel
  let workspace: String
  let files: [GitFileChange]
  let scope: String
  let scopeID: String?
  @State private var message = ""
  @State private var selected = Set<String>()
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Commit to \(model.status?.repository?.branch ?? "this branch")").font(.appFont(size: 17, weight: .medium))
      Text("Commit message").font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
      AppTextEditor(title: "Commit message", text: $message, height: 64)
      HStack {
        Text("\(selected.count) files selected").font(.appFont(size: 11))
        Spacer()
        Button(selected.count == files.count ? "Deselect all" : "Select all") {
          selected = selected.count == files.count ? [] : Set(files.map(\.path))
        }.buttonStyle(.plain).font(.appFont(size: 11))
      }.foregroundStyle(theme.secondaryTextColor)
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(files) { file in
            Toggle(isOn: Binding(get: { selected.contains(file.path) }, set: { value in
              if value { selected.insert(file.path) } else { selected.remove(file.path) }
            })) {
              HStack(spacing: 7) {
                Image(systemName: file.symbol).foregroundStyle(Color(nsColor: theme.gitReviewPalette.icon(for: file)))
                Text(file.name).lineLimit(1)
                Spacer()
                Text(file.statusSymbol).foregroundStyle(Color(nsColor: theme.gitReviewPalette.status(for: file)))
              }.font(.appFont(size: 12))
            }.toggleStyle(.checkbox).help(file.path).accessibilityLabel(file.path)
          }
        }.padding(.vertical, 4)
      }.frame(height: 180)
      Text("Commits the current contents of the selected files, including earlier edits in those files. Other staged files stay staged.")
        .font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor).fixedSize(horizontal: false, vertical: true)
      if let error = model.error {
        Text(error).font(.appFont(size: 11)).foregroundStyle(Color(nsColor: theme.gitReviewPalette.deletion))
          .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        Spacer()
        if model.isBusy { ProgressView().controlSize(.small) }
        Button("Cancel") { dismiss() }.disabled(model.isBusy).keyboardShortcut(.cancelAction)
        Button("Commit") {
          Task { if await model.commit(workspace: workspace, scope: scope, id: scopeID, paths: selected.sorted(), message: message) { dismiss() } }
        }.disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selected.isEmpty || model.isBusy)
      }
    }.buttonStyle(AppButtonStyle()).padding(22).frame(width: 460).foregroundStyle(theme.textColor).background(theme.solidBackground).tint(theme.textColor)
      .preferredColorScheme(theme.surfaceColorScheme).onAppear { selected = Set(files.map(\.path)) }
  }
}

private struct GitPushSheet: View {
  @ObservedObject var model: GitWorkingModel
  let workspace: String
  @State private var remote = ""
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Push \(model.status?.repository?.branch ?? "branch")").font(.appFont(size: 17, weight: .medium))
      HStack {
        Text("Remote").font(.appFont(size: 12))
        AppSelect(title: "Remote", selection: $remote,
          options: (model.status?.remotes ?? []).map { AppSelectOption(title: $0, value: $0) })
      }
      Text("Destination: \(remote)/\(model.status?.remoteBranch ?? "")").font(.appFont(size: 12))
      if model.status?.upstream == nil {
        Text("This remote branch becomes the upstream for future pushes.").font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
      }
      if let error = model.error {
        Text(error).font(.appFont(size: 11)).foregroundStyle(Color(nsColor: theme.gitReviewPalette.deletion))
          .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        Spacer()
        if model.isBusy { ProgressView().controlSize(.small) }
        Button("Cancel") { dismiss() }.disabled(model.isBusy).keyboardShortcut(.cancelAction)
        Button("Push") { Task { if await model.push(workspace: workspace, remote: remote) { dismiss() } } }
          .disabled(remote.isEmpty || model.isBusy || model.status?.canPush != true)
      }
    }.buttonStyle(AppButtonStyle()).padding(22).frame(width: 400).foregroundStyle(theme.textColor).background(theme.solidBackground).tint(theme.textColor)
      .preferredColorScheme(theme.surfaceColorScheme).onAppear { remote = model.status?.remote ?? model.status?.remotes.first ?? "" }
  }
}
