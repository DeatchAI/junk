import SwiftUI

enum ComposerProjectMenuLayout {
  static let width: CGFloat = 264
  static let rowHeight: CGFloat = 28
  static let rowSpacing: CGFloat = 1
  static let maximumListHeight: CGFloat = 144
  static let cornerRadius: CGFloat = 12
}

struct ComposerProjectMenu: View {
  @ObservedObject var store: WorkingDirectoryStore
  @ObservedObject var library: ComposerProjectLibrary
  @Binding var query: String
  let onSelect: () -> Void
  let onAdd: () -> Void
  @ObservedObject private var theme = ThemeManager.shared
  @FocusState private var isSearchFocused: Bool

  private var projects: [ComposerProject] { library.matching(query) }

  private enum RowIcon { case folder, addProject, clear }

  private var menuShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: ComposerProjectMenuLayout.cornerRadius, style: .continuous)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryTextColor)
        TextField("Search projects", text: $query)
          .textFieldStyle(.plain).focused($isSearchFocused)
      }
      .font(.appFont(size: 12)).padding(.horizontal, 8).padding(.vertical, 6)

      Divider().padding(.horizontal, 7)
      row("New project", icon: .addProject, action: onAdd)

      if !projects.isEmpty {
        ScrollView {
          VStack(spacing: ComposerProjectMenuLayout.rowSpacing) {
            ForEach(projects) { project in
              let available = project.isAvailable
              row(project.name, icon: .folder, selected: store.url?.path == project.path, enabled: available) {
                store.setDirectory(project.resolvedURL())
                onSelect()
              }
              .help(available ? project.path : "Folder unavailable: \(project.path)")
            }
          }
        }
        .frame(height: min(CGFloat(projects.count)
          * (ComposerProjectMenuLayout.rowHeight + ComposerProjectMenuLayout.rowSpacing)
          - ComposerProjectMenuLayout.rowSpacing, ComposerProjectMenuLayout.maximumListHeight))
        .scrollIndicators(.hidden)
      } else {
        Text(query.isEmpty ? "Add a folder to save your first project." : "No projects found")
          .font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
          .padding(.horizontal, 8).padding(.vertical, 7)
      }

      Divider().padding(.horizontal, 7).padding(.vertical, 3)
      row("Don’t work in a project", icon: .clear, selected: store.url == nil) {
        store.clear()
        onSelect()
      }
    }
    .padding(5).frame(width: ComposerProjectMenuLayout.width)
    .foregroundStyle(theme.textColor)
    .themedSurface(in: menuShape)
    .overlay {
      menuShape
        .stroke(theme.textColor.opacity(theme.mode == .liquidGlass ? 0 : 0.1), lineWidth: 0.5)
        .allowsHitTesting(false)
    }
    .clipShape(menuShape)
    .preferredColorScheme(theme.surfaceColorScheme)
    .onAppear { isSearchFocused = true }
  }

  private func row(_ title: String, icon: RowIcon, selected: Bool = false, enabled: Bool = true,
    action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        rowIcon(icon).frame(width: 16, height: 16)
        Text(title).font(.appFont(size: 12)).lineLimit(1).truncationMode(.middle)
        Spacer(minLength: 6)
        if selected { Image(systemName: "checkmark").font(.appFont(size: 10, weight: .semibold)) }
      }
      .foregroundStyle(theme.textColor)
      .padding(.horizontal, 7)
      .frame(maxWidth: .infinity, minHeight: ComposerProjectMenuLayout.rowHeight,
        maxHeight: ComposerProjectMenuLayout.rowHeight, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(ComposerButtonStyle(cornerRadius: 6))
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.4)
  }

  @ViewBuilder private func rowIcon(_ icon: RowIcon) -> some View {
    switch icon {
    case .folder: ComposerFolderIcon()
    case .addProject: ComposerFolderIcon(isAdding: true)
    case .clear: Image(systemName: "xmark").font(.appFont(size: 11, weight: .medium))
    }
  }
}
