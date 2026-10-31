import AppKit
import SwiftUI

struct ComposerProjectSelector: View {
  @ObservedObject var store: WorkingDirectoryStore
  @ObservedObject var library: ComposerProjectLibrary
  @ObservedObject private var remoteMachines = RemoteMachineStore.shared
  var onMenuPresentationChanged: (Bool) -> Void = { _ in }
  @ObservedObject private var theme = ThemeManager.shared
  @State private var isPresented = false
  @State private var query = ""
  @State private var presentationID = UUID()

  init(store: WorkingDirectoryStore, onMenuPresentationChanged: @escaping (Bool) -> Void = { _ in }) {
    self.store = store
    self.library = store.projects
    self.onMenuPresentationChanged = onMenuPresentationChanged
  }

  private var contentRevision: AnyHashable {
    AnyHashable([presentationID.uuidString, query, store.path ?? ""] + library.projects.map(\.path)
      + remoteMachines.workspaces.map(\.id))
  }

  var body: some View {
    Button {
      if !isPresented {
        query = ""
        presentationID = UUID()
      }
      isPresented.toggle()
    } label: {
      HStack(spacing: 6) {
        ComposerFolderIcon().frame(width: 16, height: 16)
        Text(store.displayName)
          .font(.appFont(size: 11, weight: .medium))
          .lineLimit(1).truncationMode(.middle)
        Image(systemName: "chevron.down").font(.appFont(size: 8, weight: .semibold))
      }
      .foregroundStyle(theme.secondaryTextColor)
      .padding(.horizontal, 7).frame(height: 24)
      .contentShape(Rectangle())
    }
    .buttonStyle(ComposerButtonStyle())
    .disabled(store.selectionLocked)
    .help("Choose a project")
    .accessibilityLabel("Choose project: \(store.displayName)")
    .background {
      DropdownPanelAnchor(isPresented: $isPresented, menuWidth: ComposerProjectMenuLayout.width,
        menu: ComposerProjectMenu(store: store, library: library, query: $query,
          onSelect: { isPresented = false }, onAdd: addProject).id(presentationID),
        contentRevision: contentRevision, acceptsKeyboardInput: true)
    }
    .onChange(of: isPresented) { _, presented in onMenuPresentationChanged(presented) }
    .onDisappear { onMenuPresentationChanged(false) }
  }

  private func addProject() {
    isPresented = false
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Add project"
    panel.message = "Choose a project folder."
    panel.begin { response in
      if response == .OK, let url = panel.url { store.setDirectory(url) }
    }
  }
}
