import AppKit
import SwiftUI

struct ComposerAttachmentMenuRow: View {
  let title: String
  var subtitle: String? = nil
  let systemImage: String
  var showsSubmenu = false
  var showsDetail = false
  var isSelected = false
  var isHighlighted = false
  var onHover: (() -> Void)?
  let action: () -> Void

  @ObservedObject private var theme = ThemeManager.shared
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 7) {
        Image(systemName: systemImage)
          .font(.appFont(size: 12))
          .foregroundColor(theme.textColor.opacity(0.7))
          .frame(width: 16)

          Text(title)
            .font(.appFont(size: 13))
            .foregroundColor(theme.textColor)
            .lineLimit(1)

          Spacer(minLength: 4)
          if showsDetail, let subtitle = subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(.appFont(size: 11, weight: .regular))
              .foregroundColor(theme.secondaryTextColor)
              .lineLimit(1)
              .truncationMode(.middle).frame(maxWidth: 100, alignment: .trailing)
          }

        if isSelected {
          Image(systemName: "checkmark")
            .font(.appFont(size: 11, weight: .semibold))
            .foregroundColor(theme.accentColor)
        } else if showsSubmenu {
          Image(systemName: "chevron.right").font(.system(size: 8, weight: .medium))
            .foregroundStyle(theme.secondaryTextColor)
        }
      }
      .foregroundColor(theme.textColor)
      .padding(.horizontal, 7)
      .frame(maxWidth: .infinity, minHeight: ComposerMenuStyle.rowHeight, maxHeight: ComposerMenuStyle.rowHeight,
        alignment: .leading)
      .background {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(isHighlighted || isHovered ? theme.textColor.opacity(0.06) : .clear)
      }
    }
    .buttonStyle(.plain)
    .help(subtitle ?? title)
    .onHover {
      isHovered = $0
      if $0 { onHover?() }
    }
  }
}

struct ComposerAttachmentMenuHeader: View {
  let title: String
  let onBack: () -> Void

  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(spacing: 8) {
      Button(action: onBack) {
        Image(systemName: "chevron.left")
          .font(.appFont(size: 11, weight: .semibold))
          .frame(width: 20, height: 24)
      }
      .buttonStyle(.plain)
      .help("Back")

      Text(title)
        .font(.appFont(size: 12, weight: .medium))
      Spacer()
    }
    .foregroundColor(theme.textColor)
    .padding(.horizontal, 4)
    .padding(.bottom, 3)
  }
}

struct ComposerAttachmentMenuEmptyState: View {
  let text: String

  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Text(text)
      .font(.appFont(size: 12))
      .foregroundColor(theme.secondaryTextColor)
      .frame(maxWidth: .infinity, minHeight: 48)
  }
}

struct InlineFileBrowser: View {
  @ObservedObject var catalog: InlineWorkspaceCatalog
  let onBack: () -> Void
  let onUpdateQuery: (String) -> Void
  let onChooseWorkingDirectory: () -> Void
  let onChooseFromMac: () -> Void
  let onSelect: (URL) -> Void

  @ObservedObject private var theme = ThemeManager.shared
  @State private var selectedIndex = 0
  @State private var keyMonitor: Any?

  private var relativeHeaderPath: String {
    guard let root = catalog.workingDirectory else {
      return "Choose a folder"
    }

    let rootName = root.lastPathComponent.isEmpty ? root.path : root.lastPathComponent
    let rawQuery = catalog.query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawQuery.isEmpty else { return rootName }

    let path = rawQuery.hasPrefix("./")
      ? String(rawQuery.dropFirst(2))
      : rawQuery
    let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard !trimmedPath.isEmpty, path.contains("/") else { return rootName }

    if trimmedPath == rootName || trimmedPath.hasPrefix(rootName + "/") {
      return path
    }
    return "\(rootName)/\(path)"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 8) {
        Button(action: navigateBack) {
          Image(systemName: "chevron.left")
            .font(.appFont(size: 11, weight: .semibold))
            .frame(width: 24, height: 28)
        }
        .buttonStyle(.plain)
        .help("Back")

        Text(relativeHeaderPath)
          .font(.appFont(size: 13, weight: .medium))
          .foregroundColor(theme.secondaryTextColor)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: 190, alignment: .leading)

        Spacer()

        if catalog.isSearching {
          ProgressView()
            .controlSize(.mini)
            .help("Loading files")
        }

