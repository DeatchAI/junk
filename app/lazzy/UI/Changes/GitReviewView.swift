import AppKit
import SwiftUI

struct GitReviewView: View {
  @ObservedObject var model: GitReviewModel
  var onClose: () -> Void
  var onZoom: () -> Void = {}
  @ObservedObject private var theme = ThemeManager.shared
  @State private var showSidebar = true
  @State private var splitDiff = true

  private var files: [GitFileChange] { model.review?.files ?? [] }
  private var projectName: String { URL(fileURLWithPath: model.review?.repository?.root ?? model.workspace).lastPathComponent }

  var body: some View {
    VStack(spacing: 0) {
      header
      rule
      if let notice = model.review?.notice { information(notice) }
      if let error = model.error {
        HStack(spacing: 8) {
          information(error)
          Button("Retry") { Task { await model.refresh() } }.buttonStyle(.plain).font(.appFont(size: 11)).padding(.trailing, 14)
        }
      }
      HStack(spacing: 0) {
        if showSidebar, !files.isEmpty {
          GitFileNavigator(files: files, selection: $model.selectedPath).frame(width: 225)
          Rectangle().fill(theme.textColor.opacity(0.09)).frame(width: 1)
        }
        VStack(spacing: 0) {
          if !files.isEmpty {
            GitFileTabs(files: files, selection: $model.selectedPath)
            rule
          }
          diffPanel
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
      rule
      footer
      if model.review?.repository != nil {
        rule
        GitRepositoryControls(workspace: model.workspace, files: files,
          scope: model.sessionScope ? "session" : model.projectScope ? "project" : "task",
          scopeID: model.sessionScope ? model.conversationID : model.runID,
          endpoint: model.endpoint)
      }
      if let notice = model.notice { information(notice) }
    }
    .foregroundStyle(theme.textColor).background(theme.solidBackground).tint(theme.textColor)
    .preferredColorScheme(theme.surfaceColorScheme)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(theme.textColor.opacity(0.14), lineWidth: 0.7).allowsHitTesting(false) }
    .sheet(item: $model.preview) { preview in confirmation(preview) }
    .task(id: "\(model.runID ?? "project")|\(model.conversationID ?? "")|\(model.sessionScope)|\(model.projectScope)") { await model.refresh() }
    .onExitCommand(perform: onClose)
    .onReceive(NotificationCenter.default.publisher(for: .gitReviewChanged)) { _ in Task { await model.refresh() } }
  }

  private var rule: some View { Rectangle().fill(theme.textColor.opacity(0.09)).frame(height: 1) }

  private var header: some View {
    HStack(spacing: 10) {
      GitReviewIconButton(symbol: "sidebar.left", label: showSidebar ? "Hide file tree" : "Show file tree") { showSidebar.toggle() }
      HStack(spacing: 7) {
        Text(projectName).font(.appFont(size: 12, weight: .medium)).lineLimit(1)
        if let branch = model.review?.repository?.branch {
          Image(systemName: "arrow.triangle.branch").font(.system(size: 10))
          Text(branch).font(.appFont(size: 11)).lineLimit(1)
        }
      }.foregroundStyle(theme.secondaryTextColor).allowsHitTesting(false)
      Spacer(minLength: 16)
      if model.isLoading { ProgressView().controlSize(.mini) }
      if model.conversationID != nil, model.runID != nil {
        HStack(spacing: 2) {
          scopeButton("This chat", selected: model.sessionScope) { model.sessionScope = true; model.projectScope = false }
          scopeButton("Last task", selected: !model.sessionScope) { model.sessionScope = false; model.projectScope = false }
        }.padding(3).background(theme.textColor.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
          .disabled(model.isMutating)
      } else {
        Text(model.projectScope ? "Project changes" : "Task changes").font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
      }
      GitReviewIconButton(symbol: "arrow.clockwise", label: "Refresh changes") { Task { await model.refresh() } }
      GitReviewIconButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Resize window", action: onZoom)
      GitReviewIconButton(symbol: "xmark", label: "Close changes", action: onClose).keyboardShortcut("w", modifiers: .command)
    }
    .padding(.horizontal, 10).frame(height: 46)
    .background { GitWindowDragRegion() }
  }

  private func scopeButton(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(text).font(.appFont(size: 11, weight: selected ? .medium : .regular))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .foregroundStyle(selected ? theme.textColor : theme.secondaryTextColor)
        .background(selected ? theme.textColor.opacity(0.075) : .clear, in: RoundedRectangle(cornerRadius: 5))
    }.buttonStyle(.plain)
  }

  @ViewBuilder private var diffPanel: some View {
    if let file = model.selectedFile {
      VStack(spacing: 0) {
        HStack(spacing: 8) {
          breadcrumbs(file)
          Spacer(minLength: 8)
          if file.reason == nil || file.diff?.isEmpty == false || file.binary {
            GitChangeCounts(additions: file.additions, deletions: file.deletions, binary: file.binary)
          }
          GitReviewIconButton(symbol: splitDiff ? "rectangle.split.2x1" : "rectangle", label: splitDiff ? "Show unified diff" : "Show split diff") { splitDiff.toggle() }
          if !model.projectScope, !model.sessionScope, file.discarded != true {
            AppActionMenu(actions: [
              .init(title: "Discard file changes…", symbol: "trash", isEnabled: model.canDiscardTask) {
                Task { await model.prepare(paths: [file.path]) }
              },
            ]) { Image(systemName: "ellipsis").frame(width: 12) }
            .accessibilityLabel("File actions")
          }
        }.padding(.horizontal, 14).frame(height: 36)
        rule
        if let reason = file.reason, file.diff?.isEmpty == false { information(reason) }
        if file.discarded == true {
          emptyState("Changes discarded", detail: "Use Undo discard to bring them back.")
        } else if file.binary {
          emptyState("Binary file changed", detail: "A text comparison isn't available for this file.")
        } else if file.diff?.isEmpty != false {
          emptyState(file.reason == nil ? "No text changes" : "Snapshot unavailable", detail: file.reason ?? "This file's contents are unchanged.")
        } else {
          if splitDiff {
            HStack(spacing: 0) {
              paneLabel("Before", detail: model.sessionScope ? "Chat start" : model.projectScope ? "Git base" : "Task start", color: theme.gitReviewPalette.deletion)
              Rectangle().fill(theme.textColor.opacity(0.09)).frame(width: 1)
              paneLabel("After", detail: model.projectScope ? "Working tree" : "Latest snapshot", color: theme.gitReviewPalette.addition)
            }.frame(height: 29).background(theme.textColor.opacity(0.015))
            rule
          }
          GitDiffTextView(text: file.diff ?? "", foreground: NSColor(theme.textColor), background: NSColor(theme.solidBackground), split: splitDiff)
            .id(file.path)
        }
      }
    } else if model.isLoading {
      emptyState("Reading changes…", detail: "")
    } else {
      emptyState(files.isEmpty ? "No changes to review" : "Choose a file", detail: model.review?.repository == nil
        ? model.error ?? model.review?.notice ?? "Choose a Git project to review changes."
        : model.projectScope ? "Your working tree is clean." : "Files changed in this chat will appear here.")
    }
  }

  private func breadcrumbs(_ file: GitFileChange) -> some View {
    HStack(spacing: 5) {
      ForEach(Array(file.path.split(separator: "/").enumerated()), id: \.offset) { index, component in
        if index > 0 { Image(systemName: "chevron.right").font(.system(size: 7)) }
        if index == file.path.split(separator: "/").count - 1 {
          Image(systemName: file.symbol).font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.gitReviewPalette.icon(for: file)))
        }
        Text(String(component)).lineLimit(1).truncationMode(.middle)
      }
    }.font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor).help(file.path)
  }

  private func paneLabel(_ title: String, detail: String, color: NSColor) -> some View {
    HStack(spacing: 8) {
      Text(title).font(.appFont(size: 10, weight: .medium)).foregroundStyle(Color(nsColor: color))
      Text(detail).font(.appFont(size: 10)).foregroundStyle(theme.secondaryTextColor)
      Spacer()
    }.padding(.horizontal, 16).frame(maxWidth: .infinity)
  }

  private var footer: some View {
    HStack(spacing: 10) {
      Text("\(files.count) \(files.count == 1 ? "file" : "files")")
      Text(model.sessionScope ? "Changed in this chat" : model.projectScope ? "Working tree" : "Changed in this task")
      Spacer(minLength: 8)
      if model.sessionScope {
        if model.review?.recoveryID != nil {
          Button("Undo session revert…") { Task { await model.prepare(undo: true) } }.disabled(model.isMutating)
        }
        Button("Revert session…") { Task { await model.prepare() } }.disabled(model.isMutating || files.isEmpty)
      } else {
        if model.review?.recoveryID != nil {
          Button("Undo discard…") { Task { await model.prepare(undo: true) } }.disabled(model.isMutating)
        }
        if model.runID != nil, !model.projectScope {
          Button("Discard task changes…") { Task { await model.prepare() } }.disabled(!model.canDiscardTask)
        }
      }
    }.buttonStyle(.plain).font(.appFont(size: 10)).foregroundStyle(theme.secondaryTextColor)
      .padding(.horizontal, 14).frame(height: 32)
  }

  private func confirmation(_ preview: GitRestorePreview) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(preview.isUndo ? "Undo this revert?" : preview.isSession ? "Revert this session?" : "Discard these changes?").font(.appFont(size: 17, weight: .medium))
      Text(preview.isUndo ? "Restore the contents saved immediately before this revert." : preview.isSession ? "Restore these files to before this chat changed them. Earlier edits and Git staging will be kept. The current contents will be saved for Undo." : "Restore these files to before this task started. Earlier edits and Git staging will be kept.")
        .font(.appFont(size: 13)).fixedSize(horizontal: false, vertical: true)
      ScrollView {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(preview.paths, id: \.self) { Text($0).font(.system(size: 11, design: .monospaced)).textSelection(.enabled) }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.frame(maxHeight: 130)
      Text("Project: \(URL(fileURLWithPath: preview.repository).lastPathComponent)").font(.appFont(size: 11))
      Text("Recovery copies stay on this Mac for up to seven days. Manage them in Settings → Privacy & data.")
        .font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor).fixedSize(horizontal: false, vertical: true)
      HStack {
        Spacer()
        Button("Cancel") { model.preview = nil }.buttonStyle(GitConfirmationButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
        Button(preview.isUndo ? "Undo revert" : preview.isSession ? "Revert changes" : "Discard changes") { Task { await model.confirm() } }
          .buttonStyle(GitConfirmationButtonStyle(prominent: false))
      }
    }.padding(24).frame(width: 460).foregroundStyle(theme.textColor).background(theme.solidBackground).tint(theme.textColor)
      .preferredColorScheme(theme.surfaceColorScheme).onExitCommand { model.preview = nil }
  }

  private func information(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "info.circle")
      Text(text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }.font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor).padding(12)
  }

  private func emptyState(_ title: String, detail: String) -> some View {
    VStack(spacing: 10) {
      Image(systemName: "doc.text.magnifyingglass").font(.system(size: 24, weight: .light))
      Text(title).font(.appFont(size: 13, weight: .medium))
      if !detail.isEmpty { Text(detail).font(.appFont(size: 11)).multilineTextAlignment(.center).frame(maxWidth: 360) }
    }.foregroundStyle(theme.secondaryTextColor).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct GitConfirmationButtonStyle: ButtonStyle {
  let prominent: Bool
  @ObservedObject private var theme = ThemeManager.shared
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.appFont(size: 12, weight: .medium))
      .padding(.horizontal, 12).padding(.vertical, 7)
      .foregroundStyle(prominent ? theme.solidBackground : theme.textColor)
      .background(prominent ? theme.textColor : theme.textColor.opacity(0.10))
      .clipShape(RoundedRectangle(cornerRadius: 6)).opacity(configuration.isPressed ? 0.75 : 1)
  }
}
