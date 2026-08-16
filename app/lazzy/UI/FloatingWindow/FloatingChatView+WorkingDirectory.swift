import AppKit
import SwiftUI

private struct WorkingDirectorySelector: View {
  @ObservedObject var store: WorkingDirectoryStore

  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(spacing: 7) {
      Button(action: chooseDirectory) {
        Image(systemName: store.url == nil ? "folder.badge.plus" : "folder")
          .font(.appFont(size: 12, weight: .medium))
          .foregroundColor(store.url == nil ? theme.secondaryTextColor : theme.accentColor)

        Text(store.displayName)
          .font(.appFont(size: 11, weight: .medium))
          .foregroundColor(
            store.url == nil ? theme.secondaryTextColor : theme.textColor.opacity(0.78)
          )
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .buttonStyle(.plain)
      .help(store.url == nil ? "Choose a working directory" : "Change working directory")

      if store.url != nil {
        Button(action: store.clear) {
          Image(systemName: "xmark")
            .font(.appFont(size: 9, weight: .bold))
            .foregroundColor(theme.secondaryTextColor)
            .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .help("Clear working directory")
      }

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func chooseDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Use Folder"
    panel.message = "Choose the folder you are working in. File search will stay inside it."
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      store.setDirectory(url)
    }
  }
}

struct WorkingDirectoryTray: View {
  @ObservedObject var store: WorkingDirectoryStore

  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    WorkingDirectorySelector(store: store)
      .padding(.horizontal, 13)
      .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
      .background {
        trayShape.fill(theme.solidBackground)
      }
      // .overlay(alignment: .top) {
      //   Rectangle()
      //     .fill(theme.textColor.opacity(0.12))
      //     .frame(height: 0.6)
      // }
      .clipShape(trayShape)
      .padding(.horizontal, 14)
      .padding(.bottom, 7)
      // .padding(.top, -6)
  }

  private var trayShape: UnevenRoundedRectangle {
    UnevenRoundedRectangle(
      cornerRadii: .init(
        topLeading: 0,
        bottomLeading: theme.borderRadius,
        bottomTrailing: theme.borderRadius,
        topTrailing: 0
      ),
      style: .continuous
    )
  }
}