        Button(action: onChooseFromMac) {
          Image(systemName: "paperclip")
            .font(.appFont(size: 14, weight: .medium))
            .frame(width: 26, height: 28)
        }
          .buttonStyle(.plain)
          .foregroundColor(theme.accentColor)
          .help("Attach a file or folder from Mac")
      }
      .foregroundColor(theme.textColor)
      .padding(.horizontal, 4)

      resultList
    }
    .padding(5)
    .onAppear {
      guard catalog.workingDirectory != nil else {
        onChooseFromMac()
        return
      }
      catalog.search(query: catalog.query)
      setupKeyMonitor()
    }
    .onChange(of: catalog.results) { _, found in
      if found.isEmpty {
        selectedIndex = 0
      } else if !found.indices.contains(selectedIndex) {
        selectedIndex = 0
      } else {
        selectedIndex = min(selectedIndex, found.count - 1)
      }
    }
    .onDisappear {
      catalog.cancel()
      removeKeyMonitor()
    }
  }

  @ViewBuilder
  private var resultList: some View {
    if catalog.state == .needsMoreCharacters {
      ContentUnavailableView(
        "Keep typing",
        systemImage: "text.cursor",
        description: Text("Type at least two characters to search filenames, or enter a folder path.")
      )
      .frame(height: 294)
    } else if catalog.state == .noWorkingDirectory {
      VStack(spacing: 10) {
        ContentUnavailableView(
          "No working directory",
          systemImage: "folder.badge.questionmark",
          description: Text("Choose a project folder to search its files and folders.")
        )

        HStack(spacing: 8) {
          Button("Choose working directory", action: onChooseWorkingDirectory)
            .buttonStyle(.borderedProminent)
          Button(action: onChooseFromMac) {
            Image(systemName: "paperclip")
              .frame(width: 28, height: 28)
          }
          .buttonStyle(.bordered)
          .help("Attach a file or folder from Mac")
        }
      }
      .frame(maxWidth: .infinity, minHeight: 294)
    } else if catalog.state == .spotlightUnavailable {
      ContentUnavailableView(
        "Spotlight search unavailable",
        systemImage: "magnifyingglass.circle",
        description: Text("Open a folder path or use the attach button to attach a file.")
      )
      .frame(height: 294)
    } else if catalog.results.isEmpty && !catalog.isSearching {
      ContentUnavailableView(
        "No matching files",
        systemImage: "doc.text.magnifyingglass",
        description: Text(catalog.query.isEmpty ? "Choose from your Mac or open a folder below." : "Try a folder path such as Desktop/ or choose from your Mac.")
      )
      .frame(height: 294)
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 2) {
            ForEach(Array(catalog.results.enumerated()), id: \.element.id) { index, item in
              InlineFileResultRow(
                item: item,
                isSelected: selectedIndex == index,
                onSelect: { onSelect(item.url) },
                relativeRoot: catalog.workingDirectory
              )
              .id(item.id)
              .onHover { isHovering in
                if isHovering { selectedIndex = index }
              }
            }
          }
        }
        .onChange(of: selectedIndex) { _, newValue in
          guard catalog.results.indices.contains(newValue) else { return }
          withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(catalog.results[newValue].id, anchor: .center)
          }
        }
      }
      .frame(height: min(CGFloat(max(catalog.results.count, 1)) * (ComposerMenuStyle.rowHeight + 1), 240))
      .overlay {
        if catalog.isSearching && catalog.results.isEmpty {
          ProgressView().controlSize(.small)
        }
      }
    }
  }

  private func setupKeyMonitor() {
    guard keyMonitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let modifiers = event.modifierFlags.intersection([.command, .option, .control])
      guard modifiers.isEmpty else { return event }

      switch Int(event.keyCode) {
      case 125:
        moveSelection(by: 1)
        return nil
      case 126:
        moveSelection(by: -1)
        return nil
      case 36, 76:
        selectCurrent()
        return nil
      case 49:
        openCurrentDirectory()
        return nil
      case 53, 123:
        navigateBack()
        return nil
      default:
        return event
      }
    }
  }

  private func removeKeyMonitor() {
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
  }

  private func moveSelection(by delta: Int) {
    guard !catalog.results.isEmpty else { return }
    selectedIndex = min(max(selectedIndex + delta, 0), catalog.results.count - 1)
  }

  private func selectCurrent() {
    guard catalog.results.indices.contains(selectedIndex) else { return }
    onSelect(catalog.results[selectedIndex].url)
  }

  private func openCurrentDirectory() {
    guard catalog.results.indices.contains(selectedIndex) else { return }
    let item = catalog.results[selectedIndex]
    guard item.isDirectory else { return }
    onUpdateQuery(item.rootRelativeQueryPath(from: catalog.workingDirectory) + "/")
  }

  private func navigateBack() {
    let normalized = catalog.query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      onBack()
      return
    }

    let path = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let components = path.split(separator: "/", omittingEmptySubsequences: true)
    guard components.count > 1 else {
      onUpdateQuery("")
      return
    }

    onUpdateQuery(components.dropLast().joined(separator: "/") + "/")
  }
}

struct InlineFileResultRow: View {
  let item: InlineWorkspaceItem
  let isSelected: Bool
  let onSelect: () -> Void
  let relativeRoot: URL?

  var body: some View {
    ComposerAttachmentMenuRow(title: item.name, subtitle: item.relativePath(from: relativeRoot),
      systemImage: item.systemImage, showsDetail: true, isHighlighted: isSelected, action: onSelect)
      .help(item.url.path)
  }
}

struct ComposerBrowserTabRow: View {
  let tab: BrowserTab
  let isSelected: Bool
  let isHighlighted: Bool
  let onHover: () -> Void
  let onSelect: () -> Void

  var body: some View {
    ComposerAttachmentMenuRow(title: tab.title.isEmpty ? tab.url : tab.title,
      subtitle: URL(string: tab.url)?.host ?? tab.url, systemImage: "globe", showsDetail: true,
      isSelected: isSelected, isHighlighted: isHighlighted, onHover: onHover, action: onSelect)
      .help(tab.url)
  }
}
