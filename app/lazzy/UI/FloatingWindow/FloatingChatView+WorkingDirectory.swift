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
  @State private var isExpanded = false

  private let collapsedHeight: CGFloat = 12
  private let expandedHeight: CGFloat = 38

  var body: some View {
    ZStack(alignment: .top) {
      trayContent
        .offset(y: isExpanded ? 0 : -(expandedHeight - collapsedHeight))

      if !isExpanded {
        collapsedHandle
      }
    }
    .frame(height: isExpanded ? expandedHeight : collapsedHeight, alignment: .top)
    .frame(maxWidth: .infinity, alignment: .top)
    .clipShape(trayShape)
    .padding(.horizontal, 14)
    .padding(.bottom, 7)
    .animation(.spring(response: 0.28, dampingFraction: 0.84), value: isExpanded)
  }

  private var trayContent: some View {
    traySurface(
      ZStack(alignment: .trailing) {
        WorkingDirectorySelector(store: store)

        Button(action: collapse) {
          Image(systemName: "chevron.down")
            .font(.appFont(size: 10, weight: .semibold))
            .foregroundColor(theme.secondaryTextColor)
            .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help("Hide working directory")
        .padding(.trailing, 8)
      }
      .padding(.horizontal, 13)
      .frame(maxWidth: .infinity, minHeight: expandedHeight, alignment: .leading)
    )
  }

  private var collapsedHandle: some View {
    traySurface(
      Button(action: toggleExpanded) {
        HStack(spacing: 0) {
          Spacer(minLength: 0)

          Image(systemName: "chevron.up")
            .font(.appFont(size: 10, weight: .semibold))
            .foregroundColor(theme.secondaryTextColor)
            .frame(width: 26, height: collapsedHeight)
        }
        .padding(.trailing, 8)
        .frame(height: collapsedHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Show working directory")
    )
  }

  private func traySurface<Content: View>(_ content: Content) -> some View {
    content
      .background {
        trayShape.fill(theme.solidBackground)
      }
      .overlay(alignment: .top) {
        Rectangle()
          .fill(theme.textColor.opacity(0.12))
          .frame(height: 0.6)
      }
      .clipShape(trayShape)
  }

  private func toggleExpanded() {
    if isExpanded {
      collapse()
    } else {
      expand()
    }
  }

  private func expand() {
    guard !isExpanded else { return }
    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
      isExpanded = true
    }
  }

  private func collapse() {
    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
      isExpanded = false
    }
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
